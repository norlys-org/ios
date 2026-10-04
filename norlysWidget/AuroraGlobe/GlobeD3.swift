//
//  GlobeD3.swift
//  norlysWidget
//
//  The parts of d3 the website's globe is built from, ported line for line so the widget lands on
//  the same values: d3-array's blur2, d3-contour's marching squares, d3-polygon's area and
//  containment, d3-geo's distance, interpolation and graticule, and d3-interpolate's basis spline.
//

import Foundation

/// A longitude and a latitude in degrees, in the order d3 takes them.
struct GeoPoint: Equatable {
    var lon: Double
    var lat: Double
}

enum GlobeD3 {
    static let radians = Double.pi / 180
    static let degrees = 180 / Double.pi
    /// d3-geo's epsilon.
    static let epsilon = 1e-6

    // MARK: d3-array blur2

    /// `d3.blur2({ data, width, height }, radius)`, in place. The storage decides the rounding:
    /// `Float` rounds every pass like the website's Float32Array, `Double` keeps it like a plain array.
    static func blur2<E: BinaryFloatingPoint>(_ values: inout [E], width: Int, height: Int, radius: Double) {
        guard width > 0, height > 0, radius > 0, values.count >= width * height else { return }
        var temp = values
        let n = width * height

        values.withUnsafeMutableBufferPointer { valuesBuffer in
            temp.withUnsafeMutableBufferPointer { tempBuffer in
                let v = valuesBuffer.baseAddress!, t = tempBuffer.baseAddress!
                func blurh(_ target: UnsafeMutablePointer<E>, _ source: UnsafeMutablePointer<E>) {
                    var y = 0
                    while y < n {
                        blurLine(target, source, start: y, stop: y + width, step: 1, radius: radius)
                        y += width
                    }
                }
                func blurv(_ target: UnsafeMutablePointer<E>, _ source: UnsafeMutablePointer<E>) {
                    for x in 0..<width {
                        blurLine(target, source, start: x, stop: x + n, step: width, radius: radius)
                    }
                }
                blurh(t, v)
                blurh(v, t)
                blurh(t, v)
                blurv(v, t)
                blurv(t, v)
                blurv(v, t)
            }
        }
    }

    /// Sets each `target[i]` to the average of `source[i - r] … source[i + r]` along one line, clamped
    /// to the line, the two values past a fractional radius weighted by its fraction (blurf / bluri).
    private static func blurLine<E: BinaryFloatingPoint>(
        _ target: UnsafeMutablePointer<E>,
        _ source: UnsafeMutablePointer<E>,
        start: Int,
        stop end: Int,
        step: Int,
        radius: Double
    ) {
        let stop = end - step // inclusive
        guard stop >= start else { return }

        let radius0 = radius.rounded(.down)
        if radius0 == radius {
            let r = Int(radius)
            let w = Double(2 * r + 1)
            var sum = Double(r) * Double(source[start])
            let s = step * r
            var i = start
            while i < start + s {
                sum += Double(source[min(stop, i)])
                i += step
            }
            i = start
            while i <= stop {
                sum += Double(source[min(stop, i + s)])
                target[i] = E(sum / w)
                sum -= Double(source[max(start, i - s)])
                i += step
            }
        } else {
            let t = radius - radius0
            let w = 2 * radius + 1
            var sum = radius0 * Double(source[start])
            let s0 = step * Int(radius0)
            let s1 = s0 + step
            var i = start
            while i < start + s0 {
                sum += Double(source[min(stop, i)])
                i += step
            }
            i = start
            while i <= stop {
                sum += Double(source[min(stop, i + s0)])
                target[i] = E((sum + t * (Double(source[max(start, i - s1)]) + Double(source[min(stop, i + s1)]))) / w)
                sum -= Double(source[max(start, i - s0)])
                i += step
            }
        }
    }

    // MARK: d3-contour

    struct Point: Equatable {
        var x: Double
        var y: Double
    }

    /// A polygon as d3-contour gives it: its outline, then any holes inside it.
    typealias Polygon = [[Point]]

    /// `d3.contours().size([dx, dy]).thresholds(thresholds)(values)`: for each threshold, ascending,
    /// the polygons enclosing the values at or above it.
    static func contours(_ values: [Double], width dx: Int, height dy: Int, thresholds: [Double]) -> [[Polygon]] {
        thresholds.sorted().map { contour(values, dx: dx, dy: dy, value: $0) }
    }

    private static func contour(_ values: [Double], dx: Int, dy: Int, value: Double) -> [Polygon] {
        var polygons: [Polygon] = []
        var holes: [[Point]] = []

        isorings(values, dx: dx, dy: dy, value: value) { ring in
            var ring = ring
            smoothLinear(&ring, values: values, dx: dx, dy: dy, value: value)
            if contourArea(ring) > 0 {
                polygons.append([ring])
            } else {
                holes.append(ring)
            }
        }

        for hole in holes {
            for index in polygons.indices where contains(polygons[index][0], hole) != -1 {
                polygons[index].append(hole)
                break
            }
        }

        return polygons
    }

    /// The segments of each marching squares case, in cell units.
    private static let cases: [[[Point]]] = [
        [],
        [[Point(x: 1.0, y: 1.5), Point(x: 0.5, y: 1.0)]],
        [[Point(x: 1.5, y: 1.0), Point(x: 1.0, y: 1.5)]],
        [[Point(x: 1.5, y: 1.0), Point(x: 0.5, y: 1.0)]],
        [[Point(x: 1.0, y: 0.5), Point(x: 1.5, y: 1.0)]],
        [[Point(x: 1.0, y: 1.5), Point(x: 0.5, y: 1.0)], [Point(x: 1.0, y: 0.5), Point(x: 1.5, y: 1.0)]],
        [[Point(x: 1.0, y: 0.5), Point(x: 1.0, y: 1.5)]],
        [[Point(x: 1.0, y: 0.5), Point(x: 0.5, y: 1.0)]],
        [[Point(x: 0.5, y: 1.0), Point(x: 1.0, y: 0.5)]],
        [[Point(x: 1.0, y: 1.5), Point(x: 1.0, y: 0.5)]],
        [[Point(x: 0.5, y: 1.0), Point(x: 1.0, y: 0.5)], [Point(x: 1.5, y: 1.0), Point(x: 1.0, y: 1.5)]],
        [[Point(x: 1.5, y: 1.0), Point(x: 1.0, y: 0.5)]],
        [[Point(x: 0.5, y: 1.0), Point(x: 1.5, y: 1.0)]],
        [[Point(x: 1.0, y: 1.5), Point(x: 1.5, y: 1.0)]],
        [[Point(x: 0.5, y: 1.0), Point(x: 1.0, y: 1.5)]],
        []
    ]

    private final class Fragment {
        var start: Int
        var end: Int
        var ring: [Point]

        init(start: Int, end: Int, ring: [Point]) {
            self.start = start
            self.end = end
            self.ring = ring
        }
    }

    /// Marching squares with the isolines stitched into rings.
    private static func isorings(_ values: [Double], dx: Int, dy: Int, value: Double, callback: ([Point]) -> Void) {
        var fragmentByStart: [Int: Fragment] = [:]
        var fragmentByEnd: [Int: Fragment] = [:]
        var x = -1, y = -1
        var t0 = 0, t1 = 0, t2 = 0, t3 = 0

        func above(_ index: Int) -> Int {
            index >= 0 && index < values.count && values[index] >= value ? 1 : 0
        }
        func index(_ point: Point) -> Int {
            Int(point.x * 2 + point.y * Double(dx + 1) * 4)
        }
        func stitch(_ line: [Point]) {
            let start = Point(x: line[0].x + Double(x), y: line[0].y + Double(y))
            let end = Point(x: line[1].x + Double(x), y: line[1].y + Double(y))
            let startIndex = index(start), endIndex = index(end)

            if let f = fragmentByEnd[startIndex] {
                if let g = fragmentByStart[endIndex] {
                    fragmentByEnd[f.end] = nil
                    fragmentByStart[g.start] = nil
                    if f === g {
                        f.ring.append(end)
                        callback(f.ring)
                    } else {
                        let merged = Fragment(start: f.start, end: g.end, ring: f.ring + g.ring)
                        fragmentByStart[f.start] = merged
                        fragmentByEnd[g.end] = merged
                    }
                } else {
                    fragmentByEnd[f.end] = nil
                    f.ring.append(end)
                    f.end = endIndex
                    fragmentByEnd[endIndex] = f
                }
            } else if let f = fragmentByStart[endIndex] {
                if let g = fragmentByEnd[startIndex] {
                    fragmentByStart[f.start] = nil
                    fragmentByEnd[g.end] = nil
                    if f === g {
                        f.ring.append(end)
                        callback(f.ring)
                    } else {
                        let merged = Fragment(start: g.start, end: f.end, ring: g.ring + f.ring)
                        fragmentByStart[g.start] = merged
                        fragmentByEnd[f.end] = merged
                    }
                } else {
                    fragmentByStart[f.start] = nil
                    f.ring.insert(start, at: 0)
                    f.start = startIndex
                    fragmentByStart[startIndex] = f
                }
            } else {
                let fragment = Fragment(start: startIndex, end: endIndex, ring: [start, end])
                fragmentByStart[startIndex] = fragment
                fragmentByEnd[endIndex] = fragment
            }
        }
        func march(_ index: Int) {
            cases[index].forEach(stitch)
        }

        // First row (y = -1, t2 = t3 = 0)
        t1 = above(0)
        march(t1 << 1)
        x += 1
        while x < dx - 1 {
            t0 = t1
            t1 = above(x + 1)
            march(t0 | t1 << 1)
            x += 1
        }
        march(t1 << 0)

        // Intermediate rows
        y += 1
        while y < dy - 1 {
            x = -1
            t1 = above(y * dx + dx)
            t2 = above(y * dx)
            march(t1 << 1 | t2 << 2)
            x += 1
            while x < dx - 1 {
                t0 = t1
                t1 = above(y * dx + dx + x + 1)
                t3 = t2
                t2 = above(y * dx + x + 1)
                march(t0 | t1 << 1 | t2 << 2 | t3 << 3)
                x += 1
            }
            march(t1 | t2 << 3)
            y += 1
        }

        // Last row (y = dy - 1, t0 = t1 = 0)
        x = -1
        t2 = above(y * dx)
        march(t2 << 2)
        x += 1
        while x < dx - 1 {
            t3 = t2
            t2 = above(y * dx + x + 1)
            march(t2 << 2 | t3 << 3)
            x += 1
        }
        march(t2 << 3)
    }

    private static func smoothLinear(_ ring: inout [Point], values: [Double], dx: Int, dy: Int, value: Double) {
        // An index past the array reads as `undefined` in JavaScript, which d3 treats as -Infinity
        func valid(_ index: Int) -> Double {
            guard index >= 0, index < values.count else { return -.infinity }
            let v = values[index]
            return v.isNaN ? -.infinity : v
        }

        for i in ring.indices {
            let x = ring[i].x, y = ring[i].y
            let xt = Int(x), yt = Int(y) // `| 0` truncates towards zero
            let v1 = valid(yt * dx + xt)
            if x > 0, x < Double(dx), Double(xt) == x {
                ring[i].x = smooth1(x, valid(yt * dx + xt - 1), v1, value)
            }
            if y > 0, y < Double(dy), Double(yt) == y {
                ring[i].y = smooth1(y, valid((yt - 1) * dx + xt), v1, value)
            }
        }
    }

    private static func smooth1(_ x: Double, _ v0: Double, _ v1: Double, _ value: Double) -> Double {
        let a = value - v0
        let b = v1 - v0
        let d = (a.isFinite || b.isFinite) ? a / b : sign(a) / sign(b)
        return d.isNaN ? x : x + d - 0.5
    }

    private static func sign(_ x: Double) -> Double {
        x > 0 ? 1 : x < 0 ? -1 : x
    }

    /// d3-contour's ring area, signed so an outline is positive and a hole negative.
    private static func contourArea(_ ring: [Point]) -> Double {
        let n = ring.count
        guard n > 0 else { return 0 }
        var area = ring[n - 1].y * ring[0].x - ring[n - 1].x * ring[0].y
        for i in 1..<n {
            area += ring[i - 1].y * ring[i].x - ring[i - 1].x * ring[i].y
        }
        return area
    }

    private static func contains(_ ring: [Point], _ hole: [Point]) -> Int {
        for point in hole {
            let c = ringContains(ring, point)
            if c != 0 { return c }
        }
        return 0
    }

    private static func ringContains(_ ring: [Point], _ point: Point) -> Int {
        let x = point.x, y = point.y
        var contains = -1
        var j = ring.count - 1
        for i in ring.indices {
            let pi = ring[i], pj = ring[j]
            if segmentContains(pi, pj, point) { return 0 }
            if (pi.y > y) != (pj.y > y), x < (pj.x - pi.x) * (y - pi.y) / (pj.y - pi.y) + pi.x {
                contains = -contains
            }
            j = i
        }
        return contains
    }

    private static func segmentContains(_ a: Point, _ b: Point, _ c: Point) -> Bool {
        guard (b.x - a.x) * (c.y - a.y) == (c.x - a.x) * (b.y - a.y) else { return false }
        let p: Double, q: Double, r: Double
        if a.x == b.x {
            (p, q, r) = (a.y, c.y, b.y)
        } else {
            (p, q, r) = (a.x, c.x, b.x)
        }
        return p <= q && q <= r || r <= q && q <= p
    }

    // MARK: d3-polygon

    static func polygonArea(_ polygon: [Point]) -> Double {
        guard var b = polygon.last else { return 0 }
        var area = 0.0
        for a in polygon {
            area += b.y * a.x - b.x * a.y
            b = a
        }
        return area / 2
    }

    static func polygonContains(_ polygon: [Point], _ point: Point) -> Bool {
        guard let last = polygon.last else { return false }
        var x0 = last.x, y0 = last.y
        var inside = false
        for p in polygon {
            if (p.y > point.y) != (y0 > point.y), point.x < (x0 - p.x) * (point.y - p.y) / (y0 - p.y) + p.x {
                inside.toggle()
            }
            x0 = p.x
            y0 = p.y
        }
        return inside
    }

    // MARK: d3-geo

    /// Great circle distance in radians, as `d3.geoDistance` measures it.
    static func geoDistance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let lambda0 = a.lon * radians, phi0 = a.lat * radians
        let lambda = b.lon * radians, phi = b.lat * radians
        let sinPhi0 = sin(phi0), cosPhi0 = cos(phi0)
        let sinPhi = sin(phi), cosPhi = cos(phi)
        let delta = abs(lambda - lambda0)
        let cosDelta = cos(delta), sinDelta = sin(delta)
        let x = cosPhi * sinDelta
        let y = cosPhi0 * sinPhi - sinPhi0 * cosPhi * cosDelta
        let z = sinPhi0 * sinPhi + cosPhi0 * cosPhi * cosDelta
        return atan2((x * x + y * y).squareRoot(), z)
    }

    /// `d3.geoInterpolate(a, b)(t)`: the point a fraction `t` of the way along the great circle.
    static func geoInterpolate(_ a: GeoPoint, _ b: GeoPoint, _ t: Double) -> GeoPoint {
        let x0 = a.lon * radians, y0 = a.lat * radians
        let x1 = b.lon * radians, y1 = b.lat * radians
        let cy0 = cos(y0), sy0 = sin(y0), cy1 = cos(y1), sy1 = sin(y1)
        let kx0 = cy0 * cos(x0), ky0 = cy0 * sin(x0)
        let kx1 = cy1 * cos(x1), ky1 = cy1 * sin(x1)
        let d = 2 * asin((haversin(y1 - y0) + cy0 * cy1 * haversin(x1 - x0)).squareRoot())
        guard d != 0 else { return GeoPoint(lon: x0 * degrees, lat: y0 * degrees) }

        let k = sin(d)
        let td = t * d
        let bb = sin(td) / k, aa = sin(d - td) / k
        let x = aa * kx0 + bb * kx1, y = aa * ky0 + bb * ky1, z = aa * sy0 + bb * sy1
        return GeoPoint(lon: atan2(y, x) * degrees, lat: atan2(z, (x * x + y * y).squareRoot()) * degrees)
    }

    private static func haversin(_ x: Double) -> Double {
        let s = sin(x / 2)
        return s * s
    }

    /// `d3.geoGraticule()()`: meridians every 10° and parallels every 10°, the major meridians running
    /// to the poles. Its meridians are deliberately sparse, three points each, the drawing being
    /// expected to subdivide them.
    static func graticuleLines() -> [[GeoPoint]] {
        let precision = 2.5
        let (x0, x1, y0, y1) = (-180.0, 180.0, -80 - epsilon, 80 + epsilon) // minor extent
        let (bigX0, bigX1, bigY0, bigY1) = (-180.0, 180.0, -90 + epsilon, 90 - epsilon) // major extent
        let (dx, dy, bigDX, bigDY) = (10.0, 10.0, 90.0, 360.0)

        func range(_ start: Double, _ stop: Double, _ step: Double) -> [Double] {
            let count = max(0, Int(ceil((stop - start) / step)))
            return (0..<count).map { start + Double($0) * step }
        }
        func meridian(_ from: Double, _ to: Double, _ step: Double) -> (Double) -> [GeoPoint] {
            let ys = range(from, to - epsilon, step) + [to]
            return { x in ys.map { GeoPoint(lon: x, lat: $0) } }
        }
        func parallel(_ from: Double, _ to: Double, _ step: Double) -> (Double) -> [GeoPoint] {
            let xs = range(from, to - epsilon, step) + [to]
            return { y in xs.map { GeoPoint(lon: $0, lat: y) } }
        }

        let minorMeridian = meridian(y0, y1, 90)
        let minorParallel = parallel(x0, x1, precision)
        let majorMeridian = meridian(bigY0, bigY1, 90)
        let majorParallel = parallel(bigX0, bigX1, precision)

        return range(ceil(bigX0 / bigDX) * bigDX, bigX1, bigDX).map(majorMeridian)
            + range(ceil(bigY0 / bigDY) * bigDY, bigY1, bigDY).map(majorParallel)
            + range(ceil(x0 / dx) * dx, x1, dx).filter { abs(fmod($0, bigDX)) > epsilon }.map(minorMeridian)
            + range(ceil(y0 / dy) * dy, y1, dy).filter { abs(fmod($0, bigDY)) > epsilon }.map(minorParallel)
    }

    // MARK: d3-interpolate

    /// `d3.interpolateBasis(values)(t)`: the uniform B-spline through the values.
    static func interpolateBasis(_ values: [Double], _ t: Double) -> Double {
        let n = values.count - 1
        var t = t
        let i: Int
        if t <= 0 {
            t = 0
            i = 0
        } else if t >= 1 {
            t = 1
            i = n - 1
        } else {
            i = Int((t * Double(n)).rounded(.down))
        }
        let v1 = values[i], v2 = values[i + 1]
        let v0 = i > 0 ? values[i - 1] : 2 * v1 - v2
        let v3 = i < n - 1 ? values[i + 2] : 2 * v2 - v1
        let t1 = (t - Double(i) / Double(n)) * Double(n)
        let t2 = t1 * t1, t3 = t2 * t1
        return ((1 - 3 * t1 + 3 * t2 - t3) * v0
            + (4 - 6 * t2 + 3 * t3) * v1
            + (1 + 3 * t1 + 3 * t2 - 3 * t3) * v2
            + t3 * v3) / 6
    }
}
