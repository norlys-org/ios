//
//  GlobeSubstorms.swift
//  norlysWidget
//
//  Where the oval is moving fastest, ringed as the website rings it (map/features/substormMarkers.ts
//  and helpers/substorms.ts): the model's derivative is laid over a grid of the rotated globe,
//  blurred, and cut at the substorm levels with marching squares, one dashed ring per substorm at the
//  strongest level it reaches.
//

import Foundation

struct SubstormLevel: Equatable {
    /// Level of the model's derivative, out of five.
    let value: Double
    let name: String
    /// Opacity the ring is drawn at.
    let opacity: Double

    static let all = [
        SubstormLevel(value: 2, name: String(localized: "Dynamic"), opacity: 0.45),
        SubstormLevel(value: 2.4, name: String(localized: "Very Dynamic"), opacity: 0.7),
        SubstormLevel(value: 3, name: String(localized: "Extremely Dynamic"), opacity: 1)
    ]
}

/// A substorm the model has drawn a ring around, at the strongest level it reaches.
struct Substorm {
    let level: SubstormLevel
    /// Its outline first, then any hole inside it.
    let rings: [[GeoPoint]]
}

enum GlobeSubstorms {
    /// Rings the globe carries at once.
    private static let maxRings = 3
    /// Cell of the grid the rings are cut from, in degrees of the rotated globe.
    private static let cellSize = 0.5
    /// Cells left empty around the model, so a ring closing just outside it is not cut by the grid.
    private static let gridMargin = 8
    /// Area a ring has to close, in square degrees, to be worth drawing.
    private static let minRingArea = 4.0
    /// Blur radius, in cells, rounding the rings off.
    private static let blur = 2.0
    /// Dashes a ring is cut into at most.
    private static let maxDashes = 500

    /// The model's derivative as it is computed, a regular grid of longitudes and latitudes.
    private struct SpeedField {
        let values: [Double]
        let columns: Int
        let rows: Int
        let lon: Double
        let lat: Double
        let lonStep: Double
        let latStep: Double
    }

    private final class Patch {
        let level: Int
        let rings: [[GlobeD3.Point]]
        var parent: Patch?

        init(level: Int, rings: [[GlobeD3.Point]]) {
            self.level = level
            self.rings = rings
        }
    }

    /// Lays the derivative of every point back onto the grid it was computed on.
    private static func readField(_ frame: AuroraModelFrame) -> SpeedField? {
        // `Number(value.toFixed(4))`, enough to tell two grid lines apart
        func round(_ value: Double) -> Double { (value * 1e4).rounded() / 1e4 }

        let lons = Array(Set(frame.points.map { round($0.lon) })).sorted()
        let lats = Array(Set(frame.points.map { round($0.lat) })).sorted()
        guard lons.count >= 2, lats.count >= 2 else { return nil }

        let lonIndex = Dictionary(uniqueKeysWithValues: lons.enumerated().map { ($1, $0) })
        let latIndex = Dictionary(uniqueKeysWithValues: lats.enumerated().map { ($1, $0) })
        var values = [Double](repeating: 0, count: lons.count * lats.count)
        for point in frame.points {
            guard let x = lonIndex[round(point.lon)], let y = latIndex[round(point.lat)] else { continue }
            values[y * lons.count + x] = Double(point.speed)
        }

        return SpeedField(
            values: values,
            columns: lons.count,
            rows: lats.count,
            lon: lons[0],
            lat: lats[0],
            lonStep: (lons[lons.count - 1] - lons[0]) / Double(lons.count - 1),
            latStep: (lats[lats.count - 1] - lats[0]) / Double(lats.count - 1)
        )
    }

    /// The derivative anywhere on the globe. A longitude falling off one end of the field is read from
    /// the other; the latitudes it does not cover read as quiet.
    private static func sample(_ field: SpeedField, _ lon: Double, _ lat: Double) -> Double {
        let gridY = (lat - field.lat) / field.latStep
        guard gridY >= 0, gridY <= Double(field.rows - 1) else { return 0 }
        let y0 = min(Int(gridY.rounded(.down)), field.rows - 2)
        let ty = gridY - Double(y0)

        let turn = 360 / field.lonStep
        let gridX = fmod(fmod((lon - field.lon) / field.lonStep, turn) + turn, turn)
        let xa = Int(gridX.rounded(.down))
        guard xa < field.columns else { return 0 }
        let tx = gridX - Double(xa)
        let xb = (xa + 1) % field.columns

        let values = field.values, columns = field.columns
        return values[y0 * columns + xa] * (1 - tx) * (1 - ty)
            + values[y0 * columns + xb] * tx * (1 - ty)
            + values[(y0 + 1) * columns + xa] * (1 - tx) * ty
            + values[(y0 + 1) * columns + xb] * tx * ty
    }

    /// Every substorm the model is drawing, in longitude and latitude.
    static func substorms(in frame: AuroraModelFrame) -> [Substorm] {
        // Blurring only ever brings the peak down, so a model that never reaches the first level has
        // nothing to ring. Quiet is the common case
        let peak = frame.points.map { Double($0.speed) }.max() ?? 0
        guard peak >= SubstormLevel.all[0].value, let field = readField(frame) else { return [] }

        // The grid is laid over the rotated globe, which brings the whole modelled band into one patch
        var minLon = Double.infinity, maxLon = -Double.infinity
        var minLat = Double.infinity, maxLat = -Double.infinity
        for point in frame.points {
            let rotated = GlobeDensity.rotateCoordinates(point.lon, point.lat)
            minLon = min(minLon, rotated.lon)
            maxLon = max(maxLon, rotated.lon)
            minLat = min(minLat, rotated.lat)
            maxLat = max(maxLat, rotated.lat)
        }
        let gridLon = minLon - Double(gridMargin) * cellSize
        let gridLat = minLat - Double(gridMargin) * cellSize
        let width = Int(((maxLon - minLon) / cellSize).rounded(.up)) + 2 * gridMargin
        let height = Int(((maxLat - minLat) / cellSize).rounded(.up)) + 2 * gridMargin

        var values = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let point = GlobeDensity.invertRotation(gridLon + Double(x) * cellSize, gridLat + Double(y) * cellSize)
                values[y * width + x] = sample(field, point.lon, point.lat)
            }
        }
        GlobeD3.blur2(&values, width: width, height: height, radius: blur)

        let contours = GlobeD3.contours(values, width: width, height: height, thresholds: SubstormLevel.all.map(\.value))
        var patches: [Patch] = []
        for (level, polygons) in contours.enumerated() {
            for polygon in polygons where abs(GlobeD3.polygonArea(polygon[0])) * cellSize * cellSize >= minRingArea {
                patches.append(Patch(level: level, rings: polygon))
            }
        }

        return keepStrongest(patches).map { patch in
            Substorm(level: SubstormLevel.all[patch.level], rings: patch.rings.map { ring in
                ring.map { GlobeDensity.invertRotation(gridLon + $0.x * cellSize, gridLat + $0.y * cellSize) }
            })
        }
    }

    /// The innermost ring of each stack of levels, stepped back out to the rings enclosing them while
    /// there are more than the globe can carry.
    private static func keepStrongest(_ patches: [Patch]) -> [Patch] {
        for patch in patches {
            patch.parent = stableSorted(patches.filter { other in
                other.level < patch.level && GlobeD3.polygonContains(other.rings[0], patch.rings[0][0])
            }) { $0.level > $1.level }.first
        }

        var kept = patches.filter { patch in !patches.contains { $0.parent === patch } }
        while kept.count > maxRings {
            // Only the rings sharing an enclosing one are stepped back out to it
            var stepped: [Patch] = []
            for patch in kept {
                let parent = patch.parent
                let merges = parent != nil && kept.filter { $0.parent === parent }.count > 1
                let ring = merges ? parent! : patch
                if !stepped.contains(where: { $0 === ring }) { stepped.append(ring) }
            }
            if stepped.count == kept.count { break }
            kept = stepped
        }
        if kept.count <= maxRings { return kept }

        // Nothing encloses them any more, so the widest of the strongest are the ones worth the room
        return Array(stableSorted(kept) { a, b in
            if a.level != b.level { return a.level > b.level }
            return abs(GlobeD3.polygonArea(a.rings[0])) > abs(GlobeD3.polygonArea(b.rings[0]))
        }.prefix(maxRings))
    }

    /// JavaScript's sort is stable, which the ties above rely on.
    private static func stableSorted<T>(_ items: [T], by areInIncreasingOrder: (T, T) -> Bool) -> [T] {
        items.enumerated().sorted { a, b in
            if areInIncreasingOrder(a.element, b.element) { return true }
            if areInIncreasingOrder(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Cuts a ring into the dashes it is drawn as, stretched to a whole number of dashes so the
    /// pattern closes where the ring does. `scale` is the projection's, in points per radian.
    static func dashes(of ring: [GeoPoint], scale: Double, dash: Double, gap: Double) -> [[GeoPoint]] {
        guard ring.count > 1 else { return [] }
        let lengths = (1..<ring.count).map { GlobeD3.geoDistance(ring[$0 - 1], ring[$0]) * 180 / .pi }
        let perimeter = lengths.reduce(0) { $1.isNaN ? $0 : $0 + $1 }
        let pixels = scale * .pi / 180
        let cycles = min(Double(maxDashes), max(1, (perimeter * pixels / (dash + gap)).rounded()))
        let cycle = perimeter / cycles
        let dashArc = cycle * dash / (dash + gap)

        var dashes: [[GeoPoint]] = []
        var current = [ring[0]]
        var on = true
        var remaining = dashArc

        for i in 1..<ring.count {
            let length = lengths[i - 1]
            var walked = 0.0
            while length - walked > remaining {
                walked += remaining
                let cut = GlobeD3.geoInterpolate(ring[i - 1], ring[i], walked / length)
                if on {
                    current.append(cut)
                    dashes.append(current)
                } else {
                    current = [cut]
                }
                on.toggle()
                remaining = on ? dashArc : cycle - dashArc
            }
            remaining -= length - walked
            if on { current.append(ring[i]) }
        }
        if on, current.count > 1 { dashes.append(current) }

        return dashes
    }
}
