import WidgetKit
import SwiftUI
import Intents

// Location model to store predefined locations and their image URLs
struct Location: Identifiable, Codable {
    let id: String
    let name: String
    let imageURL: URL
    
    static let predefinedLocations = [
        Location(id: "tromso", name: "Tromsø", imageURL: URL(string: "https://api.norlys.live/images/all-sky/pori")!),
        Location(id: "oslo", name: "Oslo", imageURL: URL(string: "https://api.example.com/oslo-live.jpg")!),
        Location(id: "bergen", name: "Bergen", imageURL: URL(string: "https://api.example.com/bergen-live.jpg")!)
    ]
    
    static func getLocation(for id: String) -> Location {
        return predefinedLocations.first { $0.id == id } ?? predefinedLocations[0]
    }
}

// Widget entry containing the image data and location info
struct LocationEntry: TimelineEntry {
    let date: Date
    let location: Location
    let imageData: Data?
    let configuration: ConfigureLocationIntent
}

// Widget provider to fetch images and create timeline
struct LocationProvider: IntentTimelineProvider {
    typealias Intent = ConfigureLocationIntent
    typealias Entry = LocationEntry
    
    func placeholder(in context: Context) -> LocationEntry {
        LocationEntry(
            date: Date(),
            location: Location.predefinedLocations[0],
            imageData: nil,
            configuration: ConfigureLocationIntent()
        )
    }

    func getSnapshot(for configuration: ConfigureLocationIntent, in context: Context, completion: @escaping (LocationEntry) -> ()) {
        let location = Location.getLocation(for: configuration.location ?? "tromso")
        let entry = LocationEntry(
            date: Date(),
            location: location,
            imageData: nil,
            configuration: configuration
        )
        completion(entry)
    }

    func getTimeline(for configuration: ConfigureLocationIntent, in context: Context, completion: @escaping (Timeline<LocationEntry>) -> ()) {
        let location = Location.getLocation(for: configuration.location ?? "tromso")
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: location.imageURL)
                let entry = LocationEntry(
                    date: Date(),
                    location: location,
                    imageData: data,
                    configuration: configuration
                )
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: Date())!
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                completion(timeline)
            } catch {
                let entry = LocationEntry(
                    date: Date(),
                    location: location,
                    imageData: nil,
                    configuration: configuration
                )
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: Date())!
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                completion(timeline)
            }
        }
    }
}

// Widget view
struct LocationWidgetEntryView : View {
    var entry: LocationProvider.Entry
    
    var body: some View {
        ZStack(alignment: .top) {
            if let imageData = entry.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Color.gray // Placeholder when image fails to load
            }
            
            Text(entry.location.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
                .padding(.top, 8)
        }
    }
}

// Main widget struct
struct LocationWidget: Widget {
    let kind: String = "LocationWidget"

    var body: some WidgetConfiguration {
        IntentConfiguration(
            kind: kind,
            intent: ConfigureLocationIntent.self,
            provider: LocationProvider()
        ) { entry in
            LocationWidgetEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Location View")
        .description("Shows a live image from your selected location.")
        .supportedFamilies([.systemSmall])
    }
}

// Preview provider
#Preview("Location Widget", as: .systemSmall) {
    LocationWidget()
} timeline: {
    LocationEntry(
        date: .now,
        location: Location.predefinedLocations[0],
        imageData: nil,
        configuration: ConfigureLocationIntent()
    )
} 