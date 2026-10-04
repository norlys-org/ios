//
//  RTSWStackView.swift
//  norlysWidget
//
//  Draws the solar wind stackplot prepared by RTSWStack, laid out like the mobile
//  version of norlys.live/rtsw: a title with the live badge and its countdown, the
//  panels with their latest values on the left as in the small widget, the time
//  axis and, under it, the satellite each coloured point came from.
//

import SwiftUI

// MARK: - Layout

/// Where everything sits in the widget, in points.
enum RTSWStackLayout {
    static let leading: CGFloat = 8
    static let trailing: CGFloat = 12
    static let top: CGFloat = 9
    static let bottom: CGFloat = 8
    /// Column of the latest values, as in the small widget.
    static let readingColumn: CGFloat = 72
    /// Column of axis values, right-aligned against the plots.
    static let valueColumn: CGFloat = 18
    static let titleRow: CGFloat = 12
    /// The title sits further in than the plots, clear of the widget's rounded corner.
    static let titleInset: CGFloat = 16
    /// Row holding "Forecast" over the arrival band.
    static let forecastRow: CGFloat = 9
    static let panelSpacing: CGFloat = 5
    static let timeRow: CGFloat = 11
    static let satelliteBar: CGFloat = 3
    static let footerRow: CGFloat = 10

    /// Left edge of the plots.
    static let plotX = leading + readingColumn + valueColumn

    /// Width of the plots in a widget this wide; the timeline provider thins the data to it.
    static func plotWidth(forWidgetWidth width: CGFloat) -> CGFloat {
        max(width - plotX - trailing, 1)
    }

    /// The panels' frames, the height between the header and the time axis shared out by weight.
    static func panelFrames(for panels: [RTSWPanel], in size: CGSize) -> [CGRect] {
        let firstY = top + titleRow + forecastRow + 2
        let lastY = size.height - bottom - footerRow - 3 - satelliteBar - 2 - timeRow
        let spacing = panelSpacing * CGFloat(max(panels.count - 1, 0))
        let totalWeight = panels.reduce(0) { $0 + $1.weight }
        let width = plotWidth(forWidgetWidth: size.width)

        var y = firstY
        return panels.map { panel in
            let height = (lastY - firstY - spacing) * panel.weight / totalWeight
            defer { y += height + panelSpacing }
            return CGRect(x: plotX, y: y, width: width, height: height)
        }
    }
}

private extension Font {
    static func helvetica(_ size: CGFloat) -> Font {
        .custom("Helvetica", size: size)
    }
}

// MARK: - Stack View

/// What the live badge says about the data's freshness.
enum RTSWUpdateStatus {
    /// Counting down from the fetch to the reload the timeline asked for.
    case updatesIn(ClosedRange<Date>)
    /// The reload is overdue (WidgetKit spaces them out), so how long ago the data was fetched.
    case updated(Date)
}

struct RTSWStackView: View {
    let stack: RTSWStack
    /// What the widget shows, e.g. "Solar Wind", followed by the period in grey.
    let title: String
    let period: String
    let status: RTSWUpdateStatus
    /// Written across the plots when the satellite's data does not describe the wind heading for Earth.
    let watermark: String?
    let size: CGSize

    var body: some View {
        let frames = RTSWStackLayout.panelFrames(for: stack.panels, in: size)
        let plotX = RTSWStackLayout.plotX
        let plotWidth = RTSWStackLayout.plotWidth(forWidgetWidth: size.width)
        let plotsBottom = frames.last?.maxY ?? 0
        let barY = plotsBottom + RTSWStackLayout.timeRow + 2

        ZStack(alignment: .topLeading) {
            header
            forecastLabel(plotWidth: plotWidth)

            ForEach(Array(stack.panels.enumerated()), id: \.offset) { index, panel in
                readings(of: panel, in: frames[index])
                values(of: panel, in: frames[index])
                RTSWPanelView(panel: panel, stack: stack, size: frames[index].size)
                    .offset(x: frames[index].minX, y: frames[index].minY)
            }

            ForEach(Array(stack.timeLabels.enumerated()), id: \.offset) { _, label in
                Text(label.text)
                    .font(.helvetica(7))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .fixedSize()
                    .position(x: plotX + label.position * plotWidth, y: plotsBottom + RTSWStackLayout.timeRow / 2 + 1)
            }

            satelliteBar(width: plotWidth)
                .offset(x: plotX, y: barY)

            footer(width: plotWidth)
                .offset(x: plotX, y: barY + RTSWStackLayout.satelliteBar + 3)

            if let watermark, let first = frames.first, let last = frames.last {
                Text(watermark)
                    .font(.helvetica(64))
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.1))
                    .fixedSize()
                    .rotationEffect(.degrees(30))
                    .position(x: first.midX, y: (first.minY + last.maxY) / 2)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// The title, like the Lys widget's, and the live badge with the wait until the next update.
    private var header: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(title)
                .font(.helvetica(10))
                .fontWeight(.bold)
                .foregroundColor(.white)
            Text(verbatim: "(\(period))")
                .font(.helvetica(8))
                .fontWeight(.bold)
                .foregroundColor(.gray)

            Spacer(minLength: 4)

            // Both kept current by the system between timeline reloads
            Group {
                switch status {
                case .updatesIn(let interval):
                    HStack(spacing: 2) {
                        Text("Updates in")
                        // Timers reserve more room than they need: sized to "4:59" or "14:59"
                        Text(timerInterval: interval, countsDown: true)
                            .monospacedDigit()
                            .multilineTextAlignment(.leading)
                            .frame(width: interval.upperBound.timeIntervalSince(interval.lowerBound) < 600 ? 19 : 24,
                                   alignment: .leading)
                    }
                case .updated(let date):
                    Text("Updated \(date, style: .relative) ago")
                        .multilineTextAlignment(.trailing)
                        .fixedSize()
                }
            }
            .font(.helvetica(7.5))
            .fontWeight(.bold)
            .foregroundColor(RTSWPalette.textGrey300)

            Text("LIVE")
                .font(.helvetica(5.5))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 2.5)
                .padding(.vertical, 1.5)
                .background(RTSWPalette.red.color)
        }
        .frame(width: size.width - RTSWStackLayout.titleInset - RTSWStackLayout.trailing,
               height: RTSWStackLayout.titleRow)
        .offset(x: RTSWStackLayout.titleInset, y: RTSWStackLayout.top)
    }

    /// "Forecast" over the band the wind now reaching Earth was measured in, held inside the plot.
    @ViewBuilder
    private func forecastLabel(plotWidth: CGFloat) -> some View {
        if let zone = stack.earthZone {
            let width: CGFloat = 34
            let center = (zone.lowerBound + zone.upperBound) / 2 * plotWidth
            let left = min(max(center - width / 2, 0), plotWidth - width)
            Text("Forecast")
                .font(.helvetica(7))
                .fontWeight(.bold)
                .foregroundColor(.gray)
                .fixedSize()
                .frame(width: width, height: RTSWStackLayout.forecastRow)
                .offset(x: RTSWStackLayout.plotX + left, y: RTSWStackLayout.top + RTSWStackLayout.titleRow)
        }
    }

    /// The panel's latest values and their change over the window, laid out like the small widget's,
    /// shrunk to share the panel's height when it carries several components.
    private func readings(of panel: RTSWPanel, in frame: CGRect) -> some View {
        let count = CGFloat(max(panel.readings.count, 1))
        let valueSize = min(26, (frame.height / count - 9) * 0.95)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(panel.readings.enumerated()), id: \.offset) { _, reading in
                VStack(alignment: .leading, spacing: -3) {
                    Text(reading.name)
                        .font(.helvetica(min(10, max(7, valueSize * 0.4))))
                        .fontWeight(.bold)
                        .foregroundColor(reading.color)

                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(reading.value)
                            .font(.helvetica(valueSize))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(reading.trendText)
                                .font(.helvetica(min(10, max(6, valueSize * 0.38))))
                                .fontWeight(.bold)
                                .foregroundColor((reading.trend ?? 0) >= 0 ? .green : .red)

                            Text(reading.unit)
                                .font(.helvetica(6))
                                .fontWeight(.bold)
                                .foregroundColor(.gray)
                        }
                        .fixedSize()
                    }
                }
                .frame(maxHeight: .infinity, alignment: .leading)
            }
        }
        .frame(width: RTSWStackLayout.readingColumn, height: frame.height, alignment: .leading)
        .offset(x: RTSWStackLayout.leading, y: frame.minY)
    }

    /// The panel's axis values.
    @ViewBuilder
    private func values(of panel: RTSWPanel, in frame: CGRect) -> some View {
        let plotX = RTSWStackLayout.plotX
        let labelWidth = RTSWStackLayout.valueColumn - 4
        // Held inside the panel, so values on the edges of neighbouring panels don't run into each other
        ForEach(Array(panel.axisLabels.enumerated()), id: \.offset) { _, label in
            Text(label.text)
                .font(.helvetica(7))
                .fontWeight(.bold)
                .foregroundColor(RTSWPalette.textGrey300)
                .fixedSize()
                .frame(width: labelWidth, alignment: .trailing)
                .position(x: plotX - 4 - labelWidth / 2,
                          y: frame.minY + min(max(label.position * frame.height, 4), frame.height - 4))
        }
    }

    /// Which satellite fed the coloured points, along the time axis.
    private func satelliteBar(width: CGFloat) -> some View {
        let height = RTSWStackLayout.satelliteBar
        let byColor = Dictionary(grouping: stack.segments, by: \.color)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(byColor.keys.enumerated()), id: \.offset) { _, color in
                Path { path in
                    for segment in byColor[color] ?? [] {
                        let start = segment.range.lowerBound * width
                        path.addRect(CGRect(x: start, y: 0,
                                            width: max(segment.range.upperBound * width - start, 1), height: height))
                    }
                }
                .fill(color)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    /// The satellites behind the points, and how long the wind takes to reach Earth.
    private func footer(width: CGFloat) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(stack.legend.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 2.5) {
                    if item.active {
                        Rectangle()
                            .fill(item.color)
                            .frame(width: 5, height: 5)
                    } else {
                        Circle()
                            .fill(item.color)
                            .frame(width: 4, height: 4)
                    }
                    Text(item.name)
                        .foregroundColor(item.active ? item.color : RTSWPalette.textGrey400)
                }
            }

            Spacer(minLength: 4)

            if let travelTime = stack.travelTime {
                let distance = Text(rtswDistance(travelTime)).foregroundColor(.white)
                ViewThatFits(in: .horizontal) {
                    Text("Travel time to earth: ").foregroundColor(RTSWPalette.textGrey300) + distance
                    Text("Travel time: ").foregroundColor(RTSWPalette.textGrey300) + distance
                    distance
                }
            }
        }
        .font(.helvetica(7))
        .fontWeight(.bold)
        .lineLimit(1)
        .frame(width: width, height: RTSWStackLayout.footerRow)
    }
}

// MARK: - Panel View

/// One panel of the stack: backgrounds, grid, arrival band and points, clipped to the plot.
private struct RTSWPanelView: View {
    let panel: RTSWPanel
    let stack: RTSWStack
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let background = panel.background {
                LinearGradient(stops: background, startPoint: .top, endPoint: .bottom)
            }
            if let sector = panel.sector {
                bands(sector.towards, from: 0, to: sector.split)
                    .fill(RTSWPalette.towards)
                bands(sector.away, from: sector.split, to: 1)
                    .fill(RTSWPalette.away)
            }
            bands(panel.suspectRuns, from: 0, to: 1)
                .fill(RTSWPalette.suspect)
            bands(panel.errorRuns, from: 0, to: 1)
                .fill(RTSWPalette.error)

            horizontalLines(panel.gridLines)
                .stroke(RTSWPalette.border, lineWidth: 0.5)
            if let zero = panel.zeroLine {
                horizontalLines([zero])
                    .stroke(RTSWPalette.grey400, lineWidth: 0.75)
            }
            if let ten = panel.tenLine {
                horizontalLines([ten])
                    .stroke(RTSWPalette.primary300.color, style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
            }

            // The stretch the wind now reaching Earth was measured in: a band rather than a line,
            // because the crossing is timed off one speed and the wind does not hold it the whole way
            if let zone = stack.earthZone {
                bands([zone], from: 0, to: 1)
                    .fill(Color.white.opacity(0.035))
                verticalLines([zone.lowerBound, zone.upperBound])
                    .stroke(RTSWPalette.grey400, style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
            }

            ForEach(Array(panel.dots.enumerated()), id: \.offset) { _, dots in
                Path { path in
                    for point in dots.points {
                        path.addEllipse(in: CGRect(x: point.x * size.width - 1, y: point.y * size.height - 1,
                                                   width: 2, height: 2))
                    }
                }
                .fill(dots.color)
            }

            sideLabels
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }

    /// Height of the side labels' line, which is their width once turned.
    private static let sideLabelLine: CGFloat = 7

    /// For Phi, which way the field points either side of the sector boundary.
    @ViewBuilder
    private var sideLabels: some View {
        if panel.sector != nil {
            // Each kept to its own half of the panel, shrinking when the panel is short
            let half = size.height / 2 - 4
            topDown(Text("Towards -").foregroundColor(RTSWPalette.blue400.color.opacity(0.7)), length: half)
            // Pinned by its start a little above the bottom, reading upwards
            Text("Away +")
                .font(.helvetica(5.5))
                .fontWeight(.bold)
                .foregroundColor(RTSWPalette.magenta.color.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: half, height: Self.sideLabelLine, alignment: .leading)
                .rotationEffect(.degrees(-90), anchor: .bottomLeading)
                .frame(height: size.height - 3, alignment: .bottomLeading)
                .offset(x: 3 + Self.sideLabelLine)
        }
    }

    /// Text reading bottom to top, its end pinned near the top-left corner, shrunk to fit `length`.
    private func topDown(_ text: Text, length: CGFloat) -> some View {
        text
            .font(.helvetica(5.5))
            .fontWeight(.bold)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: length, height: Self.sideLabelLine, alignment: .trailing)
            .rotationEffect(.degrees(-90), anchor: .topTrailing)
            .frame(width: 3, alignment: .topTrailing)
            .offset(y: 3)
    }

    /// Full-height (or partial-height) rectangles over stretches of the window.
    private func bands(_ ranges: [ClosedRange<Double>], from top: Double, to bottom: Double) -> Path {
        Path { path in
            for range in ranges {
                path.addRect(CGRect(x: range.lowerBound * size.width, y: top * size.height,
                                    width: (range.upperBound - range.lowerBound) * size.width,
                                    height: (bottom - top) * size.height))
            }
        }
    }

    private func horizontalLines(_ positions: [Double]) -> Path {
        Path { path in
            for y in positions {
                path.move(to: CGPoint(x: 0, y: y * size.height))
                path.addLine(to: CGPoint(x: size.width, y: y * size.height))
            }
        }
    }

    private func verticalLines(_ positions: [Double]) -> Path {
        Path { path in
            for x in positions {
                path.move(to: CGPoint(x: x * size.width, y: 0))
                path.addLine(to: CGPoint(x: x * size.width, y: size.height))
            }
        }
    }
}
