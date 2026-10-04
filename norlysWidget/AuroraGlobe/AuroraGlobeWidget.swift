//
//  AuroraGlobeWidget.swift
//  norlysWidget
//
//  The globe of norlys.live in a small and a large widget: the model's ovals in the website's
//  colours, the terminator, the land outline with its lakes and rivers, the geographic and magnetic
//  graticules and the substorm rings, turned to face the reader, or either geomagnetic pole, and
//  marking where they are when they let norlys know. Titled like the other widgets, with the
//  website's live badge and the age of the model in the corner.
//

import CoreLocation
import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct AuroraGlobeEntry: TimelineEntry {
    let date: Date
    /// When the model drawn was computed, nil when it could not be fetched.
    let modelDate: Date?
    let scene: GlobeScene
}

// MARK: - Timeline Provider

struct AuroraGlobeProvider: AppIntentTimelineProvider {
    typealias Entry = AuroraGlobeEntry
    typealias Intent = SelectGlobeConfigurationIntent

    /// The model is computed every minute; the widget asks to follow it as closely as WidgetKit allows,
    /// the badge telling the model's age in between.
    static let reloadInterval: TimeInterval = 5 * 60

    func placeholder(in context: Context) -> AuroraGlobeEntry {
        Self.sampleEntry(centre: .location)
    }

    func snapshot(for configuration: SelectGlobeConfigurationIntent, in context: Context) async -> AuroraGlobeEntry {
        if context.isPreview {
            return Self.sampleEntry(centre: configuration.centre)
        }
        return await Self.liveEntry(centre: configuration.centre)
    }

    func timeline(for configuration: SelectGlobeConfigurationIntent, in context: Context) async -> Timeline<AuroraGlobeEntry> {
        let entry = await Self.liveEntry(centre: configuration.centre)
        return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(Self.reloadInterval)))
    }

    /// The latest model, the globe turned as configured. The reader's position is looked up whatever the
    /// centre, for the dot marking it.
    static func liveEntry(centre: GlobeCentre) async -> AuroraGlobeEntry {
        async let location = GlobeLocation.current()
        let frame = try? await AuroraModelFrame.fetchLatest()
        let user = await location
        let now = Date()
        return AuroraGlobeEntry(
            date: now,
            // A server clock running ahead would otherwise read as a model from the future
            modelDate: frame.map { min($0.timestamp, now) },
            // The terminator and the moon at the time of drawing, as the website draws its latest model
            scene: GlobeScene(frame: frame, date: now, centre: centre.point(userLocation: user), userLocation: user)
        )
    }

    /// A frame bundled with the widget, from an evening with a substorm, for the gallery and placeholders.
    static func sampleEntry(centre: GlobeCentre) -> AuroraGlobeEntry {
        let frame = Bundle.main.url(forResource: "GlobeSample", withExtension: "bin")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? AuroraModelFrame.decodeFrames($0).first }
        let now = Date()
        return AuroraGlobeEntry(
            date: now,
            modelDate: now.addingTimeInterval(-42),
            scene: GlobeScene(frame: frame, date: frame?.timestamp ?? now,
                              centre: centre.point(userLocation: nil), userLocation: nil)
        )
    }
}

// MARK: - Location

/// The reader's position, when they have let norlys use it and widgets may share it.
@MainActor
final class GlobeLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    static func current(timeout: Duration = .seconds(5)) async -> GeoPoint? {
        let location = await GlobeLocation().locate(timeout: timeout)
        return location.map { GeoPoint(lon: $0.coordinate.longitude, lat: $0.coordinate.latitude) }
    }

    private func locate(timeout: Duration) async -> CLLocation? {
        guard manager.isAuthorizedForWidgetUpdates else { return nil }
        // A fix from the last quarter of an hour is as good as a new one for a whole globe
        if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -15 * 60 { return recent }

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        let fresh = await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
            self.continuation = continuation
            manager.requestLocation()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish(nil)
            }
        }
        return fresh ?? manager.location
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.finish(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}

// MARK: - Layout

extension GlobeLayout {
    /// The globe under the header, as large as the room left allows.
    static func widget(size: CGSize, small: Bool) -> GlobeLayout {
        let header: CGFloat = small ? 24 : 30
        let height = size.height - header
        let radius = max(min(size.width, height) / 2 - (small ? 4 : 6), 1)
        // The website's globe on a phone has a radius of about 294 CSS pixels: 0.3 of the height it is
        // laid out in, zoomed 1.4 times onto the reader. The marks it sizes in pixels are drawn in that
        // proportion, never so small they could not be read
        let proportion = radius / 294
        return GlobeLayout(
            size: size,
            centre: CGPoint(x: size.width / 2, y: header + height / 2),
            radius: radius,
            markerScale: max(proportion, 0.35),
            lineScale: max(proportion, 0.5)
        )
    }
}

private extension Font {
    static func helvetica(_ size: CGFloat) -> Font {
        .custom("Helvetica", size: size)
    }
}

// MARK: - Widget View

struct AuroraGlobeEntryView: View {
    let entry: AuroraGlobeEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.displayScale) private var displayScale
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var small: Bool { family == .systemSmall }

    var body: some View {
        GeometryReader { geometry in
            let layout = GlobeLayout.widget(size: geometry.size, small: small)
            let scale = max(displayScale, 1)

            ZStack(alignment: .topLeading) {
                // On the website's black rather than the system's take on it, so the night side of the
                // globe stays as invisible against the page as it is there. Left out where the system
                // removes the widget's background
                if let globe = GlobeRenderer.render(entry.scene, layout: layout, pixelScale: scale, opaque: showsBackground) {
                    Image(decorative: globe, scale: scale)
                        .widgetAccentedRenderingMode(.fullColor)
                }

                // As the website says it over its globe
                if entry.modelDate == nil {
                    Text("Could not load data")
                        .textCase(.uppercase)
                        .font(.helvetica(small ? 10 : 16))
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 0xB0 / 255, green: 0xB0 / 255, blue: 0xB0 / 255).opacity(0.5))
                        .multilineTextAlignment(.center)
                        .frame(width: layout.radius * 1.6)
                        .position(layout.centre)
                }

                header
                    .frame(width: geometry.size.width)
            }
        }
    }

    /// The title, like the other widgets', and the website's live badge with the age of the model.
    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                title("Current aurora activity")
                title("Aurora activity")
            }

            Spacer(minLength: 0)

            if let modelDate = entry.modelDate {
                LiveBadge(since: modelDate, small: small)
            }
        }
        .padding(.horizontal, small ? 12 : 16)
        .padding(.top, small ? 10 : 12)
    }

    private func title(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.helvetica(10))
            .fontWeight(.bold)
            .foregroundColor(.white)
            .lineLimit(1)
            .fixedSize()
    }
}

/// "LIVE ∙ 12s ago", as the website's badge words it, kept current by the system between reloads.
/// Worded in the reader's language, as the website's badge is.
private struct LiveBadge: View {
    let since: Date
    let small: Bool

    private var age: Date.AnchoredRelativeFormatStyle {
        Date.AnchoredRelativeFormatStyle(anchor: since, allowedFields: [.minute, .second], presentation: .numeric,
                                         unitsStyle: .narrow, locale: .autoupdatingCurrent)
    }

    var body: some View {
        // Text kept current by the system takes all the room it is offered, so the badge is sized to
        // the widest it says within the hour and the live text is laid over that
        let live = String(localized: "LIVE")
        Text(verbatim: "\(live) ∙ \(age.format(since.addingTimeInterval(59 * 60)))")
            .hidden()
            .overlay {
                (Text(verbatim: "\(live) ∙ ") + Text(.currentDate, format: age))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
            .font(.helvetica(small ? 6.5 : 7))
            .fontWeight(.bold)
            .foregroundColor(.white)
            .lineLimit(1)
            .padding(.horizontal, 3)
            .padding(.vertical, 1.5)
            .background(Color(red: 1, green: 0, blue: 0))
    }
}

// MARK: - Widget Configuration

struct AuroraGlobeWidget: Widget {
    let kind: String = "AuroraGlobeWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectGlobeConfigurationIntent.self,
            provider: AuroraGlobeProvider()
        ) { entry in
            AuroraGlobeEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Aurora globe")
        .description("The norlys model on the globe, as on norlys.live: the auroral ovals, the terminator, substorms and your position, centred on you or on either geomagnetic pole.")
        .supportedFamilies([.systemSmall, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Preview

#Preview("Small", as: .systemSmall) {
    AuroraGlobeWidget()
} timeline: {
    AuroraGlobeProvider.sampleEntry(centre: .north)
}

#Preview("Large", as: .systemLarge) {
    AuroraGlobeWidget()
} timeline: {
    AuroraGlobeProvider.sampleEntry(centre: .north)
}
