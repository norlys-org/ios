//
//  GlobeGeometry.swift
//  norlysWidget
//
//  The lines drawn over the globe, traced as the website's map/features/fastGlobe.ts traces them:
//  every point converted to the unit sphere once, segments longer than a degree split along their
//  great circle, the pen lifted where a line passes behind the globe and segments shorter than
//  three quarters of a point dropped.
//
//  The land outline and lakes (Natural Earth 1:50m), the rivers (1:110m) and the AACGM magnetic
//  parallels (SuperDARN) are the website's own assets, packed by `scripts/pack-globe-assets.mjs`:
//  'NGEO' | u32 rings | u32 points | u32 offsets[rings + 1] | i16 lon, i16 lat per point,
//  longitudes scaled by 32767 / 180 and latitudes by 32767 / 90.
//

import CoreGraphics
import Foundation

/// Where the globe is: d3.geoOrthographic's rotate, scale and translate.
struct GlobeView {
    /// Rows: screen x, screen y before the flip, and the horizon test (fastGlobe's rotationMatrix).
    let m: [Double]
    /// Radius of the globe, in points.
    let scale: Double
    let translateX: Double
    let translateY: Double
    let width: Double
    let height: Double
    /// The point the viewer looks straight at.
    let centre: GeoPoint

    init(centre: GeoPoint, scale: Double, translate: CGPoint, size: CGSize) {
        // d3 rotates by `[-longitude, -latitude]` to bring a point to the centre
        let lambda = -centre.lon * GlobeD3.radians, phi = -centre.lat * GlobeD3.radians
        let cl = cos(lambda), sl = sin(lambda), cp = cos(phi), sp = sin(phi)
        m = [
            sl, cl, 0,
            sp * cl, -sp * sl, cp,
            cp * cl, -cp * sl, -sp
        ]
        self.scale = scale
        translateX = translate.x
        translateY = translate.y
        width = size.width
        height = size.height
        self.centre = centre
    }

    /// The point on screen, as `projection(point)` gives it: no clipping.
    func project(_ point: GeoPoint) -> CGPoint {
        let p = GlobeView.unit(point)
        return CGPoint(x: translateX + scale * (p.x * m[0] + p.y * m[1] + p.z * m[2]),
                       y: translateY - scale * (p.x * m[3] + p.y * m[4] + p.z * m[5]))
    }

    /// Positive on the half of the sphere facing the viewer.
    func facing(_ p: SIMD3<Double>) -> Double {
        p.x * m[6] + p.y * m[7] + p.z * m[8]
    }

    func screen(_ p: SIMD3<Double>) -> CGPoint {
        CGPoint(x: translateX + scale * (p.x * m[0] + p.y * m[1] + p.z * m[2]),
                y: translateY - scale * (p.x * m[3] + p.y * m[4] + p.z * m[5]))
    }

    /// A direction of the globe, in the view's frame: (screen x, screen y, towards the viewer).
    func toView(_ p: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(p.x * m[0] + p.y * m[1] + p.z * m[2],
              p.x * m[3] + p.y * m[4] + p.z * m[5],
              p.x * m[6] + p.y * m[7] + p.z * m[8])
    }

    /// Back from the view's frame: the matrix is a rotation, so its transpose undoes it.
    func toWorld(_ q: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(m[0] * q.x + m[3] * q.y + m[6] * q.z,
              m[1] * q.x + m[4] * q.y + m[7] * q.z,
              m[2] * q.x + m[5] * q.y + m[8] * q.z)
    }

    static func unit(_ point: GeoPoint) -> SIMD3<Double> {
        let lambda = point.lon * GlobeD3.radians, phi = point.lat * GlobeD3.radians
        return SIMD3(cos(phi) * cos(lambda), cos(phi) * sin(lambda), sin(phi))
    }
}

/// Geometry converted to unit-sphere positions, laid out flat.
struct SphereGeometry {
    /// Three floats per point.
    let xyz: [Float]
    /// Ring `i` owns the points `offsets[i] ..< offsets[i + 1]`.
    let offsets: [Int]
    /// Bounding cap per ring, four floats each: centre x, y, z and the cosine of its radius.
    let caps: [Float]

    /// Segments shorter than this are dropped as a ring is walked.
    private static let minSegment = 0.75
    /// Longest segment, in radians, drawn as a straight line; d3 resamples, so its sources may be sparse.
    private static let maxSegment = 1 * GlobeD3.radians

    init(rings: [[GeoPoint]]) {
        var xyz: [Float] = []
        var offsets: [Int] = []
        var caps: [Float] = []
        for ring in rings {
            offsets.append(xyz.count / 3)
            let start = xyz.count / 3
            SphereGeometry.appendRing(ring, to: &xyz)
            caps.append(contentsOf: SphereGeometry.cap(xyz, from: start, to: xyz.count / 3))
        }
        offsets.append(xyz.count / 3)
        self.xyz = xyz
        self.offsets = offsets
        self.caps = caps
    }

    /// One ring as a flat `x, y, z` run, a segment spanning more than a degree split along its great circle.
    private static func appendRing(_ ring: [GeoPoint], to xyz: inout [Float]) {
        var previous = SIMD3<Double>.zero
        var first = true
        for point in ring {
            let p = GlobeView.unit(point)
            if !first {
                let omega = acos(max(-1, min(1, (previous * p).sum())))
                let steps = Int((omega / maxSegment).rounded(.up))
                let sinOmega = sin(omega)
                if steps > 1, sinOmega > 1e-9 {
                    for step in 1..<steps {
                        let t = Double(step) / Double(steps)
                        let between = previous * (sin((1 - t) * omega) / sinOmega) + p * (sin(t * omega) / sinOmega)
                        xyz.append(Float(between.x))
                        xyz.append(Float(between.y))
                        xyz.append(Float(between.z))
                    }
                }
            }
            xyz.append(Float(p.x))
            xyz.append(Float(p.y))
            xyz.append(Float(p.z))
            previous = p
            first = false
        }
    }

    /// A cap covering the points `from ..< to`: their mean direction and the cosine of the widest of them.
    private static func cap(_ xyz: [Float], from: Int, to: Int) -> [Float] {
        var sum = SIMD3<Double>.zero
        for i in from..<to {
            sum += SIMD3(Double(xyz[i * 3]), Double(xyz[i * 3 + 1]), Double(xyz[i * 3 + 2]))
        }
        let length = (sum * sum).sum().squareRoot()
        let centre = length > 0 ? sum / length : sum
        var minDot = 1.0
        for i in from..<to {
            let dot = Double(xyz[i * 3]) * centre.x + Double(xyz[i * 3 + 1]) * centre.y + Double(xyz[i * 3 + 2]) * centre.z
            minDot = min(minDot, dot)
        }
        return [Float(centre.x), Float(centre.y), Float(centre.z), Float(minDot)]
    }

    /// True when a cap lies wholly behind the horizon or outside the viewport.
    private func isHidden(_ ring: Int, _ view: GlobeView) -> Bool {
        let at = ring * 4
        let centre = SIMD3(Double(caps[at]), Double(caps[at + 1]), Double(caps[at + 2]))
        let cosRadius = Double(caps[at + 3])
        if cosRadius >= 0, view.facing(centre) < -(1 - cosRadius * cosRadius).squareRoot() { return true }

        // The cap's chord bounds how far from its projected centre it reaches on screen
        let screen = view.screen(centre)
        let radius = view.scale * (2 - 2 * cosRadius).squareRoot() + 2
        return screen.x + radius < 0 || screen.x - radius > view.width
            || screen.y + radius < 0 || screen.y - radius > view.height
    }

    /// Traces every visible ring into `path`. A point behind the globe lifts the pen.
    func trace(into path: CGMutablePath, view: GlobeView) {
        let minimum = SphereGeometry.minSegment * SphereGeometry.minSegment
        let m = view.m
        let (m0, m1, m2, m3, m4, m5, m6, m7, m8) = (m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8])
        let scale = view.scale, translateX = view.translateX, translateY = view.translateY

        xyz.withUnsafeBufferPointer { buffer in
            guard let points = buffer.baseAddress else { return }
            for ring in 0..<(offsets.count - 1) where !isHidden(ring, view) {
                let end = offsets[ring + 1]
                var drawing = false
                var lastX = 0.0, lastY = 0.0

                for i in offsets[ring]..<end {
                    let x = Double(points[i * 3]), y = Double(points[i * 3 + 1]), z = Double(points[i * 3 + 2])
                    if x * m6 + y * m7 + z * m8 < 0 {
                        drawing = false
                        continue
                    }
                    let screenX = translateX + scale * (x * m0 + y * m1 + z * m2)
                    let screenY = translateY - scale * (x * m3 + y * m4 + z * m5)
                    // The last point is always kept, so a coastline closes on itself
                    if drawing, i != end - 1 {
                        let dx = screenX - lastX, dy = screenY - lastY
                        if dx * dx + dy * dy < minimum { continue }
                    }
                    if drawing {
                        path.addLine(to: CGPoint(x: screenX, y: screenY))
                    } else {
                        path.move(to: CGPoint(x: screenX, y: screenY))
                    }
                    drawing = true
                    lastX = screenX
                    lastY = screenY
                }
            }
        }
    }
}

enum GlobeGeometry {
    static let land = load("GlobeLand")
    static let lakes = load("GlobeLakes")
    static let rivers = load("GlobeRivers")
    static let magneticLatitudes = load("GlobeMagneticLatitudes")
    static let graticule = SphereGeometry(rings: GlobeD3.graticuleLines())

    private static func load(_ name: String) -> SphereGeometry? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "bin"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decode(data).map(SphereGeometry.init(rings:))
    }

    static func decode(_ data: Data) -> [[GeoPoint]]? {
        guard data.count >= 12 else { return nil }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [[GeoPoint]]? in
            func u32(_ offset: Int) -> Int { Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))) }
            func i16(_ offset: Int) -> Double { Double(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: Int16.self))) }

            guard raw[0] == 0x4E, raw[1] == 0x47, raw[2] == 0x45, raw[3] == 0x4F else { return nil } // NGEO
            let rings = u32(4), points = u32(8)
            let pointsAt = 12 + (rings + 1) * 4
            guard raw.count >= pointsAt + points * 4 else { return nil }
            let offsets = (0...rings).map { u32(12 + $0 * 4) }
            guard offsets.first == 0, offsets.last == points, zip(offsets, offsets.dropFirst()).allSatisfy({ $0 <= $1 }) else {
                return nil
            }

            return (0..<rings).map { ring in
                (offsets[ring]..<offsets[ring + 1]).map { i in
                    GeoPoint(lon: i16(pointsAt + i * 4) * 180 / 32767, lat: i16(pointsAt + i * 4 + 2) * 90 / 32767)
                }
            }
        }
    }
}
