//
//  RTSWFetcher.swift
//  norlysWidget
//
//  Swift port of the rtsw-fetcher package behind norlys.live/rtsw: the solar wind
//  magnetic field and plasma measured by every satellite at L1, each point tagged
//  with the satellite it came from and whether NOAA marks that satellite as active.
//  DSCOVR, ACE and SOLAR-1 come from NOAA's HAPI feed (HAPI.swift).
//

import Foundation

// MARK: - Data Models

/// Codes for the satellite a point came from, as NOAA's HAPI numbers them.
enum RTSWSourceCode {
    static let ace = 1
    static let dscovr = 2
    static let solar1 = 4
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

/// RTSWMag: Magnetic field measurement (GSM coordinates).
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
}
