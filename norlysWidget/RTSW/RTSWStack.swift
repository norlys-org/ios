//
//  RTSWStack.swift
//  norlysWidget
//
//  Prepares the solar wind stackplot drawn by the large widget, after the one on
//  norlys.live/rtsw: the same panels, scales, ticks, colours and backgrounds. Every
//  position is normalised, x from 0 at the start of the window to 1 at its end and
//  y from 0 at the top of a panel to 1 at its bottom; RTSWStackView draws it.
//

import SwiftUI

// MARK: - Palette

/// A colour the way the website's d3 scales mix it: sRGB channels (0-255) and opacity, interpolated linearly.
struct RTSWColor {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double = 1

    init(_ hex: UInt32, opacity: Double = 1) {
        red = Double((hex >> 16) & 0xFF)
        green = Double((hex >> 8) & 0xFF)
        blue = Double(hex & 0xFF)
        self.opacity = opacity
    }

    init(red: Double, green: Double, blue: Double, opacity: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    /// Linear mix towards another colour, extrapolating past either end like d3 does.
    func mixed(with other: RTSWColor, _ t: Double) -> RTSWColor {
        RTSWColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t,
            opacity: opacity + (other.opacity - opacity) * t
        )
    }

    var color: Color {
        Color(
            .sRGB,
            red: min(max(red, 0), 255) / 255,
            green: min(max(green, 0), 255) / 255,
            blue: min(max(blue, 0), 255) / 255,
            opacity: min(max(opacity, 0), 1)
        )
    }
}

/// The website theme's colours, as the stackplot uses them.
enum RTSWPalette {
    static let red = RTSWColor(0xFF0000)
    static let blue400 = RTSWColor(0x48BCFF)
    static let blue700 = RTSWColor(0x0066FF)
    static let magenta = RTSWColor(0xFF00F5)
    static let yellow = RTSWColor(0xFFD602)
    static let orange = RTSWColor(0xFF6E00)
    static let primary300 = RTSWColor(0x59FF88)
    static let primary600 = RTSWColor(0x01B836)
    static let menu400 = RTSWColor(0xFFFFFF, opacity: 0.4)

    static let grey400 = RTSWColor(0xABABAB).color
    static let textGrey200 = RTSWColor(0xD1D1D1).color
    static let textGrey300 = RTSWColor(0xB0B0B0).color
    static let textGrey400 = RTSWColor(0x858585).color
    /// Grid lines.
    static let border = Color.white.opacity(0.2)
    /// Points of the satellites that are not the one chosen.
    static let inactive = Color.white.opacity(0.12)
    /// Phi's sector backgrounds, above and below the boundary.
    static let towards = RTSWColor(0x0C202B).color
    static let away = RTSWColor(0x2B002A).color
    /// Backgrounds behind samples NOAA flags as suspect or as errors.
    static let suspect = yellow.color.opacity(0.05)
    static let error = red.color.opacity(0.1)

    /// Phi is coloured by its own value: magenta pointing away from the Sun, blue towards it.
    static func phi(_ value: Double) -> Color {
        let mixed = value <= 225
            ? magenta.mixed(with: menu400, (value - 45) / 180)
            : menu400.mixed(with: blue400, (value - 225) / 180)
        return mixed.color
    }

    /// The IMF background's green, deepening with the field's strength up to 25 nT.
    static func imfBackground(_ value: Double) -> RTSWColor {
        RTSWColor(0x000000).mixed(with: primary600, value / 25)
    }

    static func satellite(_ source: Int) -> Color {
        switch source {
        case RTSWSourceCode.ace: return primary600.color
        case RTSWSourceCode.dscovr: return blue700.color
        case RTSWSourceCode.stereo: return orange.color
        case RTSWSourceCode.solar1: return magenta.color
        default: return red.color
        }
    }

    static func satelliteName(_ source: Int) -> String {
        switch source {
        case RTSWSourceCode.ace: return "ACE"
        case RTSWSourceCode.dscovr: return "DSCOVR"
        case RTSWSourceCode.stereo: return "STEREO"
        case RTSWSourceCode.solar1: return "SOLAR 1"
        default: return "IMAP"
        }
    }
}

extension RTSWKey {
    var name: String {
        switch self {
        case .bt: return "Bt"
        case .by: return "By"
        case .bz: return "Bz"
        case .phi: return String(localized: "Phi")
        case .theta: return String(localized: "Theta")
        case .speed: return String(localized: "Speed")
        case .density: return String(localized: "Density")
        }
    }

    var unit: String {
        switch self {
        case .bt, .by, .bz: return "nT"
        case .phi, .theta: return "deg"
        case .speed: return "km/s"
        case .density: return "1/cm3"
        }
    }

    /// Unit under a reading, written as in the small and medium widgets.
    var readingUnit: String {
        switch self {
        case .density: return "(p/cm³)"
        default: return "(\(unit))"
        }
    }

    /// Decimals of a reading, as in the medium widget.
    var valueFormat: String {
        switch self {
        case .phi, .theta, .speed: return "%.0f"
        default: return "%.1f"
        }
    }

    var trendFormat: String {
        switch self {
        case .phi, .theta, .speed: return "%+.0f"
        default: return "%+.1f"
        }
    }

    /// Colour of the component's points; Phi's depends on the value.
    func color(_ value: Double = 0) -> Color {
        switch self {
        case .bt: return .white
        case .by: return RTSWPalette.blue400.color
        case .bz: return RTSWPalette.red.color
        case .phi: return RTSWPalette.phi(value)
        case .theta: return RTSWColor(0xFF2181).color
        case .speed: return RTSWPalette.yellow.color
        case .density: return RTSWPalette.orange.color
        }
    }
}

// MARK: - Model

/// The optional components the widget is configured to draw.
struct RTSWComponents {
    var by = false
    var bz = true
    var phi = true
    var theta = false
}

struct RTSWLabel {
    /// Normalised position along the axis.
    let position: Double
    let text: String
}

/// Points of one colour.
struct RTSWDots {
    let color: Color
    let points: [CGPoint]
}

/// The latest value of a component and how it changed over the window, as the small widget shows it.
struct RTSWReading {
    let name: String
    let color: Color
    let value: String
    /// Change from the first to the last value of the window, nil without data.
    let trend: Double?
    let trendText: String
    let unit: String
}

struct RTSWPanel {
    /// Latest values written left of the panel.
    let readings: [RTSWReading]
    /// Share of the height the panel takes; the field's is a little taller, as on the website.
    let weight: CGFloat
    let gridLines: [Double]
    let axisLabels: [RTSWLabel]
    let zeroLine: Double?
    /// Dashed line at 10 p/cm³, which often marks a compression arriving.
    let tenLine: Double?
    /// Background deepening to green with the field's strength, for the IMF.
    let background: [Gradient.Stop]?
    /// Phi's sector: where the panel splits, and the stretches spent on either side of it.
    let sector: (split: Double, towards: [ClosedRange<Double>], away: [ClosedRange<Double>])?
    let suspectRuns: [ClosedRange<Double>]
    let errorRuns: [ClosedRange<Double>]
    /// The other satellites' grey points first, then the chosen one's in colour.
    let dots: [RTSWDots]
}

/// A stretch of the window fed by one satellite, for the bar under the plots.
struct RTSWSegment {
    let range: ClosedRange<Double>
    let color: Color
}

struct RTSWLegendItem {
    let name: String
    let color: Color
    /// Whether the satellite's points are drawn in colour, or only in grey behind them.
    let active: Bool
}

struct RTSWStack {
    let panels: [RTSWPanel]
    /// Stretch of the window the wind now reaching Earth was measured in. Hidden for STEREO.
    let earthZone: ClosedRange<Double>?
    /// Seconds the wind measured last takes to cover the 1.5 million km to Earth.
    let travelTime: TimeInterval?
    let timeLabels: [RTSWLabel]
    let segments: [RTSWSegment]
    let legend: [RTSWLegendItem]
    /// Whether the chosen satellite had anything to draw.
    let hasData: Bool
}

// MARK: - Building

/// Distance from L1 to Earth, in km.
private let l1Distance = 1_500_000.0
/// How far either side of the calculated arrival the wind might really land, as a share of the travel time.
private let travelTimeUncertainty = 0.15

private enum PanelKind {
    case imf, phi, theta, speed, density
}

private extension DateInterval {
    /// Where a date falls in the interval, from 0 at its start to 1 at its end.
    func fraction(of date: Date) -> Double {
        date.timeIntervalSince(start) / duration
    }
}

extension RTSWStack {
    /// - Parameters:
    ///   - window: The stretch of time drawn, ending now.
    ///   - resolution: Spacing of the samples, in seconds.
    ///   - plotWidth: Width the plots will be drawn at, which the points are thinned to.
    init(data: RTSWData, satellite: RTSWSatellite, components: RTSWComponents,
         window: DateInterval, resolution: TimeInterval, plotWidth: Double) {
        let mag = data.mag.filter { window.contains($0.date) }
        let plasma = data.plasma.filter { window.contains($0.date) }
        let x = window.fraction(of:)

        let activeSource = data.mag.last(where: \.active)?.source
        let isMagActive = Self.activeTest(for: satellite, in: mag, activeSource: activeSource)
        let isPlasmaActive = Self.activeTest(for: satellite, in: plasma, activeSource: activeSource)

        // Timed off the latest speed of the active satellite, as the website does whichever one is shown
        let isAutoActive = Self.activeTest(for: .auto, in: plasma, activeSource: activeSource)
        let latest = plasma.last(where: { isAutoActive($0) && $0.speed > 0 })
            ?? plasma.last(where: { isPlasmaActive($0) && $0.speed > 0 })
        if let latest {
            let travelTime = l1Distance / latest.speed
            let earthHit = latest.date.addingTimeInterval(-travelTime)
            let spread = travelTime * travelTimeUncertainty
            self.travelTime = travelTime
            earthZone = satellite == .stereo
                ? nil
                : x(earthHit.addingTimeInterval(-spread))...x(earthHit.addingTimeInterval(spread))
        } else {
            travelTime = nil
            earthZone = nil
        }

        var panels = [
            Self.panel(.imf, keys: [.bt] + (components.bz ? [.bz] : []) + (components.by ? [.by] : []),
                       points: mag, isActive: isMagActive, window: window, resolution: resolution, plotWidth: plotWidth)
        ]
        if components.phi {
            panels.append(Self.panel(.phi, keys: [.phi], points: mag, isActive: isMagActive,
                                     window: window, resolution: resolution, plotWidth: plotWidth))
        }
        if components.theta {
            panels.append(Self.panel(.theta, keys: [.theta], points: mag, isActive: isMagActive,
                                     window: window, resolution: resolution, plotWidth: plotWidth))
        }
        panels.append(Self.panel(.speed, keys: [.speed], points: plasma, isActive: isPlasmaActive,
                                 window: window, resolution: resolution, plotWidth: plotWidth))
        panels.append(Self.panel(.density, keys: [.density], points: plasma, isActive: isPlasmaActive,
                                 window: window, resolution: resolution, plotWidth: plotWidth))
        self.panels = panels

        // Which satellite fed the points drawn in colour, stretch by stretch
        var feeds: [(source: Int, start: Date, end: Date)] = []
        for point in mag where isMagActive(point) && point.bt.isFinite {
            if let last = feeds.last, last.source == point.source,
               point.date.timeIntervalSince(last.end) <= resolution * 1.5 {
                feeds[feeds.count - 1].end = point.date
            } else {
                feeds.append((point.source, point.date, point.date))
            }
        }
        segments = feeds.map { RTSWSegment(range: x($0.start)...x($0.end), color: RTSWPalette.satellite($0.source)) }

        // Named in the order they appear, followed by the satellites only seen in grey
        var legend: [RTSWLegendItem] = []
        var listed = Set<Int>()
        for feed in feeds where listed.insert(feed.source).inserted {
            legend.append(RTSWLegendItem(name: RTSWPalette.satelliteName(feed.source),
                                         color: RTSWPalette.satellite(feed.source), active: true))
        }
        let greySources = mag.filter { !isMagActive($0) && $0.bt.isFinite }.map(\.source)
            + plasma.filter { !isPlasmaActive($0) && $0.speed.isFinite }.map(\.source)
        for source in greySources where listed.insert(source).inserted {
            legend.append(RTSWLegendItem(name: RTSWPalette.satelliteName(source),
                                         color: Color.white.opacity(0.35), active: false))
        }
        self.legend = legend

        let calendar = Calendar.current
        timeLabels = RTSWTimeTicks.labels(for: RTSWTimeTicks.ticks(in: window, count: 4, calendar: calendar),
                                          in: window, plotWidth: plotWidth)

        hasData = mag.contains(where: isMagActive) || plasma.contains(where: isPlasmaActive)
    }

    /// Which points are drawn in colour: every point of a chosen satellite; in auto, those NOAA tagged
    /// as active plus the newest samples of the active satellite, which `active-mag` trails by a few minutes.
    private static func activeTest<T: RTSWSample>(for satellite: RTSWSatellite, in points: [T],
                                                   activeSource: Int?) -> (T) -> Bool {
        if let code = satellite.sourceCode { return { $0.source == code } }
        guard let activeSource else { return { $0.active } }
        let lastTagged = points.last(where: \.active)?.date ?? .distantPast
        return { $0.active || ($0.source == activeSource && $0.date > lastTagged) }
    }

    private static func panel<T: RTSWSample>(_ kind: PanelKind, keys: [RTSWKey], points: [T],
                                             isActive: (T) -> Bool, window: DateInterval,
                                             resolution: TimeInterval, plotWidth: Double) -> RTSWPanel {
        let active = points.filter(isActive)
        let inactive = points.filter { !isActive($0) }
        let scale = RTSWScale(kind: kind, keys: keys, points: active)
        let x = window.fraction(of:)

        // Axis values: Phi's two, three nice ones, or the decades of a logarithmic axis
        let gridValues: [Double]
        let labels: [RTSWLabel]
        switch kind {
        case .phi:
            gridValues = [135, 315]
            labels = gridValues.compactMap { value in scale.position(value).map { RTSWLabel(position: $0, text: "\(Int(value))") } }
        case .density:
            gridValues = D3.logTicks(scale.lower, scale.upper, count: 2)
            labels = D3.logTicks(scale.lower, scale.upper, count: 4).filter(D3.isPowerOfTen).compactMap { value in
                scale.position(value).map { RTSWLabel(position: $0, text: value >= 1 ? "\(Int(value.rounded()))" : "\(value)") }
            }
        default:
            gridValues = D3.ticks(scale.lower, scale.upper, count: 3)
            let precision = D3.precision(D3.tickStep(scale.lower, scale.upper, count: 10))
            labels = gridValues.compactMap { value in
                scale.position(value).map { RTSWLabel(position: $0, text: D3.format(value, precision: precision)) }
            }
        }

        // Points, thinned to the plot's width. Phi below 45° is drawn above 360° so the sector boundary
        // sits in the middle, and coloured by value in ten-degree bins of one colour each
        var dots: [RTSWDots] = []
        for (group, colored) in [(inactive, false), (active, true)] {
            for key in keys {
                let samples = group.compactMap { point -> (date: Date, value: Double)? in
                    var value = point.value(key)
                    guard value.isFinite else { return nil }
                    if key == .phi && value < 45 { value += 360 }
                    return (point.date, value)
                }
                let positioned = decimate(samples, window: window, width: plotWidth).compactMap { sample -> (CGPoint, Double)? in
                    scale.position(sample.value).map { (CGPoint(x: x(sample.date), y: $0), sample.value) }
                }
                if !colored {
                    dots.append(RTSWDots(color: RTSWPalette.inactive, points: positioned.map(\.0)))
                } else if key == .phi {
                    let bins = Dictionary(grouping: positioned) { Int((($0.1 - 45) / 10).rounded(.down)) }
                    for (bin, members) in bins.sorted(by: { $0.key < $1.key }) {
                        dots.append(RTSWDots(color: key.color(45 + (Double(bin) + 0.5) * 10), points: members.map(\.0)))
                    }
                } else {
                    dots.append(RTSWDots(color: key.color(), points: positioned.map(\.0)))
                }
            }
        }

        let background: [Gradient.Stop]?
        if kind == .imf {
            background = Self.imfGradient(top: RTSWPalette.imfBackground(abs(scale.upper)),
                                          bottom: RTSWPalette.imfBackground(abs(scale.lower)))
        } else {
            background = nil
        }

        let sector: (split: Double, towards: [ClosedRange<Double>], away: [ClosedRange<Double>])?
        if kind == .phi, let split = scale.position(225) {
            sector = (
                split,
                runs(active, where: { $0.value(.phi) > 225 || $0.value(.phi) < 45 }, window: window, resolution: resolution),
                runs(active, where: { $0.value(.phi) < 225 && $0.value(.phi) >= 45 }, window: window, resolution: resolution)
            )
        } else {
            sector = nil
        }

        let readings = keys.map { key -> RTSWReading in
            let first = active.first { $0.value(key).isFinite }?.value(key)
            let last = active.last { $0.value(key).isFinite }?.value(key)
            let trend = last.flatMap { last in first.map { last - $0 } }
            return RTSWReading(
                name: key.name,
                color: key.color(),
                value: last.map { String(format: key.valueFormat, $0) } ?? "–",
                trend: trend,
                trendText: trend.map { String(format: key.trendFormat, $0) } ?? "",
                unit: key.readingUnit
            )
        }
        return RTSWPanel(
            readings: readings,
            weight: kind == .imf ? 1.1 : 1,
            gridLines: gridValues.compactMap(scale.position),
            axisLabels: labels,
            zeroLine: kind == .imf || kind == .theta ? scale.position(0) : kind == .phi ? scale.position(220) : nil,
            tenLine: kind == .density ? scale.position(10) : nil,
            background: background,
            sector: sector,
            suspectRuns: runs(active, where: { $0.quality == 1 }, window: window, resolution: resolution),
            errorRuns: runs(active, where: { $0.quality == 2 }, window: window, resolution: resolution),
            dots: dots
        )
    }

    /// Green at the edges fading to nothing at zero. The stops reproduce the SVG gradient's
    /// unpremultiplied fade, which darkens faster than a plain colour-to-clear one.
    private static func imfGradient(top: RTSWColor, bottom: RTSWColor) -> [Gradient.Stop] {
        let steps = [0.0, 0.25, 0.5, 0.75, 1.0]
        let black = RTSWColor(0x000000, opacity: 0)
        let upper = steps.map { t in Gradient.Stop(color: top.mixed(with: black, t).color, location: t / 2) }
        let lower = steps.reversed().map { t in Gradient.Stop(color: bottom.mixed(with: black, t).color, location: 1 - t / 2) }
        return upper + lower.dropFirst()
    }

    /// Stretches of consecutive points passing a test. Each point covers the step before it, as on the website.
    private static func runs<T: RTSWSample>(_ points: [T], where matches: (T) -> Bool,
                                            window: DateInterval, resolution: TimeInterval) -> [ClosedRange<Double>] {
        let x = window.fraction(of:)
        var runs: [ClosedRange<Double>] = []
        var current: (start: Date, end: Date)?
        for point in points {
            if matches(point), let run = current, point.date.timeIntervalSince(run.end) <= resolution * 1.5 {
                current = (run.start, point.date)
                continue
            }
            if let run = current { runs.append(x(run.start.addingTimeInterval(-resolution))...x(run.end)) }
            current = matches(point) ? (point.date, point.date) : nil
        }
        if let run = current { runs.append(x(run.start.addingTimeInterval(-resolution))...x(run.end)) }
        return runs
    }

    /// Keeps the lowest and the highest point of every column the plot is wide, so a two-minute
    /// southward turn of Bz survives being drawn a few hundred points wide (the website's `decimate`).
    private static func decimate(_ samples: [(date: Date, value: Double)], window: DateInterval,
                                 width: Double) -> [(date: Date, value: Double)] {
        let column = window.duration / max(width, 1)
        guard column > 0, Double(samples.count) >= width * 3 else { return samples }

        var thinned: [(date: Date, value: Double)] = []
        var index = Int.min
        var low: (date: Date, value: Double)?
        var high: (date: Date, value: Double)?
        func flush() {
            guard let low, let high else { return }
            if low.date == high.date { thinned.append(low) }
            else if low.date < high.date { thinned += [low, high] }
            else { thinned += [high, low] }
        }
        for sample in samples {
            let at = Int((sample.date.timeIntervalSince1970 / column).rounded(.down))
            if at != index {
                flush()
                index = at
                low = nil
                high = nil
            }
            if low == nil || sample.value < low!.value { low = sample }
            if high == nil || sample.value > high!.value { high = sample }
        }
        flush()
        return thinned
    }
}

// MARK: - Scales

/// A panel's value axis, as the website builds it.
private struct RTSWScale {
    let lower: Double
    let upper: Double
    let logarithmic: Bool

    /// The extent of the active points padded by a tenth (ignoring identified errors, and the negative
    /// speeds and densities only bad samples have), mirrored around zero for the field components,
    /// fixed for Phi, then rounded out to nice values.
    init<T: RTSWSample>(kind: PanelKind, keys: [RTSWKey], points: [T]) {
        var minimum = Double.infinity
        var maximum = -Double.infinity
        for point in points where point.quality != 2 {
            for key in keys {
                let value = point.value(key)
                guard value.isFinite, !((key == .speed || key == .density) && value < 0) else { continue }
                minimum = min(minimum, value)
                maximum = max(maximum, value)
            }
        }
        if !minimum.isFinite { (minimum, maximum) = (0, 1) }

        var lower = minimum - minimum * 0.1
        var upper = maximum + maximum * 0.1
        if kind == .imf || kind == .theta {
            upper = max(abs(minimum), abs(maximum))
            lower = -upper
        }
        logarithmic = kind == .density
        if logarithmic && lower <= 0 { lower = 0.1 }
        if kind == .phi { (lower, upper) = (45, 405) }

        if logarithmic {
            lower = pow(10, log10(lower).rounded(.down))
            upper = pow(10, log10(max(upper, lower)).rounded(.up))
            if upper <= lower { upper = lower * 10 }
        } else {
            (lower, upper) = D3.nice(lower, upper)
            if upper <= lower { (lower, upper) = (lower - 1, upper + 1) }
        }
        self.lower = lower
        self.upper = upper
    }

    /// Where a value sits, from 0 at the top of the panel to 1 at the bottom.
    func position(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        if logarithmic {
            guard value > 0 else { return nil }
            return 1 - (log10(value) - log10(lower)) / (log10(upper) - log10(lower))
        }
        return 1 - (value - lower) / (upper - lower)
    }
}

/// Ports of the d3 routines behind the website's axes, so the widget's land on the same values.
private enum D3 {
    private static let e10 = 50.0.squareRoot()
    private static let e5 = 10.0.squareRoot()
    private static let e2 = 2.0.squareRoot()

    /// JavaScript's Math.round, which rounds halves up rather than away from zero.
    private static func jsRound(_ value: Double) -> Double {
        (value + 0.5).rounded(.down)
    }

    private static func tickSpec(_ start: Double, _ stop: Double, _ count: Double) -> (i1: Double, i2: Double, inc: Double) {
        let step = (stop - start) / max(0, count)
        let power = log10(step).rounded(.down)
        let error = step / pow(10, power)
        let factor: Double = error >= e10 ? 10 : error >= e5 ? 5 : error >= e2 ? 2 : 1
        var i1: Double, i2: Double, inc: Double
        if power < 0 {
            inc = pow(10, -power) / factor
            i1 = jsRound(start * inc)
            i2 = jsRound(stop * inc)
            if i1 / inc < start { i1 += 1 }
            if i2 / inc > stop { i2 -= 1 }
            inc = -inc
        } else {
            inc = pow(10, power) * factor
            i1 = jsRound(start / inc)
            i2 = jsRound(stop / inc)
            if i1 * inc < start { i1 += 1 }
            if i2 * inc > stop { i2 -= 1 }
        }
        if i2 < i1 && 0.5 <= count && count < 2 { return tickSpec(start, stop, count * 2) }
        return (i1, i2, inc)
    }

    /// d3.ticks
    static func ticks(_ start: Double, _ stop: Double, count: Double) -> [Double] {
        guard count > 0, start.isFinite, stop.isFinite, start <= stop else { return [] }
        if start == stop { return [start] }
        let (i1, i2, inc) = tickSpec(start, stop, count)
        guard i2 >= i1, inc.isFinite, inc != 0 else { return [] }
        return (0...Int(i2 - i1)).map { i in
            inc < 0 ? (i1 + Double(i)) / -inc : (i1 + Double(i)) * inc
        }
    }

    /// d3.tickStep
    static func tickStep(_ start: Double, _ stop: Double, count: Double) -> Double {
        let inc = tickSpec(start, stop, count).inc
        return inc < 0 ? 1 / -inc : inc
    }

    /// d3's linear `scale.nice()`, which extends a domain to round values.
    static func nice(_ lower: Double, _ upper: Double, count: Double = 10) -> (Double, Double) {
        var start = lower
        var stop = upper
        var previous: Double?
        for _ in 0..<10 {
            let step = tickSpec(start, stop, count).inc
            if step == previous { return (start, stop) }
            if step > 0 {
                start = (start / step).rounded(.down) * step
                stop = (stop / step).rounded(.up) * step
            } else if step < 0 {
                start = (start * step).rounded(.up) / step
                stop = (stop * step).rounded(.down) / step
            } else {
                break
            }
            previous = step
        }
        return (lower, upper)
    }

    /// d3's logarithmic `scale.ticks()`: every 1-9 × 10ⁿ when there are few decades, else whole decades.
    static func logTicks(_ lower: Double, _ upper: Double, count: Double) -> [Double] {
        guard lower > 0, upper > lower else { return [] }
        let i = log10(lower)
        let j = log10(upper)
        guard j - i < count else {
            return ticks(i, j, count: min(j - i, count)).map { pow(10, $0) }
        }
        var values: [Double] = []
        var exponent = i.rounded(.down)
        while exponent <= j.rounded(.up) {
            for k in 1..<10 {
                let value = exponent < 0 ? Double(k) / pow(10, -exponent) : Double(k) * pow(10, exponent)
                if value < lower { continue }
                if value > upper { break }
                values.append(value)
            }
            exponent += 1
        }
        return Double(values.count) * 2 < count ? ticks(lower, upper, count: count) : values
    }

    /// The website labels a logarithmic axis on its decades only.
    static func isPowerOfTen(_ value: Double) -> Bool {
        let exponent = log10(value)
        return abs(exponent - exponent.rounded()) < 1e-9
    }

    /// Decimals d3 gives axis labels for ticks this far apart.
    static func precision(_ step: Double) -> Int {
        max(0, -Int(log10(abs(step)).rounded(.down)))
    }

    /// d3-format's ",.Nf": grouped thousands and a typographic minus sign.
    static func format(_ value: Double, precision: Int) -> String {
        let text = String(format: "%.\(precision)f", abs(value))
        let parts = text.split(separator: ".", maxSplits: 1)
        var integer = String(parts[0])
        var index = integer.count - 3
        while index > 0 {
            integer.insert(",", at: integer.index(integer.startIndex, offsetBy: index))
            index -= 3
        }
        let grouped = parts.count > 1 ? "\(integer).\(parts[1])" : integer
        let isZero = Double(text) == 0
        return (value < 0 && !isZero ? "\u{2212}" : "") + grouped
    }
}

/// d3's time ticks and the website's axis formats, in local time.
private enum RTSWTimeTicks {
    private static let minute: TimeInterval = 60
    private static let hour = 60 * minute
    private static let day = 24 * hour
    private static let year = 365 * day

    private static let intervals: [(unit: Calendar.Component, step: Int, duration: TimeInterval)] = [
        (.minute, 1, minute), (.minute, 5, 5 * minute), (.minute, 15, 15 * minute), (.minute, 30, 30 * minute),
        (.hour, 1, hour), (.hour, 3, 3 * hour), (.hour, 6, 6 * hour), (.hour, 12, 12 * hour),
        (.day, 1, day), (.day, 2, 2 * day), (.weekOfYear, 1, 7 * day),
        (.month, 1, 30 * day), (.month, 3, 90 * day), (.year, 1, year)
    ]

    /// Round dates across the window, about `count` of them: the interval nearest to an even split,
    /// aligned on the local calendar (6 h ticks fall at midnight, 6 am, noon and 6 pm).
    static func ticks(in window: DateInterval, count: Int, calendar: Calendar) -> [Date] {
        var calendar = calendar
        calendar.firstWeekday = 1 // d3's weeks start on Sunday

        let target = window.duration / Double(count)
        let index = intervals.firstIndex { $0.duration > target } ?? intervals.count
        let unit: Calendar.Component
        let step: Int
        if index == intervals.count {
            unit = .year
            step = max(1, Int(D3.tickStep(window.start.timeIntervalSince1970 / year,
                                          window.end.timeIntervalSince1970 / year, count: Double(count))))
        } else if index == 0 {
            (unit, step) = (.minute, 1)
        } else {
            let below = intervals[index - 1]
            let above = intervals[index]
            (unit, step) = target / below.duration < above.duration / target
                ? (below.unit, below.step)
                : (above.unit, above.step)
        }

        guard let first = calendar.dateInterval(of: unit, for: window.start)?.start else { return [] }
        var ticks: [Date] = []
        var date = first
        while date <= window.end {
            if date >= window.start && isRound(date, unit: unit, step: step, calendar: calendar) {
                ticks.append(date)
            }
            guard let next = calendar.date(byAdding: unit, value: 1, to: date) else { break }
            date = next
        }
        return ticks
    }

    /// Whether a date starting a unit is one d3's `interval.every(step)` keeps.
    private static func isRound(_ date: Date, unit: Calendar.Component, step: Int, calendar: Calendar) -> Bool {
        switch unit {
        case .minute: return calendar.component(.minute, from: date) % step == 0
        case .hour: return calendar.component(.hour, from: date) % step == 0
        case .day: return (calendar.component(.day, from: date) - 1) % step == 0
        case .month: return (calendar.component(.month, from: date) - 1) % step == 0
        case .year: return calendar.component(.year, from: date) % step == 0
        default: return true
        }
    }

    /// Labels for the bottom ticks, in the website's format for the window's length, leaving out any
    /// that would run into the one before or off the edge of the widget.
    static func labels(for ticks: [Date], in window: DateInterval, plotWidth: Double) -> [RTSWLabel] {
        let formatter = DateFormatter()
        if window.duration <= day {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else if window.duration <= 54 * day {
            formatter.setLocalizedDateFormatFromTemplate("EEEd")
        } else if window.duration <= 5 * year {
            formatter.setLocalizedDateFormatFromTemplate("MMMy")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("y")
        }

        var labels: [RTSWLabel] = []
        var lastEnd = -Double.infinity
        for tick in ticks {
            let text = formatter.string(from: tick)
            let position = window.fraction(of: tick)
            let center = position * plotWidth
            let halfWidth = Double(text.count) * 2.1 + 1 // ~4.2 pt a character at 7 pt
            // The plots have the axis columns to their left but only a few points to their right
            guard center - halfWidth >= max(lastEnd + 3, -40), center + halfWidth <= plotWidth + 10 else { continue }
            labels.append(RTSWLabel(position: position, text: text))
            lastEnd = center + halfWidth
        }
        return labels
    }
}

/// How date-fns words the travel time on the website ("44 minutes", "about 1 hour").
func rtswDistance(_ seconds: TimeInterval) -> String {
    let minutes = Int((seconds / 60).rounded())
    if minutes < 1 { return String(localized: "less than a minute") }
    if minutes < 45 { return String(localized: "\(minutes) minutes") }
    if minutes < 90 { return String(localized: "about 1 hour") }
    return String(localized: "about \(Int((Double(minutes) / 60).rounded())) hours")
}
