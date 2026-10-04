//
//  RTSWLargeWidget.swift
//  norlysWidget
//
//  Large widget displaying the real-time solar wind stackplot of norlys.live/rtsw:
//  IMF Bt/Bz (and By), Phi (and/or Theta), speed and density, with the satellite
//  each point came from underneath. The satellite, time period and optional
//  components are configurable.
//

import AppIntents
import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct RTSWLargeProvider: AppIntentTimelineProvider {
    typealias Entry = RTSWLargeEntry
    typealias Intent = SelectRTSWConfigurationIntent

    /// Provides a placeholder entry for widget previews.
    func placeholder(in context: Context) -> RTSWLargeEntry {
        createMockEntry(for: SelectRTSWConfigurationIntent(), in: context)
    }

    /// Provides a snapshot entry: sample data in the widget gallery, real data otherwise.
    func snapshot(for configuration: SelectRTSWConfigurationIntent, in context: Context) async -> RTSWLargeEntry {
        if context.isPreview {
            return createMockEntry(for: configuration, in: context)
        }
        return await createEntry(for: configuration, in: context)
    }

    /// Fetches real-time data and asks to be reloaded as often as WidgetKit allows for the chosen period.
    func timeline(for configuration: SelectRTSWConfigurationIntent, in context: Context) async -> Timeline<RTSWLargeEntry> {
        let entry = await createEntry(for: configuration, in: context)
        // WidgetKit reloads when its budget allows, which can be later than asked: from then on the
        // badge says how old the data is instead of counting down past zero
        let entries = entry.stack == nil ? [entry] : [entry, entry.overdue()]
        return Timeline(entries: entries, policy: .after(entry.nextUpdate))
    }

    /// Fetches the window ending now from the chosen satellite, together with the HAPI satellites
    /// drawn in grey behind it, and prepares the plots. Retries in five minutes when nothing came back.
    private func createEntry(for configuration: SelectRTSWConfigurationIntent, in context: Context) async -> RTSWLargeEntry {
        let currentDate = Date()
        let satellite = configuration.satellite
        let timespan = configuration.timespan.clamped(to: satellite.longestTimespan)
        let window = DateInterval(start: currentDate.addingTimeInterval(-timespan.duration), end: currentDate)

        do {
            let data: RTSWData
            switch satellite {
            case .imap:
                async let core = try? RTSWFetcher.fetchRTSW(from: window.start, to: window.end, cadence: timespan.cadence)
                let imap = try await RTSWFetcher.fetchIMAP(from: window.start, to: window.end)
                data = (await core ?? RTSWData()).merged(with: imap)
            case .stereo:
                async let core = try? RTSWFetcher.fetchRTSW(from: window.start, to: window.end, cadence: timespan.cadence)
                let stereo = try await RTSWFetcher.fetchSTEREO(from: window.start, to: window.end)
                data = (await core ?? RTSWData()).merged(with: stereo)
            default:
                data = try await RTSWFetcher.fetchRTSW(from: window.start, to: window.end, cadence: timespan.cadence)
            }

            let stack = RTSWStack(
                data: data,
                satellite: satellite,
                components: components(of: configuration),
                window: window,
                resolution: timespan.resolution,
                plotWidth: plotWidth(in: context)
            )
            if stack.hasData {
                return RTSWLargeEntry(
                    date: currentDate,
                    updatedAt: currentDate,
                    nextUpdate: currentDate.addingTimeInterval(timespan.reloadInterval),
                    satellite: satellite,
                    timespan: timespan,
                    stack: stack
                )
            }
            print("No RTSW data available for \(satellite.rawValue)")
            return RTSWLargeEntry(
                date: currentDate,
                updatedAt: currentDate,
                nextUpdate: currentDate.addingTimeInterval(300),
                satellite: satellite,
                timespan: timespan,
                stack: nil
            )
        } catch {
            print("Error fetching RTSW data: \(error)")
            return RTSWLargeEntry(
                date: currentDate,
                updatedAt: currentDate,
                nextUpdate: currentDate.addingTimeInterval(300),
                satellite: satellite,
                timespan: timespan,
                stack: nil,
                unreachable: true
            )
        }
    }

    /// Creates an entry from the bundled sample data, for previews and the widget gallery.
    private func createMockEntry(for configuration: SelectRTSWConfigurationIntent, in context: Context) -> RTSWLargeEntry {
        let currentDate = Date()
        let timespan = configuration.timespan.clamped(to: configuration.satellite.longestTimespan)
        let window = DateInterval(start: currentDate.addingTimeInterval(-timespan.duration), end: currentDate)
        return RTSWLargeEntry(
            date: currentDate,
            updatedAt: currentDate,
            nextUpdate: currentDate.addingTimeInterval(timespan.reloadInterval),
            satellite: configuration.satellite,
            timespan: timespan,
            stack: RTSWStack(
                data: Self.loadMockData(spreadOver: window),
                satellite: .auto,
                components: components(of: configuration),
                window: window,
                resolution: window.duration / 360,
                plotWidth: plotWidth(in: context)
            )
        )
    }

    private func components(of configuration: SelectRTSWConfigurationIntent) -> RTSWComponents {
        RTSWComponents(by: configuration.showBy, bz: configuration.showBz,
                       phi: configuration.showPhi, theta: configuration.showTheta)
    }

    /// Width the plots will be drawn at, which the data is thinned to. Falls back to a common
    /// large widget's width should the context not know its size.
    private func plotWidth(in context: Context) -> Double {
        RTSWStackLayout.plotWidth(forWidgetWidth: context.displaySize.width > 0 ? context.displaySize.width : 338)
    }

    /// The six hours of real one-minute measurements bundled with the widget, spread evenly over the
    /// window and attributed to SOLAR-1.
    static func loadMockData(spreadOver window: DateInterval) -> RTSWData {
        func rows(_ name: String) -> [[String]] {
            guard let path = Bundle.main.path(forResource: name, ofType: "json"),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let jsonArray = try? JSONDecoder().decode([[String]].self, from: data) else { return [] }
            return Array(jsonArray.dropFirst()) // Drop header row.
        }
        func date(_ index: Int, of count: Int) -> Date {
            window.start.addingTimeInterval(window.duration * Double(index) / Double(max(count - 1, 1)))
        }

        // [time_tag, bt, bx_gsm, by_gsm, bz_gsm, lat_gsm, lon_gsm, quality, source, active]
        let magRows = rows("mockMagData").filter { $0.count >= 10 }
        // [time_tag, speed, density, temperature, quality, source, active]
        let plasmaRows = rows("mockPlasmaData").filter { $0.count >= 7 }
        return RTSWData(
            mag: magRows.enumerated().map { index, row in
                RTSWMag(date: date(index, of: magRows.count), bt: Double(row[1]) ?? .nan, by: Double(row[3]) ?? .nan,
                        bz: Double(row[4]) ?? .nan, phi: Double(row[6]) ?? .nan, theta: Double(row[5]) ?? .nan,
                        quality: Int(row[7]) ?? 0, source: RTSWSourceCode.solar1, active: true)
            },
            plasma: plasmaRows.enumerated().map { index, row in
                RTSWPlasma(date: date(index, of: plasmaRows.count), speed: Double(row[1]) ?? .nan,
                           density: Double(row[2]) ?? .nan, quality: Int(row[4]) ?? 0,
                           source: RTSWSourceCode.solar1, active: true)
            }
        )
    }
}

// MARK: - Timeline Entry

struct RTSWLargeEntry: TimelineEntry {
    let date: Date
    /// When the data was fetched.
    let updatedAt: Date
    /// When the timeline asks to be reloaded, which the "Updates in" countdown runs to.
    let nextUpdate: Date
    let satellite: RTSWSatellite
    /// The period shown, which IMAP and STEREO cap at a day.
    let timespan: RTSWTimespan
    /// The plots to draw, nil when there is nothing to draw.
    let stack: RTSWStack?
    /// Whether there is nothing to draw because the feeds could not be reached, rather than
    /// because the satellite sent nothing over the period (DSCOVR has been decommissioned).
    var unreachable = false

    /// The same data, shown from the moment its reload is due until WidgetKit gets round to it.
    func overdue() -> RTSWLargeEntry {
        RTSWLargeEntry(date: nextUpdate, updatedAt: updatedAt, nextUpdate: nextUpdate, satellite: satellite,
                       timespan: timespan, stack: stack, unreachable: unreachable)
    }
}

// MARK: - Widget View

struct RTSWLargeWidgetEntryView: View {
    var entry: RTSWLargeEntry

    /// Why the plots are missing.
    private var emptyMessage: String {
        if entry.unreachable {
            return String(localized: "Unable to fetch solar wind data")
        }
        let timespan = String(localized: RTSWTimespan.caseDisplayRepresentations[entry.timespan]?.title ?? "")
        if entry.satellite == .auto {
            return String(localized: "No solar wind data over the last \(timespan)")
        }
        let satellite = String(localized: RTSWSatellite.caseDisplayRepresentations[entry.satellite]?.title ?? "")
        return String(localized: "No \(satellite) data over the last \(timespan)")
    }

    var body: some View {
        if let stack = entry.stack {
            GeometryReader { geometry in
                RTSWStackView(
                    stack: stack,
                    title: String(localized: "Solar Wind"),
                    period: String(localized: RTSWTimespan.caseDisplayRepresentations[entry.timespan]?.title ?? ""),
                    status: entry.date < entry.nextUpdate
                        ? .updatesIn(entry.updatedAt...entry.nextUpdate)
                        : .updated(entry.updatedAt),
                    watermark: entry.satellite == .stereo ? "STEREO" : nil,
                    size: geometry.size
                )
            }
            .background(Color.black)
        } else {
            // Error state view
            VStack(alignment: .center, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundColor(.orange)

                Text("No Data Available")
                    .font(.custom("Helvetica", size: 16))
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text(emptyMessage)
                    .font(.custom("Helvetica", size: 10))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
    }
}

// MARK: - Widget Configuration

struct RTSWLargeWidget: Widget {
    let kind: String = "RTSWLargeWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectRTSWConfigurationIntent.self,
            provider: RTSWLargeProvider()
        ) { entry in
            RTSWLargeWidgetEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Solar wind stackplot widget")
        .description("Displays the real-time solar wind like norlys.live: IMF Bt/Bz, Phi, speed and density, with a configurable satellite, time period and components.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Preview

#Preview("Large Widget", as: .systemLarge) {
    RTSWLargeWidget()
} timeline: {
    let currentDate = Date()
    let window = DateInterval(start: currentDate.addingTimeInterval(-RTSWTimespan.oneDay.duration), end: currentDate)
    let entry = RTSWLargeEntry(
        date: currentDate,
        updatedAt: currentDate,
        nextUpdate: currentDate.addingTimeInterval(RTSWTimespan.oneDay.reloadInterval),
        satellite: .auto,
        timespan: .oneDay,
        stack: RTSWStack(
            data: RTSWLargeProvider.loadMockData(spreadOver: window),
            satellite: .auto,
            components: RTSWComponents(),
            window: window,
            resolution: window.duration / 360,
            plotWidth: 280
        )
    )
    return [entry]
}
