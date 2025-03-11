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
    typealias Entry = WebcamEntry
    typealias Intent = SelectWebcamIntent
    
    func timeline(for configuration: Intent, in context: Context) async -> Timeline<WebcamEntry> {
        let currentDate = Date()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: currentDate)!

        let webcam = configuration.webcam ?? Webcam(id: "skibotn", name: "Skibotn")
        let entry = WebcamEntry(date: currentDate, webcam: webcam)
        
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
    
    func snapshot(for configuration: Intent, in context: Context) async -> WebcamEntry {
        let webcam = Webcam(id: "skibotn", name: "Skibotn")
        return WebcamEntry(date: Date(), webcam: webcam)
    }
    
    func placeholder(in context: Context) -> WebcamEntry {
        let webcam = Webcam(id: "loading", name: "Loading...")
        return WebcamEntry(date: Date(), webcam: webcam)
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
                .font(.custom("Helvetica", size: 12).weight(.bold))
                .foregroundColor(.white)
                .padding(6)
                .background {
                    Color.gray.opacity(0.7)
                        .cornerRadius(5)
                }
                .padding(14)
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
        .configurationDisplayName("Webcam")
        .description("Displays selected webcam and updates every minute.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
