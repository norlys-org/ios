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

// MARK: - Provider
struct WebcamProvider: AppIntentTimelineProvider {
    typealias Entry = WebcamEntry
    typealias Intent = SelectWebcamIntent
    
    func timeline(for configuration: Intent, in context: Context) async -> Timeline<WebcamEntry> {
        let currentDate = Date()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: currentDate)!

        let webcam = configuration.webcam ?? Webcam(id: "skibotn", name: "Skibotn")
        var imageData: Data? = nil
        if let url = URL(string: "https://api.norlys.live/images/all-sky/\(webcam.id)") {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                imageData = data
            } catch {
                imageData = nil
            }
        }

        let entry = WebcamEntry(date: currentDate, webcam: webcam, imageData: imageData)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
    
    func snapshot(for configuration: Intent, in context: Context) async -> WebcamEntry {
        let webcam = Webcam(id: "skibotn", name: "Skibotn")
        var imageData: Data? = nil
        if let url = URL(string: "https://api.norlys.live/images/all-sky/\(webcam.id)") {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                imageData = data
            } catch {
                imageData = nil
            }
        }
        return WebcamEntry(date: Date(), webcam: webcam, imageData: imageData)
    }
    
    func placeholder(in context: Context) -> WebcamEntry {
        let webcam = Webcam(id: "loading", name: "Loading...")
        return WebcamEntry(date: Date(), webcam: webcam, imageData: nil)
    }
}

// MARK: - Widget Entry
struct WebcamEntry: TimelineEntry {
    let date: Date
    let webcam: Webcam
    let imageData: Data?
}

// MARK: - Widget View
struct WebcamWidgetEntryView: View {
    let entry: WebcamEntry
   
    var body: some View {
        ZStack(alignment: .topLeading) {
            if let imageData = entry.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
            
            Text(entry.webcam.name)
                .font(.custom("Helvetica", size: 12).weight(.bold))
                .foregroundColor(.white)
                .padding(6)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(10)
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
