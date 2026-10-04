//
//  GlobeModel.swift
//  norlysWidget
//
//  The norlys model as the website's globe reads it: the latest frame of api.norlys.live/rs/latest,
//  in the binary layout of the website's helpers/modelFormat.ts.
//
//  header — 32 bytes: u32 magic 'NRLS', u16 version, u16 lats, u16 lons, u16 scale,
//                     f32 minLat, f32 maxLat, f32 minLon, f32 maxLon, u32 frames
//  frame  — f64 timestamp (ms), i16 score[lats * lons], i16 speed[lats * lons], values / scale
//

import Foundation

/// One frame of the model, laid out as the website's `MapPoint` matrix.
struct AuroraModelFrame {
    struct Point {
        let lat: Double
        let lon: Double
        /// Stored as the website's Float32Array holds them.
        let score: Float
        /// The model's derivative, out of five, which the substorm rings are cut from.
        let speed: Float
    }

    /// When the frame was computed.
    let timestamp: Date
    let lats: Int
    let lons: Int
    /// Latitude major, `points[y * lons + x]`.
    let points: [Point]
}

enum AuroraModelError: Error {
    case notAModelBuffer
    case unsupportedVersion(Int)
    case noFrame
}

extension AuroraModelFrame {
    static let latestURL = URL(string: "https://api.norlys.live/rs/latest")!

    private static let magic: UInt32 = 0x4E52_4C53
    private static let headerBytes = 32
    /// The layout this reader understands; a later writer's is refused rather than guessed at.
    private static let supportedVersion = 1

    /// The frame the website's globe opens on.
    static func fetchLatest() async throws -> AuroraModelFrame {
        let request = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let frame = try decodeFrames(data).first else { throw AuroraModelError.noFrame }
        return frame
    }

    /// Every frame of a response. The count is taken from the buffer's length as well as the header,
    /// so a response truncated in flight yields the frames that did arrive.
    static func decodeFrames(_ data: Data) throws -> [AuroraModelFrame] {
        guard data.count >= headerBytes else { throw AuroraModelError.notAModelBuffer }

        return try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            func integer<T: FixedWidthInteger>(_ offset: Int, _: T.Type) -> T {
                T(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: T.self))
            }
            func float32(_ offset: Int) -> Double {
                Double(Float(bitPattern: integer(offset, UInt32.self)))
            }

            guard integer(0, UInt32.self) == magic else { throw AuroraModelError.notAModelBuffer }
            let version = Int(integer(4, UInt16.self))
            guard version == supportedVersion else { throw AuroraModelError.unsupportedVersion(version) }

            let lats = Int(integer(6, UInt16.self))
            let lons = Int(integer(8, UInt16.self))
            let scale = Double(integer(10, UInt16.self))
            let minLat = float32(12), maxLat = float32(16)
            let minLon = float32(20), maxLon = float32(24)
            let count = lats * lons
            let frameBytes = 8 + count * 4
            let frames = min(Int(integer(28, UInt32.self)), (raw.count - headerBytes) / frameBytes)
            guard frames > 0, scale > 0 else { return [] }

            // Both ends of each range are inclusive
            let latStep = lats > 1 ? (maxLat - minLat) / Double(lats - 1) : 0
            let lonStep = lons > 1 ? (maxLon - minLon) / Double(lons - 1) : 0

            return (0..<frames).map { frame in
                let offset = headerBytes + frame * frameBytes
                var points = [Point]()
                points.reserveCapacity(count)
                for y in 0..<lats {
                    for x in 0..<lons {
                        let i = y * lons + x
                        let score = integer(offset + 8 + i * 2, Int16.self)
                        let speed = integer(offset + 8 + count * 2 + i * 2, Int16.self)
                        points.append(Point(
                            lat: minLat + Double(y) * latStep,
                            lon: minLon + Double(x) * lonStep,
                            score: Float(Double(score) / scale),
                            speed: Float(Double(speed) / scale)
                        ))
                    }
                }
                let milliseconds = Double(bitPattern: integer(offset, UInt64.self))
                return AuroraModelFrame(timestamp: Date(timeIntervalSince1970: milliseconds / 1000),
                                        lats: lats, lons: lons, points: points)
            }
        }
    }
}
