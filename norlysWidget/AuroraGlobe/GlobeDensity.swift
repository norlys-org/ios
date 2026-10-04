//
//  GlobeDensity.swift
//  norlysWidget
//
//  The model's oval as the website shades it (map/features/norlysModel.ts and modelSurface.ts):
//  every point's score is spread onto a one degree grid laid over a rotated globe, mirrored onto the
//  southern geomagnetic pole and blurred, and each pixel of the globe then reads that grid back with
//  a Catmull-Rom filter and looks its colour up in the norlys ramp.
//

import Foundation

enum GlobeDensity {
    /// Latitude taken off every point so the oval is stretched rather than joined over the pole.
    static let latitudeShift = 20.0
    static let shiftCos = cos(latitudeShift * .pi / 180)
    static let shiftSin = sin(latitudeShift * .pi / 180)
    /// The grid d3.contourDensity uses with a bandwidth of 2: a degree per cell, padded by 3 blur radii.
    static let blurRadius = (17.0.squareRoot() - 1) / 2
    static let padding = blurRadius * 3
    static let gridWidth = Int((360 + padding * 2).rounded(.down))
    static let gridHeight = Int((180 + padding * 2).rounded(.down))
    /// The value the ramp tops out at (`norlysTop`).
    static let top = 10.0

    static let southGeomagneticPole = GeoPoint(lon: 107.2, lat: -80.8)
    static let northGeomagneticPole = GeoPoint(lon: -72.8, lat: 80.8)

    // MARK: Rotations

    /// Turns the globe so the oval lies over one contiguous stretch of the grid, without the seam at
    /// 180° the raw longitudes would put through it.
    static func rotateCoordinates(_ lon: Double, _ lat: Double) -> GeoPoint {
        let lonRad = lon * .pi / 180
        let latRad = lat * .pi / 180
        let preLon = lonRad - .pi / 2
        let x = cos(latRad) * cos(preLon)
        let y = cos(latRad) * sin(preLon)
        let z = sin(latRad)
        var newLon = atan2(y, z) * 180 / .pi
        let newLat = asin(-x) * 180 / .pi
        newLon += 90
        if newLon < 0 { newLon += 360 }
        return GeoPoint(lon: newLon, lat: newLat)
    }

    /// Undoes `rotateCoordinates`.
    static func invertRotation(_ lon: Double, _ lat: Double) -> GeoPoint {
        let lonRad = lon * .pi / 180
        let latRad = lat * .pi / 180
        let preLon = lonRad - .pi / 2
        let x = cos(latRad) * cos(preLon)
        let y = cos(latRad) * sin(preLon)
        let z = sin(latRad)
        var originalLon = atan2(y, -z) * 180 / .pi
        let originalLat = asin(x) * 180 / .pi
        originalLon += 90
        if originalLon < 0 { originalLon += 360 }
        return GeoPoint(lon: originalLon, lat: originalLat)
    }

    /// Carries a point of the northern oval over to the southern geomagnetic pole.
    static func rotateToGeomagneticSouthPole(_ lon: Double, _ lat: Double) -> GeoPoint {
        let lonRad = lon * .pi / 180
        let latRad = lat * .pi / 180
        let centerLonRad = northGeomagneticPole.lon * .pi / 180
        let centerLatRad = southGeomagneticPole.lat * .pi / 180
        let targetLonRad = southGeomagneticPole.lon * .pi / 180
        let targetLatRad = southGeomagneticPole.lat * .pi / 180

        let x = cos(latRad) * cos(lonRad)
        let y = cos(latRad) * sin(lonRad)
        let z = sin(latRad)
        let centerX = cos(centerLatRad) * cos(centerLonRad)
        let centerY = cos(centerLatRad) * sin(centerLonRad)
        let centerZ = sin(centerLatRad)
        let targetX = cos(targetLatRad) * cos(targetLonRad)
        let targetY = cos(targetLatRad) * sin(targetLonRad)
        let targetZ = sin(targetLatRad)

        // Rodrigues' rotation about the axis from the one pole to the other
        let axisX = centerY * targetZ - centerZ * targetY
        let axisY = centerZ * targetX - centerX * targetZ
        let axisZ = centerX * targetY - centerY * targetX
        let axisLength = (axisX * axisX + axisY * axisY + axisZ * axisZ).squareRoot()
        let ax = axisX / axisLength, ay = axisY / axisLength, az = axisZ / axisLength
        let angle = acos(centerX * targetX + centerY * targetY + centerZ * targetZ)
        let cosAngle = cos(angle)
        let sinAngle = sin(angle)
        let oneMinusCos = 1 - cosAngle

        let xPrime = x * (cosAngle + ax * ax * oneMinusCos)
            + y * (ax * ay * oneMinusCos - az * sinAngle)
            + z * (ax * az * oneMinusCos + ay * sinAngle)
        let yPrime = x * (ay * ax * oneMinusCos + az * sinAngle)
            + y * (cosAngle + ay * ay * oneMinusCos)
            + z * (ay * az * oneMinusCos - ax * sinAngle)
        let zPrime = x * (az * ax * oneMinusCos - ay * sinAngle)
            + y * (az * ay * oneMinusCos + ax * sinAngle)
            + z * (cosAngle + az * az * oneMinusCos)

        return GeoPoint(lon: atan2(yPrime, xPrime) * 180 / .pi, lat: asin(zPrime) * 180 / .pi)
    }

    // MARK: Grid

    /// The longitude each column covers, in grid steps: the grid's 179° column is only 1° from -180°.
    private static func longitudeSpans(_ frame: AuroraModelFrame) -> [Double] {
        let lons = (0..<frame.lons).map { frame.points[$0].lon }
        guard lons.count > 1 else { return [Double](repeating: 1, count: lons.count) }
        let step = (lons[lons.count - 1] - lons[0]) / Double(lons.count - 1)
        return lons.indices.map { i in
            let previous = i > 0 ? lons[i - 1] : lons[lons.count - 1] - 360
            let next = i < lons.count - 1 ? lons[i + 1] : lons[0] + 360
            return (next - previous) / 2 / step
        }
    }

    /// The model's density over the grid, as `densityGrid` builds it: 20° of latitude removed, the
    /// globe rotated, the oval mirrored onto the southern geomagnetic pole, then blurred.
    static func grid(for frame: AuroraModelFrame) -> [Float] {
        var values = [Float](repeating: 0, count: gridWidth * gridHeight)
        let spans = longitudeSpans(frame)

        func add(_ lon: Double, _ lat: Double, _ score: Float, _ span: Double) {
            let rotated = rotateCoordinates(lon, lat < 0 ? lat + latitudeShift : lat - latitudeShift)
            let xi = rotated.lon + padding, yi = rotated.lat + 90 + padding
            // Ponderated to help high values that are alone to stand out
            let weight = pow(Double(score), 1.5) * span
            guard weight != 0, !weight.isNaN, xi >= 0, xi < Double(gridWidth), yi >= 0, yi < Double(gridHeight) else { return }

            let x0 = Int(xi.rounded(.down)), y0 = Int(yi.rounded(.down))
            let xt = xi - Double(x0) - 0.5, yt = yi - Double(y0) - 0.5
            // Float32Array semantics: summed in double, stored rounded, writes past the end dropped
            func accumulate(_ index: Int, _ amount: Double) {
                guard index < values.count else { return }
                values[index] = Float(Double(values[index]) + amount)
            }
            accumulate(x0 + y0 * gridWidth, (1 - xt) * (1 - yt) * weight)
            accumulate(x0 + 1 + y0 * gridWidth, xt * (1 - yt) * weight)
            accumulate(x0 + 1 + (y0 + 1) * gridWidth, xt * yt * weight)
            accumulate(x0 + (y0 + 1) * gridWidth, (1 - xt) * yt * weight)
        }

        for (index, point) in frame.points.enumerated() {
            add(point.lon, point.lat, point.score, spans[index % frame.lons])
        }
        for (index, point) in frame.points.enumerated() {
            let south = rotateToGeomagneticSouthPole(point.lon, -point.lat)
            add(south.lon, south.lat, point.score, spans[index % frame.lons])
        }
        GlobeD3.blur2(&values, width: gridWidth, height: gridHeight, radius: blurRadius)

        return values
    }

    // MARK: Reading

    /// The density at a point of the unit sphere, read as the website's shader reads it.
    static func value(in density: UnsafeBufferPointer<Float>, x: Double, y: Double, z: Double) -> Double {
        guard density.count == gridWidth * gridHeight, let base = density.baseAddress else { return 0 }
        return DensityReader(density: base).value(x: x, y: y, z: z)
    }
}

/// `GlobeDensity.value`, in plain arithmetic: it runs for every pixel of the globe, and has to stay
/// quick in an unoptimised build too.
struct DensityReader {
    private let density: UnsafePointer<Float>
    private let shiftCos = GlobeDensity.shiftCos
    private let shiftSin = GlobeDensity.shiftSin
    private let padding = GlobeDensity.padding
    private let width = GlobeDensity.gridWidth
    private let height = GlobeDensity.gridHeight

    init(density: UnsafePointer<Float>) {
        self.density = density
    }

    func value(x: Double, y: Double, z: Double) -> Double {
        // The latitude shift folds the band around the equator onto the latitudes beyond it
        if z < shiftSin && z > -shiftSin { return 0 }

        let across = (x * x + y * y).squareRoot()
        let side: Double = z > 0 ? 1 : -1
        let sinShifted = z * shiftCos - side * across * shiftSin
        let cosShifted = across * shiftCos + side * z * shiftSin
        let cosLon = across > 1e-9 ? x / across : 1
        let sinLon = across > 1e-9 ? y / across : 0

        // rotateCoordinates, without going through degrees
        let rx = sinShifted, ry = -cosShifted * cosLon, rz = -cosShifted * sinLon
        var frameX = atan2(ry, rx) * 180 / .pi + 90
        if frameX < 0 { frameX += 360 }
        let frameY = atan2(rz, (rx * rx + ry * ry).squareRoot()) * 180 / .pi + 90

        let gridX = frameX + padding - 0.5, gridY = frameY + padding - 0.5
        let floorX = floor(gridX), floorY = floor(gridY)
        let i = Int(floorX), j = Int(floorY)

        // Catmull-Rom weights, for the four columns and the four rows around the point
        let tx = gridX - floorX, tx2 = tx * tx, tx3 = tx2 * tx
        let wx0 = (-tx3 + 2 * tx2 - tx) / 2, wx1 = (3 * tx3 - 5 * tx2 + 2) / 2
        let wx2 = (-3 * tx3 + 4 * tx2 + tx) / 2, wx3 = (tx3 - tx2) / 2
        let ty = gridY - floorY, ty2 = ty * ty, ty3 = ty2 * ty
        let wy0 = (-ty3 + 2 * ty2 - ty) / 2, wy1 = (3 * ty3 - 5 * ty2 + 2) / 2
        let wy2 = (-3 * ty3 + 4 * ty2 + ty) / 2, wy3 = (ty3 - ty2) / 2

        // Away from the grid's edges every tap is inside it, the common case
        if i >= 1, j >= 1, i + 2 < width, j + 2 < height {
            var row = density + ((j - 1) * width + i - 1)
            var sum = wy0 * (wx0 * Double(row[0]) + wx1 * Double(row[1]) + wx2 * Double(row[2]) + wx3 * Double(row[3]))
            row += width
            sum += wy1 * (wx0 * Double(row[0]) + wx1 * Double(row[1]) + wx2 * Double(row[2]) + wx3 * Double(row[3]))
            row += width
            sum += wy2 * (wx0 * Double(row[0]) + wx1 * Double(row[1]) + wx2 * Double(row[2]) + wx3 * Double(row[3]))
            row += width
            sum += wy3 * (wx0 * Double(row[0]) + wx1 * Double(row[1]) + wx2 * Double(row[2]) + wx3 * Double(row[3]))
            return sum
        }

        // Taps falling off the grid read as zero, as the shader's `at` reads them
        func at(_ column: Int, _ row: Int) -> Double {
            column < 0 || row < 0 || column >= width || row >= height ? 0 : Double(density[row * width + column])
        }
        var sum = 0.0
        for (b, wy) in [wy0, wy1, wy2, wy3].enumerated() {
            let row = j + b - 1
            sum += wy * (wx0 * at(i - 1, row) + wx1 * at(i, row) + wx2 * at(i + 1, row) + wx3 * at(i + 2, row))
        }
        return sum
    }
}

// MARK: - Colour ramp

/// The norlys colour scale before d3 rounds it to whole colours, as the website uploads it to the
/// GPU: 1024 entries of a basis spline through the stops, in half floats, read with linear filtering.
enum NorlysRamp {
    static let size = 1024

    /// `norlysStops`: black, primary 900, the lightened primaries 800 to 600, primary 500 to 100.
    static let stops: [(Double, Double, Double)] = [
        0x000000, 0x0D5321, 0x10742B, 0x169634, 0x0BBA38, 0x09DE46, 0x33F56B, 0x59FF88, 0xB2FFC7, 0xD7FFE2
    ].map { (hex: Int) in
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    /// Red, green and blue of each entry, three floats each.
    static let entries: [Float] = {
        let channels = [stops.map(\.0), stops.map(\.1), stops.map(\.2)]
        var entries = [Float](repeating: 0, count: size * 3)
        for i in 0..<size {
            for c in 0..<3 {
                let value = Float(GlobeD3.interpolateBasis(channels[c], Double(i) / Double(size - 1)))
                entries[i * 3 + c] = halfFloat(value)
            }
        }
        return entries
    }()

    /// The value an RGBA16F texture holds for a float, rounded to the nearest half.
    private static func halfFloat(_ value: Float) -> Float {
        #if arch(arm64)
        return Float(Float16(value))
        #else
        return value
        #endif
    }
}
