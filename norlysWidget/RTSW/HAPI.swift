//
//  HAPI.swift
//  norlysWidget
//
//  Fetches real-time solar wind data from NOAA SWPC's HAPI feed.
//  The small and medium widgets only query the `active-*` datasets: they contain
//  the measurements from whichever satellite (DSCOVR / ACE / SOLAR-1) NOAA
//  currently marks as active, so no per-satellite fetching or active-flag
//  filtering is needed. The large widget also reads each satellite's own
//  datasets (see the extension below and RTSWFetcher.swift).
//

import Foundation

enum HAPI {
    private static let baseURL = "https://tlv-swpc.woc.noaa.gov/hapi/data"
    /// HAPI emits this sentinel for missing samples; points carrying it are dropped.
    private static let fillValue = -1.0e30

    struct MagPoint {
        let date: Date
        let bt: Double
        let bz: Double
    }

    struct PlasmaPoint {
        let date: Date
        let speed: Double
        let density: Double
    }

    private static func parseNumber(_ value: String) -> Double? {
        guard let number = Double(value), number != fillValue else { return nil }
        return number
    }

    /// Fetches a HAPI dataset as CSV. `time_tag` is always returned as the
    /// first column, so callers don't need to include it in `parameters`.
    private static func fetchCSV(
        id: String,
        parameters: [String],
        from startDate: Date,
        to endDate: Date
    ) async throws -> (headers: [String], rows: [[String]]) {
        let formatter = ISO8601DateFormatter()
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "parameters", value: parameters.joined(separator: ",")),
            URLQueryItem(name: "time.min", value: formatter.string(from: startDate)),
            URLQueryItem(name: "time.max", value: formatter.string(from: endDate))
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let lines = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .filter { !$0.isEmpty }
        guard let header = lines.first else { return ([], []) }
        return (
            header.split(separator: ",").map(String.init),
            lines.dropFirst().map { $0.split(separator: ",").map(String.init) }
        )
    }

    /// Magnetic field (bt/bz) from the active satellite at 1-minute cadence, oldest first.
    static func fetchActiveMag(from startDate: Date, to endDate: Date) async throws -> [MagPoint] {
        let (headers, rows) = try await fetchCSV(
            id: "active-mag-pt1m",
            parameters: ["bt", "bz_gsm"],
            from: startDate,
            to: endDate
        )
        guard let dateColumn = headers.firstIndex(of: "time_tag"),
              let btColumn = headers.firstIndex(of: "bt"),
              let bzColumn = headers.firstIndex(of: "bz_gsm") else { return [] }
        let dateFormatter = ISO8601DateFormatter()
        return rows.compactMap { row -> MagPoint? in
            guard row.count > max(dateColumn, btColumn, bzColumn),
                  let date = dateFormatter.date(from: row[dateColumn]),
                  let bt = parseNumber(row[btColumn]),
                  let bz = parseNumber(row[bzColumn]) else { return nil }
            return MagPoint(date: date, bt: bt, bz: bz)
        }
        .sorted { $0.date < $1.date }
    }

    /// Plasma (speed/density) from the active satellite at 1-minute cadence, oldest first.
    static func fetchActivePlasma(from startDate: Date, to endDate: Date) async throws -> [PlasmaPoint] {
        let (headers, rows) = try await fetchCSV(
            id: "active-plasma-pt1m",
            parameters: ["speed", "density"],
            from: startDate,
            to: endDate
        )
        guard let dateColumn = headers.firstIndex(of: "time_tag"),
              let speedColumn = headers.firstIndex(of: "speed"),
              let densityColumn = headers.firstIndex(of: "density") else { return [] }
        let dateFormatter = ISO8601DateFormatter()
        return rows.compactMap { row -> PlasmaPoint? in
            guard row.count > max(dateColumn, speedColumn, densityColumn),
                  let date = dateFormatter.date(from: row[dateColumn]),
                  let speed = parseNumber(row[speedColumn]),
                  let density = parseNumber(row[densityColumn]) else { return nil }
            return PlasmaPoint(date: date, speed: speed, density: density)
        }
        .sorted { $0.date < $1.date }
    }
}

// MARK: - Per-satellite datasets

extension HAPI {
    /// Resolution of a dataset, as it appears in its id (e.g. `solar1-mag-pt5m`).
    enum Cadence: String {
        case pt1m, pt5m, pt30m, pt1h, pt6h, pt1d
    }

    /// Magnetic field from one satellite (`dscovr`, `ace` or `solar1`), oldest first.
    /// Missing values are NaN rather than dropped, so a point keeps its other components.
    static func fetchMag(satellite: String, cadence: Cadence, from startDate: Date, to endDate: Date) async throws -> [RTSWMag] {
        let (headers, rows) = try await fetchCSV(
            id: "\(satellite)-mag-\(cadence.rawValue)",
            parameters: ["bt", "by_gsm", "bz_gsm", "theta_gsm", "phi_gsm", "quality", "source"],
            from: startDate,
            to: endDate
        )
        guard let dateColumn = headers.firstIndex(of: "time_tag"),
              let btColumn = headers.firstIndex(of: "bt"),
              let byColumn = headers.firstIndex(of: "by_gsm"),
              let bzColumn = headers.firstIndex(of: "bz_gsm"),
              let thetaColumn = headers.firstIndex(of: "theta_gsm"),
              let phiColumn = headers.firstIndex(of: "phi_gsm"),
              let qualityColumn = headers.firstIndex(of: "quality"),
              let sourceColumn = headers.firstIndex(of: "source") else { return [] }
        let dateFormatter = ISO8601DateFormatter()
        return rows.compactMap { row -> RTSWMag? in
            guard row.count == headers.count,
                  let date = dateFormatter.date(from: row[dateColumn]) else { return nil }
            return RTSWMag(
                date: date,
                bt: parseNumber(row[btColumn]) ?? .nan,
                by: parseNumber(row[byColumn]) ?? .nan,
                bz: parseNumber(row[bzColumn]) ?? .nan,
                phi: parseNumber(row[phiColumn]) ?? .nan,
                theta: parseNumber(row[thetaColumn]) ?? .nan,
                quality: Int(row[qualityColumn]) ?? 0,
                source: Int(row[sourceColumn]) ?? 0
            )
        }
        .sorted { $0.date < $1.date }
    }

    /// Plasma from one satellite (`dscovr`, `ace` or `solar1`), oldest first. Missing values are NaN.
    static func fetchPlasma(satellite: String, cadence: Cadence, from startDate: Date, to endDate: Date) async throws -> [RTSWPlasma] {
        let (headers, rows) = try await fetchCSV(
            id: "\(satellite)-plasma-\(cadence.rawValue)",
            parameters: ["speed", "density", "quality", "source"],
            from: startDate,
            to: endDate
        )
        guard let dateColumn = headers.firstIndex(of: "time_tag"),
              let speedColumn = headers.firstIndex(of: "speed"),
              let densityColumn = headers.firstIndex(of: "density"),
              let qualityColumn = headers.firstIndex(of: "quality"),
              let sourceColumn = headers.firstIndex(of: "source") else { return [] }
        let dateFormatter = ISO8601DateFormatter()
        return rows.compactMap { row -> RTSWPlasma? in
            guard row.count == headers.count,
                  let date = dateFormatter.date(from: row[dateColumn]) else { return nil }
            return RTSWPlasma(
                date: date,
                speed: parseNumber(row[speedColumn]) ?? .nan,
                density: parseNumber(row[densityColumn]) ?? .nan,
                quality: Int(row[qualityColumn]) ?? 0,
                source: Int(row[sourceColumn]) ?? 0
            )
        }
        .sorted { $0.date < $1.date }
    }

    /// Source code of the satellite NOAA marked as active at each timestamp. Satellites can switch
    /// on and off within a window, so this is looked up per point rather than once for the window.
    static func fetchActiveSources(cadence: Cadence, from startDate: Date, to endDate: Date) async throws -> [Date: Int] {
        let (headers, rows) = try await fetchCSV(
            id: "active-mag-\(cadence.rawValue)",
            parameters: ["source"],
            from: startDate,
            to: endDate
        )
        guard let dateColumn = headers.firstIndex(of: "time_tag"),
              let sourceColumn = headers.firstIndex(of: "source") else { return [:] }
        let dateFormatter = ISO8601DateFormatter()
        var sources: [Date: Int] = [:]
        for row in rows where row.count == headers.count {
            if let date = dateFormatter.date(from: row[dateColumn]), let source = Int(row[sourceColumn]) {
                sources[date] = source
            }
        }
        return sources
    }
}
