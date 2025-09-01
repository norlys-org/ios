//
//  HLysWidget.swift
//  HLysWidget
//
//  Created by Hugo on 01.09.2025.
//  This widget displays the High Lys index and trends over the last 6 hours.
//  It fetches real-time data from api.norlys.live and displays a line chart with gradient fill.
//

import WidgetKit
import SwiftUI
import Charts

// MARK: - Data Models

/// LysPoint: Data model representing a single Lys index data point
struct LysPoint: Codable {
    let date: String
    let high: Double
    let mid: Double
    let stationsHigh: Int
    let stationsMid: Int
    
    enum CodingKeys: String, CodingKey {
        case date, high, mid
        case stationsHigh = "stations_high"
        case stationsMid = "stations_mid"
    }
}

/// LysIndexData: Root data model for the Lys index API response
struct LysIndexData: Codable {
    let points: [LysPoint]
}

// MARK: - Timeline Provider

/// Provider: Supplies timeline entries for the HLys widget
struct HLysProvider: TimelineProvider {
    
    /// Creates a mock timeline entry for testing
    func createMockEntry() -> HLysEntry {
        let currentDate = Date()
        let startDate = currentDate.addingTimeInterval(-6 * 3600) // 6 hours ago
        
        // Generate mock data points
        let mockData = (0..<72).map { i in
            let date = startDate.addingTimeInterval(Double(i) * 300) // 5-minute intervals
            let value = 100 + sin(Double(i) * 0.1) * 50 + Double.random(in: -20...20)
            return (date, max(0, value))
        }
        
        let values = mockData.map { $0.1 }
        let lastValue = values.last ?? 0.0
        let firstValue = values.first ?? 0.0
        
        return HLysEntry(
            date: currentDate,
            currentValue: lastValue,
            trend: lastValue - firstValue,
            historicalData: mockData,
            stationCount: 12
        )
    }
    
    /// Provides a placeholder entry for widget previews
    func placeholder(in context: Context) -> HLysEntry {
        return createMockEntry()
    }
    
    /// Provides a snapshot entry for widget previews
    func getSnapshot(in context: Context, completion: @escaping (HLysEntry) -> Void) {
        completion(createMockEntry())
    }
    
    /// Fetches real-time data from api.norlys.live
    func getTimeline(in context: Context, completion: @escaping (Timeline<HLysEntry>) -> Void) {
        Task {
            let currentDate = Date()
            let lysDataURL = URL(string: "https://api.norlys.live/data/lys-index")!
            
            do {
                // Fetch Lys index data
                let (data, _) = try await URLSession.shared.data(from: lysDataURL)
                let lysData = try JSONDecoder().decode(LysIndexData.self, from: data)
                
                // Process the data points
                let dateFormatter = ISO8601DateFormatter()
                let processedData = lysData.points.compactMap { point -> (Date, Double)? in
                    guard let date = dateFormatter.date(from: point.date) else { return nil }
                    return (date, point.high)
                }
                .sorted { $0.0 < $1.0 } // Sort by date
                
                // Filter to last 6 hours
                let sixHoursAgo = currentDate.addingTimeInterval(-6 * 3600)
                let recentData = processedData.filter { $0.0 >= sixHoursAgo }
                
                let values = recentData.map { $0.1 }
                let lastValue = values.last ?? 0.0
                let firstValue = values.first ?? 0.0
                
                // Get station count from the most recent data point
                let stationCount = lysData.points.last?.stationsHigh ?? 0
                
                let entry = HLysEntry(
                    date: currentDate,
                    currentValue: lastValue,
                    trend: lastValue - firstValue,
                    historicalData: recentData,
                    stationCount: stationCount
                )
                
                // Update every 5 minutes
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: currentDate)!
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                completion(timeline)
                
            } catch {
                print("Error fetching HLys data: \(error)")
                // Fallback to mock data on error
                let entry = createMockEntry()
                let timeline = Timeline(entries: [entry], policy: .after(currentDate.addingTimeInterval(300))) // Retry in 5 minutes
                completion(timeline)
            }
        }
    }
}

// MARK: - Timeline Entry

/// HLysEntry: Represents a single widget timeline entry for HLys data
struct HLysEntry: TimelineEntry {
    let date: Date
    let currentValue: Double
    let trend: Double
    let historicalData: [(Date, Double)]
    let stationCount: Int
}

// MARK: - Widget View

/// HLysWidgetEntryView: Main view for the HLys widget
struct HLysWidgetEntryView: View {
    var entry: HLysEntry
    
    /// Calculates the maximum value for scaling the graph (fixed scale 0-1000)
    private var maxValue: Double {
        return 1000.0 // Fixed scale as mentioned in the original JS code
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "Over 6 hours" text
            Text("Over 6 hours")
                .font(.custom("Helvetica", size: 12))
                .fontWeight(.bold)
                .foregroundColor(.gray)
            
            // Current HLys value and trend
            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("HLys")
                        .font(.custom("Helvetica", size: 10))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text(String(format: "%.0f", entry.currentValue))
                        .font(.custom("Helvetica", size: 32))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
             
                    Text("(nT)")
                        .font(.custom("Helvetica", size: 10))
                        .fontWeight(.bold)
                        .foregroundColor(.gray)
                }
                
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(String(format: "%+.0f", entry.trend))
                        .font(.custom("Helvetica", size: 14))
                        .fontWeight(.bold)
                        .foregroundColor(entry.trend >= 0 ? .green : .red)
                }
            }
            .padding(.bottom, 8)
            
            // Historical data chart
            if !entry.historicalData.isEmpty {
                Chart {
                    // Area gradient fill
                    ForEach(Array(entry.historicalData.enumerated()), id: \.offset) { index, dataPoint in
                        AreaMark(
                            x: .value("Time", dataPoint.0),
                            y: .value("Value", dataPoint.1),
                            stacking: .unstacked
                        )
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.green.opacity(0.6),
                                    Color.green.opacity(0.0)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    
                    // Line plot
                    ForEach(Array(entry.historicalData.enumerated()), id: \.offset) { index, dataPoint in
                        LineMark(
                            x: .value("Time", dataPoint.0),
                            y: .value("Value", dataPoint.1)
                        )
                        .foregroundStyle(Color.green)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartYScale(domain: 0...maxValue)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 80)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.bottom, 5)
        .padding(.top, 10)
        .background(Color.black)
        .clipped()
    }
}

// MARK: - Widget Configuration

/// HLysWidget: Configures the HLys widget
struct HLysWidget: Widget {
    let kind: String = "HLysWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HLysProvider()) { entry in
            HLysWidgetEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("High Lys Index Widget")
        .description("Displays the High Lys index value and trends over the last 6 hours.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Widget Preview

#Preview("Small Widget", as: .systemSmall) {
    HLysWidget()
} timeline: {
    let currentDate = Date()
    let startDate = currentDate.addingTimeInterval(-6 * 3600)
    
    // Generate sample data
    let sampleData = (0..<72).map { i in
        let date = startDate.addingTimeInterval(Double(i) * 300) // 5-minute intervals
        let value = 150 + sin(Double(i) * 0.15) * 80 + cos(Double(i) * 0.05) * 40
        return (date, max(0, value))
    }
    
    let entry = HLysEntry(
        date: currentDate,
        currentValue: sampleData.last?.1 ?? 150,
        trend: 25.0,
        historicalData: sampleData,
        stationCount: 12
    )
    
    return [entry]
}
