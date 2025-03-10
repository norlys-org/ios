import WidgetKit
import SwiftUI

struct WebsiteSnapshotWidget: Widget {
    private let kind: String = "WebsiteSnapshotWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WebsiteSnapshotProvider()) { entry in
            WebsiteSnapshotWidgetView(entry: entry)
        }
        .configurationDisplayName("Website Snapshot")
        .description("Displays a snapshot of a website")
        .supportedFamilies([.systemSmall]) // This ensures a square widget
    }
}

struct WebsiteSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> WebsiteSnapshotEntry {
        WebsiteSnapshotEntry(date: Date(), imageURL: URL(string: "https://example.com/snapshot.png")!)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (WebsiteSnapshotEntry) -> Void) {
        let entry = WebsiteSnapshotEntry(date: Date(), imageURL: URL(string: "https://example.com/snapshot.png")!)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<WebsiteSnapshotEntry>) -> Void) {
        // Update every hour
        let currentDate = Date()
        let entry = WebsiteSnapshotEntry(date: currentDate, imageURL: URL(string: "https://example.com/snapshot.png")!)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct WebsiteSnapshotEntry: TimelineEntry {
    let date: Date
    let imageURL: URL
}

struct WebsiteSnapshotWidgetView: View {
    let entry: WebsiteSnapshotEntry
    
    var body: some View {
        AsyncImage(url: entry.imageURL) { phase in
            switch phase {
            case .empty:
                ProgressView()
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.red)
            @unknown default:
                EmptyView()
            }
        }
    }
}

#Preview {
    WebsiteSnapshotWidgetView(entry: WebsiteSnapshotEntry(
        date: Date(),
        imageURL: URL(string: "https://example.com/snapshot.png")!
    ))
    .previewContext(WidgetPreviewContext(family: .systemSmall))
} 