//
//  GlobeRenderer.swift
//  norlysWidget
//
//  Draws the globe the way the website's map stacks it (app/components/apps/models/Map):
//
//  1. the model, shaded pixel by pixel as modelSurface.ts's fragment shader shades it, with the
//     moon's glow over the night it lights and the shader's dithering;
//  2. the canvas over it: the rivers and lakes, the graticule, the land outline and the magnetic
//     parallels (world.ts, magneticGraticule.ts), then the day and twilight fills of the terminator
//     (terminator.ts);
//  3. the SVG over that: the reader's position (userLocation.tsx) and the substorm rings with their
//     labels (substormMarkers.ts).
//
//  The marks the website sizes in CSS pixels are scaled down to the widget by `GlobeLayout`.
//

import CoreGraphics
import CoreText
import Foundation

/// Everything the globe shows, worked out once per model frame.
struct GlobeScene {
    /// The model's density grid, nil when there is no model to draw.
    let density: [Float]?
    let substorms: [Substorm]
    /// The instant the terminator and the moon are drawn for.
    let date: Date
    /// The point the globe is turned to face.
    let centre: GeoPoint
    let userLocation: GeoPoint?

    init(frame: AuroraModelFrame?, date: Date, centre: GeoPoint, userLocation: GeoPoint?) {
        density = frame.map(GlobeDensity.grid(for:))
        substorms = frame.map(GlobeSubstorms.substorms(in:)) ?? []
        self.date = date
        self.centre = centre
        self.userLocation = userLocation
    }
}

/// Where the globe sits in the image, and the size the website's fixed marks are drawn at.
struct GlobeLayout {
    /// Size of the image, in points.
    let size: CGSize
    /// Centre of the globe, in points.
    let centre: CGPoint
    let radius: CGFloat
    /// Points per website CSS pixel, for the rings, their labels and the location dot.
    let markerScale: CGFloat
    /// Points per website CSS pixel, for the land outline and the graticules.
    let lineScale: CGFloat
}

enum GlobeRenderer {
    // MARK: Website constants

    /// terminator.ts: the sun on the horizon, and 7° under it.
    private static let sunsetRadius = 90.0
    private static let darknessRadius = 97.0
    private static let terminatorAlpha = 0.1
    /// moon.ts: the moon's zone, and the night it is painted in, past the twilight band.
    private static let moonRadius = 90.0
    private static let nightRadius = 180 - darknessRadius
    private static let glowAlpha = 0.25

    /// substormMarkers.ts, in CSS pixels.
    private static let dash = 5.0
    private static let gap = 6.0
    private static let visibleAngle = 1.45
    private static let leader = (x: 35.0, y: 50.0)
    private static let stem = 20.0
    private static let textGap = 5.0
    private static let fontSize = 20.0
    private static let margin = 20.0
    private static let labelPadding = (x: 16.0, y: 12.0)
    private static let labelHeight = 20.0
    /// Smallest a label is set at to fit the widget, against the website's size.
    private static let minimumLabelScale = 0.6

    // MARK: Rendering

    /// The globe as an image. `opaque` lays it on the website's black page; otherwise everything off
    /// the disc is left transparent, for whatever the image is shown over.
    static func render(_ scene: GlobeScene, layout: GlobeLayout, pixelScale: CGFloat, opaque: Bool = false) -> CGImage? {
        let width = Int((layout.size.width * pixelScale).rounded())
        let height = Int((layout.size.height * pixelScale).rounded())
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return nil }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let view = GlobeView(centre: scene.centre, scale: layout.radius, translate: layout.centre, size: layout.size)
        let raster = Raster(pixels: pixels, width: width, height: height, scale: Double(pixelScale), view: view)
        if opaque {
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }

        // The model, as the GPU paints it on its own canvas under the others
        shadeModel(scene, raster: raster, opaque: opaque)

        // Points, y down, for everything drawn as paths
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: pixelScale, y: -pixelScale)

        // The canvas: rivers and lakes, graticule, land, magnetic parallels, then the terminator over them
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let grey = CGColor(srgbRed: 84 / 255, green: 84 / 255, blue: 84 / 255, alpha: 1) // #545454
        stroke(GlobeGeometry.rivers, in: context, view: view,
               color: white.copy(alpha: 0.1)!, width: layout.lineScale)
        stroke(GlobeGeometry.lakes, in: context, view: view,
               color: grey.copy(alpha: 0.5)!, width: layout.lineScale)
        stroke(GlobeGeometry.graticule, in: context, view: view,
               color: white.copy(alpha: 0.035)!, width: 0.5 * layout.lineScale)
        stroke(GlobeGeometry.land, in: context, view: view,
               color: grey.copy(alpha: 0.6)!, width: layout.lineScale)
        stroke(GlobeGeometry.magneticLatitudes, in: context, view: view,
               color: white.copy(alpha: 0.13)!, width: 0.5 * layout.lineScale)
        context.flush()
        shadeTerminator(scene, raster: raster)

        // The SVG: the reader's position under the substorm rings and their labels
        drawUserLocation(scene, in: context, view: view, scale: Double(layout.markerScale))
        drawSubstorms(scene, in: context, view: view, layout: layout)

        return context.makeImage()
    }

    /// The bitmap and the globe's place in it, as plain numbers: the passes below run for every pixel
    /// of the globe and have to stay quick in an unoptimised build too.
    private struct Raster {
        let pixels: UnsafeMutablePointer<UInt8>
        let width: Int
        let height: Int
        /// Device pixels per point.
        let scale: Double
        let view: GlobeView
        /// The view's rotation, rows as in `GlobeView.m`.
        let m0: Double, m1: Double, m2: Double, m3: Double, m4: Double, m5: Double, m6: Double, m7: Double, m8: Double
        /// Device pixels spanned by the globe, a pixel wider each side for the edge's antialiasing.
        let left: Int, right: Int, top: Int, bottom: Int

        init(pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int, scale: Double, view: GlobeView) {
            self.pixels = pixels
            self.width = width
            self.height = height
            self.scale = scale
            self.view = view
            let m = view.m
            (m0, m1, m2, m3, m4, m5, m6, m7, m8) = (m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8])
            let r = view.scale
            left = max(0, Int(floor((view.translateX - r) * scale)) - 1)
            right = min(width, Int(ceil((view.translateX + r) * scale)) + 1)
            top = max(0, Int(floor((view.translateY - r) * scale)) - 1)
            bottom = min(height, Int(ceil((view.translateY + r) * scale)) + 1)
        }

        /// Walks the pixels of the disc. `visit` gets the pixel, the plane coordinates `u` and `v` the
        /// derivatives are taken from, the point of the sphere under the pixel in the view's frame
        /// (screen x, screen y, towards the viewer) and the disc's antialiased coverage, the shader's `cover`.
        func forEachPixel(_ visit: (_ i: Int, _ j: Int, _ u: Double, _ v: Double,
                                    _ qx: Double, _ qy: Double, _ qz: Double, _ cover: Double) -> Void) {
            let cx = view.translateX, cy = view.translateY, r = view.scale
            for j in top..<bottom {
                let v = (cy - (Double(j) + 0.5) / scale) / r
                for i in left..<right {
                    let u = ((Double(i) + 0.5) / scale - cx) / r
                    let rho2 = u * u + v * v
                    let rho = rho2.squareRoot()
                    var cover = (1 - rho) * r * scale + 0.5
                    if cover <= 0 { continue }
                    if cover > 1 { cover = 1 }
                    if rho < 1 {
                        visit(i, j, u, v, u, v, (1 - rho2).squareRoot(), cover)
                    } else {
                        visit(i, j, u, v, u / rho, v / rho, 0, cover)
                    }
                }
            }
        }

        /// The shader's `inside`: how much of the pixel lies within the cap of the sphere centred on
        /// (`cx`, `cy`, `cz`) in the view's frame, whose radius has the cosine `cosRadius`. GLSL takes
        /// the value's change across the pixel with `fwidth`; here it is differentiated exactly.
        func inside(u: Double, v: Double, qx: Double, qy: Double, qz: Double,
                    cx: Double, cy: Double, cz: Double, cosRadius: Double) -> Double {
            let past = qx * cx + qy * cy + qz * cz - cosRadius
            let step = 1 / (view.scale * scale)
            let depth = qz > 1e-6 ? qz : 1e-6
            let dx = (cx - cz * u / depth) * step
            let dy = (-cy + cz * v / depth) * step
            let change = abs(dx) + abs(dy)
            let value = past / (change > 1e-9 ? change : 1e-9) + 0.5
            return value < 0 ? 0 : value > 1 ? 1 : value
        }
    }

    /// The shader's dithering hash.
    private static func grain(_ x: Float, _ y: Float) -> Float {
        var px = x * 0.1031, py = y * 0.1031, pz = x * 0.1031
        px -= floor(px)
        py -= floor(py)
        pz -= floor(pz)
        let d = px * (py + 33.33) + py * (pz + 33.33) + pz * (px + 33.33)
        px += d
        py += d
        pz += d
        let r = (px + py) * pz
        return r - floor(r)
    }

    /// modelSurface.ts's fragment shader, pixel by pixel.
    private static func shadeModel(_ scene: GlobeScene, raster: Raster, opaque: Bool) {
        let view = raster.view

        // moon.ts: the zone seeing the moon, within the night, glowing with the moon's lit fraction.
        // d3.scaleLinear([0, 1], ['#000430', '#001538']), rounded to whole colours as d3 formats them
        let illumination = GlobeEphemeris.moonIllumination(scene.date)
        let glowG = (4 + 17 * illumination).rounded() / 255, glowB = (48 + 8 * illumination).rounded() / 255
        let moon = view.toView(GlobeView.unit(GlobeEphemeris.subLunarPoint(scene.date)))
        let night = view.toView(GlobeView.unit(GlobeEphemeris.antiSolarPoint(scene.date)))
        let (moonX, moonY, moonZ) = (moon.x, moon.y, moon.z)
        let (nightX, nightY, nightZ) = (night.x, night.y, night.z)
        let moonCos = cos(moonRadius * GlobeD3.radians), nightCos = cos(nightRadius * GlobeD3.radians)
        let glow = glowAlpha

        let rampLast = Double(NorlysRamp.size - 1)
        let top = GlobeDensity.top
        let bufferHeight = Float(raster.height)
        let (m0, m1, m2, m3, m4, m5, m6, m7, m8) = (raster.m0, raster.m1, raster.m2, raster.m3, raster.m4,
                                                    raster.m5, raster.m6, raster.m7, raster.m8)
        let pixels = raster.pixels, width = raster.width

        NorlysRamp.entries.withUnsafeBufferPointer { rampBuffer in
            (scene.density ?? []).withUnsafeBufferPointer { densityBuffer in
                let ramp = rampBuffer.baseAddress!
                // Only a whole grid is read: an empty array can still hand over a base address
                let reader = densityBuffer.count == GlobeDensity.gridWidth * GlobeDensity.gridHeight
                    ? densityBuffer.baseAddress.map(DensityReader.init(density:))
                    : nil

                raster.forEachPixel { i, j, u, v, qx, qy, qz, cover in
                    let lit = raster.inside(u: u, v: v, qx: qx, qy: qy, qz: qz,
                                            cx: moonX, cy: moonY, cz: moonZ, cosRadius: moonCos)
                        * raster.inside(u: u, v: v, qx: qx, qy: qy, qz: qz,
                                        cx: nightX, cy: nightY, cz: nightZ, cosRadius: nightCos)

                    var red = 0.0, green = 0.0, blue = 0.0
                    if let reader {
                        // Back onto the globe: the view's matrix is a rotation, so its transpose undoes it
                        let value = reader.value(x: m0 * qx + m3 * qy + m6 * qz,
                                                 y: m1 * qx + m4 * qy + m7 * qz,
                                                 z: m2 * qx + m5 * qy + m8 * qz)
                        if value > 0 {
                            // The ramp's texels, filtered linearly
                            let at = (value / top < 1 ? value / top : 1) * rampLast
                            let i0 = Int(at), i1 = i0 + 1 < NorlysRamp.size ? i0 + 1 : i0
                            let t = at - Double(i0)
                            let a = ramp + i0 * 3, b = ramp + i1 * 3
                            red = Double(a[0]) + (Double(b[0]) - Double(a[0])) * t
                            green = Double(a[1]) + (Double(b[1]) - Double(a[1])) * t
                            blue = Double(a[2]) + (Double(b[2]) - Double(a[2])) * t
                        }
                    }

                    // The moon's glow, blended as a screen. Its red is zero, which leaves red as it is
                    let mix = glow * lit
                    green += (glowG - green * glowG) * mix
                    blue += (glowB - blue * glowB) * mix

                    // Dithered, in the GPU's bottom-up pixel coordinates
                    if red != 0 || green != 0 || blue != 0 {
                        let fx = Float(i) + 0.5, fy = bufferHeight - Float(j) - 0.5
                        let noise = Double(grain(fx, fy) + grain(fx + 71, fy + 71) - 1) / 255
                        red += noise
                        green += noise
                        blue += noise
                    }

                    let offset = (j * width + i) * 4
                    pixels[offset] = UInt8((red < 0 ? 0 : red > 1 ? 1 : red) * cover * 255 + 0.5)
                    pixels[offset + 1] = UInt8((green < 0 ? 0 : green > 1 ? 1 : green) * cover * 255 + 0.5)
                    pixels[offset + 2] = UInt8((blue < 0 ? 0 : blue > 1 ? 1 : blue) * cover * 255 + 0.5)
                    // Over black, the disc's antialiased edge only darkens the colour: the page stays opaque
                    pixels[offset + 3] = opaque ? 255 : UInt8(cover * 255 + 0.5)
                }
            }
        }
    }

    /// terminator.ts: the circles around the sun at 90° and 97°, each filled white at a tenth, so the
    /// day is lit twice and the twilight band once.
    private static func shadeTerminator(_ scene: GlobeScene, raster: Raster) {
        let sun = raster.view.toView(GlobeView.unit(GlobeEphemeris.subSolarPoint(scene.date)))
        let (sunX, sunY, sunZ) = (sun.x, sun.y, sun.z)
        let sunset = cos(sunsetRadius * GlobeD3.radians), darkness = cos(darknessRadius * GlobeD3.radians)
        let pixels = raster.pixels, width = raster.width

        // White over the premultiplied pixel, rounded to whole levels as the canvas holds them
        func fill(_ offset: Int, _ alpha: Double) {
            if alpha <= 0 { return }
            let keep = 1 - alpha, white = 255 * alpha + 0.5
            let red = Double(pixels[offset]) * keep + white, green = Double(pixels[offset + 1]) * keep + white
            let blue = Double(pixels[offset + 2]) * keep + white, opacity = Double(pixels[offset + 3]) * keep + white
            pixels[offset] = UInt8(red < 255 ? red : 255)
            pixels[offset + 1] = UInt8(green < 255 ? green : 255)
            pixels[offset + 2] = UInt8(blue < 255 ? blue : 255)
            pixels[offset + 3] = UInt8(opacity < 255 ? opacity : 255)
        }

        raster.forEachPixel { i, j, u, v, qx, qy, qz, cover in
            let offset = (j * width + i) * 4
            fill(offset, terminatorAlpha * cover * raster.inside(u: u, v: v, qx: qx, qy: qy, qz: qz,
                                                                 cx: sunX, cy: sunY, cz: sunZ, cosRadius: sunset))
            fill(offset, terminatorAlpha * cover * raster.inside(u: u, v: v, qx: qx, qy: qy, qz: qz,
                                                                 cx: sunX, cy: sunY, cz: sunZ, cosRadius: darkness))
        }
    }

    private static func stroke(_ geometry: SphereGeometry?, in context: CGContext, view: GlobeView, color: CGColor, width: CGFloat) {
        guard let geometry else { return }
        let path = CGMutablePath()
        geometry.trace(into: path, view: view)
        context.addPath(path)
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.setLineCap(.butt)
        context.setLineJoin(.miter)
        context.setMiterLimit(10)
        context.strokePath()
    }

    // MARK: SVG

    /// userLocation.tsx: a blue dot ringed in white, left out while it is round the back of the globe.
    private static func drawUserLocation(_ scene: GlobeScene, in context: CGContext, view: GlobeView, scale: Double) {
        guard let location = scene.userLocation, GlobeD3.geoDistance(location, view.centre) <= 1.57 else { return }

        let point = view.project(location)
        let radius = 10 * scale
        let circle = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.setFillColor(CGColor(srgbRed: 0x48 / 255, green: 0xBC / 255, blue: 0xFF / 255, alpha: 1))
        context.fillEllipse(in: circle)
        context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.setLineWidth(3 * scale)
        context.strokeEllipse(in: circle)
    }

    /// A substorm as it is drawn: its dashes, its name and where the name goes.
    private struct DrawnSubstorm {
        let substorm: Substorm
        let dashes: [[GeoPoint]]
        var font: CTFont
        var line: CTLine
        /// Room the name takes, measured as it is set rather than counted in glyphs.
        var width: Double
        var placement: Placement?

        init(substorm: Substorm, dashes: [[GeoPoint]], fontSize: Double) {
            self.substorm = substorm
            self.dashes = dashes
            (font, line, width) = DrawnSubstorm.typeset(substorm.level.name, size: fontSize)
        }

        mutating func resize(to size: Double) {
            (font, line, width) = DrawnSubstorm.typeset(substorm.level.name, size: size)
        }

        /// The name in the website's face, Helvetica Bold.
        private static func typeset(_ text: String, size: Double) -> (CTFont, CTLine, Double) {
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
            let attributed = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            return (font, line, CTLineGetTypographicBounds(line, nil, nil, nil))
        }
    }

    private struct Placement {
        let x: Double
        let y: Double
        let flipX: Bool
        let flipY: Bool
        let box: CGRect
    }

    private static func drawSubstorms(_ scene: GlobeScene, in context: CGContext, view: GlobeView, layout: GlobeLayout) {
        guard !scene.substorms.isEmpty else { return }
        let k = Double(layout.markerScale)
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let halo = white.copy(alpha: 0.2)!

        var substorms = scene.substorms.map { substorm in
            // Dashes are cut to a length on screen, at the zoom they are drawn at
            DrawnSubstorm(substorm: substorm, dashes: substorm.rings.flatMap {
                GlobeSubstorms.dashes(of: $0, scale: view.scale, dash: dash * k, gap: gap * k)
            }, fontSize: fontSize * k)
        }

        // The rings, each in a group at its level's opacity: a halo under the ring keeps it readable
        // over the brightest part of the oval
        for drawn in substorms {
            let path = dashPath(drawn.dashes, view: view)
            context.saveGState()
            context.setAlpha(drawn.substorm.level.opacity)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.setLineCap(.butt)
            context.setLineJoin(.miter)
            context.setMiterLimit(4)
            context.addPath(path)
            context.setStrokeColor(halo)
            context.setLineWidth(5 * k)
            context.strokePath()
            context.addPath(path)
            context.setStrokeColor(white)
            context.setLineWidth(1.5 * k)
            context.strokePath()
            context.endTransparencyLayer()
            context.restoreGState()
        }

        // Each label hangs off its own ring, folded back where it would run off the image
        for index in substorms.indices {
            substorms[index].placement = place(&substorms[index], view: view, layout: layout)
        }
        // Labels landing on one another: only the strongest substorm's is worth reading
        var placed: [CGRect] = []
        let order = substorms.indices.sorted { a, b in
            let levels = (substorms[a].substorm.level.value, substorms[b].substorm.level.value)
            return levels.0 != levels.1 ? levels.0 > levels.1 : a < b
        }
        for index in order {
            guard let box = substorms[index].placement?.box else { continue }
            let collides = placed.contains { other in
                box.minX < other.maxX + labelPadding.x * k && other.minX < box.maxX + labelPadding.x * k
                    && box.minY < other.maxY + labelPadding.y * k && other.minY < box.maxY + labelPadding.y * k
            }
            if collides {
                substorms[index].placement = nil
            } else {
                placed.append(box)
            }
        }

        for drawn in substorms {
            guard let placement = drawn.placement else { continue }
            drawLabel(drawn, placement: placement, in: context, k: k)
        }
    }

    /// The dashes as one path, each cut where it passes behind the globe.
    private static func dashPath(_ dashes: [[GeoPoint]], view: GlobeView) -> CGPath {
        let path = CGMutablePath()
        for dash in dashes {
            var previous: SIMD3<Double>?
            for point in dash {
                let p = GlobeView.unit(point)
                let facing = view.facing(p)
                if let previous {
                    let before = view.facing(previous)
                    if before >= 0, facing >= 0 {
                        path.addLine(to: view.screen(p))
                    } else if before >= 0 || facing >= 0 {
                        // Crossing the horizon: end or start the line where it passes over it
                        let crossing = previous + (p - previous) * (before / (before - facing))
                        let onHorizon = view.screen(crossing / (crossing * crossing).sum().squareRoot())
                        if before >= 0 {
                            path.addLine(to: onHorizon)
                        } else {
                            path.move(to: onHorizon)
                            path.addLine(to: view.screen(p))
                        }
                    }
                } else if facing >= 0 {
                    path.move(to: view.screen(p))
                }
                previous = p
            }
        }
        return path
    }

    /// The point of a ring furthest towards where its label goes, among those facing the reader.
    private static func anchor(_ ring: [GeoPoint], view: GlobeView, flipX: Bool, flipY: Bool) -> CGPoint? {
        let dirX: Double = flipX ? -1 : 1, dirY: Double = flipY ? -1 : 1
        var best: (point: CGPoint, reach: Double)?
        for point in ring where GlobeD3.geoDistance(point, view.centre) <= visibleAngle {
            let projected = view.project(point)
            let reach = projected.x * dirX + projected.y * dirY
            if let current = best, reach <= current.reach { continue }
            best = (projected, reach)
        }
        return best?.point
    }

    /// Where a label goes: hung off its ring as the website hangs it, folded back from the right and the
    /// bottom of the image. A widget is narrower than any page, so a label that would still run off a
    /// side goes to the side it overruns less, and is set smaller until it fits there.
    private static func place(_ drawn: inout DrawnSubstorm, view: GlobeView, layout: GlobeLayout) -> Placement? {
        let k = Double(layout.markerScale)
        guard let ring = drawn.substorm.rings.first,
              let first = anchor(ring, view: view, flipX: false, flipY: false) else { return nil }

        let offset = (leader.x + stem + textGap) * k
        let flipY = first.y + leader.y * k > layout.size.height - margin * k
        var flipX = first.x + offset + drawn.width > layout.size.width - margin * k
        var folded = flipX || flipY ? anchor(ring, view: view, flipX: flipX, flipY: flipY) ?? first : first

        // How far the name runs past the image's margins, hung off `point` towards the left or the right
        let lower = margin * k, upper = layout.size.width - margin * k
        func overrun(_ point: CGPoint, left: Bool, width: Double) -> Double {
            let start = point.x + (left ? -offset : offset)
            let end = start + (left ? -width : width)
            return max(0, lower - min(start, end)) + max(0, max(start, end) - upper)
        }
        if overrun(folded, left: flipX, width: drawn.width) > 0 {
            let other = anchor(ring, view: view, flipX: !flipX, flipY: flipY) ?? folded
            if overrun(other, left: !flipX, width: drawn.width) < overrun(folded, left: flipX, width: drawn.width) {
                flipX.toggle()
                folded = other
            }
            let excess = overrun(folded, left: flipX, width: drawn.width)
            if excess > 0 {
                drawn.resize(to: fontSize * k * max(minimumLabelScale, (drawn.width - excess) / drawn.width))
            }
        }

        let dirX: Double = flipX ? -1 : 1, dirY: Double = flipY ? -1 : 1
        let start = folded.x + offset * dirX
        let end = start + drawn.width * dirX
        let middle = folded.y + leader.y * k * dirY
        let box = CGRect(x: min(start, end), y: middle - labelHeight * k / 2,
                         width: abs(end - start), height: labelHeight * k)
        return Placement(x: folded.x, y: folded.y, flipX: flipX, flipY: flipY, box: box)
    }

    private static func drawLabel(_ drawn: DrawnSubstorm, placement: Placement, in context: CGContext, k: Double) {
        let dirX: Double = placement.flipX ? -1 : 1, dirY: Double = placement.flipY ? -1 : 1
        let origin = CGPoint(x: placement.x, y: placement.y)
        let corner = CGPoint(x: origin.x + leader.x * k * dirX, y: origin.y + leader.y * k * dirY)
        let stemEnd = CGPoint(x: corner.x + stem * k * dirX, y: corner.y)
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

        context.saveGState()
        context.setLineCap(.butt)
        for (from, to) in [(origin, corner), (corner, stemEnd)] {
            for (color, width) in [(white.copy(alpha: 0.2)!, 5 * k), (white, 2 * k)] {
                context.move(to: from)
                context.addLine(to: to)
                context.setStrokeColor(color)
                context.setLineWidth(width)
                context.strokePath()
            }
        }

        // `dominant-baseline: middle` puts the middle of the x-height on the line
        let textX = stemEnd.x + textGap * k * dirX
        let x = placement.flipX ? textX - drawn.width : textX
        let baseline = stemEnd.y + Double(CTFontGetXHeight(drawn.font)) / 2
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

        // `paint-order: stroke`: a faint stroke under the white glyphs
        context.setTextDrawingMode(.stroke)
        context.setLineWidth(4 * k)
        context.setLineJoin(.miter)
        context.setMiterLimit(4)
        context.setStrokeColor(white.copy(alpha: 0.1)!)
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(drawn.line, context)

        context.setTextDrawingMode(.fill)
        context.setFillColor(white)
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(drawn.line, context)
        context.restoreGState()
    }
}
