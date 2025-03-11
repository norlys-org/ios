//
//  WebcamWidget.swift
//  norlys
//
//  Created by Hugo Lageneste on 11/03/2025.
//

import AppIntents
import WidgetKit
import SwiftUI
import Intents

// MARK: - Configuration
struct WebcamWidgetConfiguration: Codable {
    let location: String
}

// MARK: - Provider
struct WebcamProvider: AppIntentTimelineProvider {
    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        
    }
    
    func snapshot(for configuration: Intent, in context: Context) async -> some TimelineEntry {
        
    }
    
    func placeholder(in context: Context) -> some TimelineEntry {
        
    }
}

// MARK: - Widget Entry
struct WebcamEntry: TimelineEntry {
    let date: Date
    let webcam: Webcam
}

// MARK: - Widget View
struct WebcamWidgetEntryView: View {
    let entry: WebcamEntry
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            AsyncImage(url: URL(string: "https://api.norlys.live/images/all-sky/\(entry.webcam.id)")) { phase in
                switch phase {
                case .empty:
                    Color.black
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Color.black
                @unknown default:
                    Color.black
                }
            }
            
            Text(entry.webcam.name)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(4)
                .background {
                    Color.black.opacity(0.5)
                }
        }
    }
}

// MARK: - Widget
struct WebcamWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "WebcamWidget",
            intent: SelectWebcamIntent.self,
            provider: WebcamProvider()
        ) { entry in
            WebcamWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("All-Sky Camera")
        .description("Display all-sky camera images from various locations")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
