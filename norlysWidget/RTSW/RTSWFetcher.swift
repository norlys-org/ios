//
//  RTSWFetcher.swift
//  norlysWidget
//
//  Swift port of the rtsw-fetcher package behind norlys.live/rtsw: the solar wind
//  magnetic field and plasma measured by every satellite at L1, each point tagged
//  with the satellite it came from and whether NOAA marks that satellite as active.
//  DSCOVR, ACE and SOLAR-1 come from NOAA's HAPI feed (HAPI.swift), STEREO-A from
//  NOAA's JSON feed and IMAP from LASP's I-ALiRT feed.
//

import Foundation

// MARK: - Data Models

/// Codes for the satellite a point came from. NOAA's HAPI numbers ACE, DSCOVR and
/// SOLAR-1; STEREO and IMAP come from separate feeds and take the unused slots.
enum RTSWSourceCode {
    static let ace = 1
    static let dscovr = 2
    static let stereo = 3
    static let solar1 = 4
    static let imap = 5
}

/// A solar wind component, named as on the website.
enum RTSWKey {
    case bt, by, bz, phi, theta, speed, density
}

/// What every point has in common, whichever measurement it carries.
protocol RTSWSample {
    var date: Date { get }
    /// 0 for good data, 1 for a suspected error, 2 for an identified error.
    var quality: Int { get }
    var source: Int { get }
    /// Whether NOAA marks the point's satellite as the active one at that time.
    var active: Bool { get set }
    /// The point's value for a component, NaN when it does not carry it.
    func value(_ key: RTSWKey) -> Double
}

/// RTSWMag: Magnetic field measurement (GSM coordinates; HGRTN for STEREO).
struct RTSWMag: RTSWSample {
    let date: Date
    let bt: Double
    let by: Double
    let bz: Double
    let phi: Double
    let theta: Double
    let quality: Int
    let source: Int
    var active = false

    func value(_ key: RTSWKey) -> Double {
        switch key {
        case .bt: return bt
        case .by: return by
        case .bz: return bz
        case .phi: return phi
        case .theta: return theta
        case .speed, .density: return .nan
        }
    }
}

/// RTSWPlasma: Plasma measurement.
struct RTSWPlasma: RTSWSample {
    let date: Date
    let speed: Double
    let density: Double
    let quality: Int
    let source: Int
    var active = false

    func value(_ key: RTSWKey) -> Double {
        switch key {
        case .speed: return speed
        case .density: return density
        default: return .nan
        }
    }
}

struct RTSWData {
    var mag: [RTSWMag] = []
    var plasma: [RTSWPlasma] = []

    /// Joins two feeds, oldest first.
    func merged(with other: RTSWData) -> RTSWData {
        RTSWData(
            mag: (mag + other.mag).sorted { $0.date < $1.date },
            plasma: (plasma + other.plasma).sorted { $0.date < $1.date }
        )
    }
}

// MARK: - Fetching

enum RTSWFetcher {
    /// Satellites read from the HAPI feed.
    private static let hapiSatellites = ["dscovr", "ace", "solar1"]

    private static let stereoURL = URL(string: "https://services.swpc.noaa.gov/json/stereo/stereo_a_1m.json")!
    private static let laspURL = "https://lasp.colorado.edu/space-weather-portal/latis/dap2"

    /// DSCOVR + ACE + SOLAR-1 magnetic field and plasma for a window. Each point is tagged
    /// `active` iff its satellite is the one `active-mag` reports at that timestamp, so
    /// satellite switches within the window are reflected. A satellite that fails or has
    /// nothing to say (DSCOVR has been decommissioned) is left out rather than failing the rest.
    static func fetchRTSW(from startDate: Date, to endDate: Date, cadence: HAPI.Cadence) async throws -> RTSWData {
        async let mag = fetchEachSatellite { satellite in
            try await HAPI.fetchMag(satellite: satellite, cadence: cadence, from: startDate, to: endDate)
        }
        async let plasma = fetchEachSatellite { satellite in
            try await HAPI.fetchPlasma(satellite: satellite, cadence: cadence, from: startDate, to: endDate)
        }
        let activeSources = try await HAPI.fetchActiveSources(cadence: cadence, from: startDate, to: endDate)

        return RTSWData(
            mag: tagActive(await mag, activeSources),
            plasma: tagActive(await plasma, activeSources)
        )
    }

    /// STEREO-A from NOAA's one-minute feed, which holds a month of data and cannot be asked
    /// for a window. Only its tail is requested: a day is about a megabyte, the file over twenty.
    /// STEREO points are never flagged active.
    static func fetchSTEREO(from startDate: Date, to endDate: Date) async throws -> RTSWData {
        // Rows run up to ~660 bytes, and the feed trails real time by an hour or two
        let minutes = endDate.timeIntervalSince(startDate) / 60
        var request = URLRequest(url: stereoURL)
        request.setValue("bytes=-\(Int((minutes + 180) * 680))", forHTTPHeaderField: "Range")
        let (data, _) = try await URLSession.shared.data(for: request)

        // The tail starts part-way through a row: resume at the first whole one
        guard let firstRow = data.range(of: Data(#"{"timestamp""#.utf8))?.lowerBound else { return RTSWData() }
        var json = Data("[".utf8)
        json.append(data[firstRow...])
        let rows = try JSONDecoder().decode([STEREORow].self, from: json)

        let dateFormatter = ISO8601DateFormatter()
        let points = rows.compactMap { row -> (Date, STEREORow)? in
            guard let date = dateFormatter.date(from: row.timestamp), date > startDate else { return nil }
            return (date, row)
        }
        return RTSWData(
            mag: points.map { date, row in
                RTSWMag(date: date, bt: row.bt, by: row.by, bz: row.bz, phi: row.phi, theta: row.theta,
                        quality: 0, source: RTSWSourceCode.stereo)
            },
            plasma: points.map { date, row in
                RTSWPlasma(date: date, speed: row.speed, density: row.density,
                           quality: 0, source: RTSWSourceCode.stereo)
            }
        )
    }

    /// IMAP from LASP's I-ALiRT feed for a window, downsampled to one point per minute.
    /// IMAP points are never flagged active.
    static func fetchIMAP(from startDate: Date, to endDate: Date) async throws -> RTSWData {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let window = "?time%3E=\(encodeURIComponent(dateFormatter.string(from: startDate)))"
            + "&time%3C=\(encodeURIComponent(dateFormatter.string(from: endDate)))"
            + "&convertTime(%22milliseconds%20since%201970-01-01%22)"

        async let magRows = fetchJSONLines(
            "\(laspURL)/ialirt_mag.jsonl\(window)"
            + "&project(time,mag_B_GSM._1,mag_B_GSM._2,mag_B_GSM._3,mag_B_magnitude,mag_theta_B_GSM,mag_phi_B_GSM)"
        )
        async let plasmaRows = fetchJSONLines(
            "\(laspURL)/ialirt_swapi.jsonl\(window)"
            + "&project(time,swapi_pseudo_proton_density,swapi_pseudo_proton_speed,swapi_pseudo_proton_temperature)"
        )

        // LaTiS answers in the dataset's column order rather than the projection's:
        // time, phi, theta, |B|, Bx, By, Bz for the field; time, density, speed, temperature for the wind
        let mag = try await magRows.compactMap { row -> RTSWMag? in
            guard row.count >= 7 else { return nil }
            return RTSWMag(date: Date(timeIntervalSince1970: row[0] / 1000), bt: row[3], by: row[5], bz: row[6],
                           phi: row[1], theta: row[2], quality: 0, source: RTSWSourceCode.imap)
        }
        let plasma = try await plasmaRows.compactMap { row -> RTSWPlasma? in
            guard row.count >= 3 else { return nil }
            return RTSWPlasma(date: Date(timeIntervalSince1970: row[0] / 1000), speed: row[2], density: row[1],
                              quality: 0, source: RTSWSourceCode.imap)
        }
        return RTSWData(mag: downsampleByMinute(mag), plasma: downsampleByMinute(plasma))
    }

    // MARK: - Helpers

    private static func fetchEachSatellite<T: Sendable>(
        _ fetch: @escaping @Sendable (String) async throws -> [T]
    ) async -> [T] {
        await withTaskGroup(of: [T].self) { group in
            for satellite in hapiSatellites {
                group.addTask { (try? await fetch(satellite)) ?? [] }
            }
            return await group.reduce(into: []) { $0 += $1 }
        }
    }

    /// Tags each point `active` iff its source matches the active source at its timestamp, oldest first.
    private static func tagActive<T: RTSWSample>(_ points: [T], _ activeSources: [Date: Int]) -> [T] {
        points
            .map { point in
                var point = point
                point.active = activeSources[point.date] == point.source
                return point
            }
            .sorted { $0.date < $1.date }
    }

    /// Keeps the first point of every minute.
    private static func downsampleByMinute<T: RTSWSample>(_ points: [T]) -> [T] {
        var minutes = Set<Int>()
        return points
            .sorted { $0.date < $1.date }
            .filter { minutes.insert(Int(($0.date.timeIntervalSince1970 / 60).rounded(.down))).inserted }
    }

    /// One JSON array per line, decoded in a single pass. Nulls become NaN.
    private static func fetchJSONLines(_ urlString: String) async throws -> [[Double]] {
        guard let url = URL(string: urlString) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
        let json = Data(("[" + lines.joined(separator: ",") + "]").utf8)
        return try JSONDecoder().decode([[Double?]].self, from: json).map { row in row.map { $0 ?? .nan } }
    }

    /// JavaScript's encodeURIComponent, which LaTiS expects its time constraints in.
    private static func encodeURIComponent(_ value: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-_.!~*'()")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// One row of NOAA's STEREO-A feed. Values may come as numbers, strings or null.
private struct STEREORow: Decodable {
    let timestamp: String
    let bt: Double
    let by: Double
    let bz: Double
    let phi: Double
    let theta: Double
    let speed: Double
    let density: Double

    enum CodingKeys: String, CodingKey {
        case timestamp
        case bt = "Bt_nT"
        case by = "mag_hgrtn_t_nT"
        case bz = "mag_hgrtn_n_nT"
        case phi = "phi_deg"
        case theta = "theta_deg"
        case speed = "speed_KPS"
        case density = "density_cm3"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ key: CodingKeys) -> Double {
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return value }
            if let text = try? container.decodeIfPresent(String.self, forKey: key), let value = Double(text) { return value }
            return .nan
        }
        timestamp = try container.decode(String.self, forKey: .timestamp)
        bt = number(.bt)
        by = number(.by)
        bz = number(.bz)
        phi = number(.phi)
        theta = number(.theta)
        speed = number(.speed)
        density = number(.density)
    }
}
