//
//  LysWidget.swift
//  norlys
//
//  Created by Hugo on 01.09.2025.
//

import AppIntents
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

/// Provider: Supplies timeline entries for the Lys widget
struct LysProvider: AppIntentTimelineProvider {
    typealias Entry = LysEntry
    typealias Intent = SelectLysConfigurationIntent
    
    /// Creates a mock timeline entry for testing
    func createMockEntry(for configuration: SelectLysConfigurationIntent) -> LysEntry {
        let timespan = configuration.timespan ?? Timespan.allCases[0]
        let latitudeZone = configuration.latitudeZone ?? LatitudeZone.allCases[0]
        let hours: Double
        switch timespan.id {
        case "6h": hours = 6
        case "24h": hours = 24
        case "7d": hours = 24 * 7
        default: hours = 24
        }
        let currentDate = Date()
        // let hours = configuration.timespan.hours
        let startDate = currentDate.addingTimeInterval(-TimeInterval(hours) * 3600)
        
        // Calculate interval based on timespan for realistic data density
        let interval: TimeInterval
        switch hours {
        case 6:
            interval = 300 // 5 minutes
        case 24:
            interval = 900 // 15 minutes
        default: // 7 days
            interval = 3600 // 1 hour
        }
        
        let pointCount = Int(TimeInterval(hours) * 3600 / interval)
        
        // Generate mock data points
        let mockData = (0..<pointCount).map { i in
            let date = startDate.addingTimeInterval(Double(i) * interval)
            let value = 100 + sin(Double(i) * 0.1) * 50 + Double.random(in: -20...20)
            return (date, max(0, value))
        }
        
        let values = mockData.map { $0.1 }
        let lastValue = values.last ?? 0.0
        let firstValue = values.first ?? 0.0
        
        return LysEntry(
            date: currentDate,
            currentValue: lastValue,
            trend: lastValue - firstValue,
            historicalData: mockData,
            stationCount: 12,
            timespan: timespan,
            latitudeZone: latitudeZone
        )
    }
    
    /// Provides a placeholder entry for widget previews
    func placeholder(in context: Context) -> LysEntry {
        let configuration = SelectLysConfigurationIntent()
        return createMockEntry(for: configuration)
    }
    
    /// Provides a snapshot entry for widget previews
    func snapshot(for configuration: SelectLysConfigurationIntent, in context: Context) async -> LysEntry {
        return createMockEntry(for: configuration)
    }
    
    /// Fetches real-time data from api.norlys.live
    func timeline(for configuration: SelectLysConfigurationIntent, in context: Context) async -> Timeline<LysEntry> {
        let currentDate = Date()
        let timespan = configuration.timespan ?? Timespan.allCases[0]
        let latitudeZone = configuration.latitudeZone ?? LatitudeZone.allCases[0]
        let hours: Double
        switch timespan.id {
        case "6h": hours = 6
        case "24h": hours = 24
        case "7d": hours = 24 * 7
        default: hours = 24
        }
        let lysDataURL = URL(string: "https://api.norlys.live/data/lys-index")!
        
        do {
            // Fetch Lys index data
            let (data, _) = try await URLSession.shared.data(from: lysDataURL)
            let lysData = try JSONDecoder().decode(LysIndexData.self, from: data)
            
            // Process the data points
            let dateFormatter = ISO8601DateFormatter()
            let processedData = lysData.points.compactMap { point -> (Date, Double)? in
                guard let date = dateFormatter.date(from: point.date) else { return nil }
                let value = latitudeZone.apiKey == "high" ? point.high : point.mid
                return (date, value)
            }
            .sorted { $0.0 < $1.0 } // Sort by date
            
            // Filter to selected timespan
            let hoursAgo = TimeInterval(hours) * 3600
            let timespanStartDate = currentDate.addingTimeInterval(-hoursAgo)
            let recentData = processedData.filter { $0.0 >= timespanStartDate }
            
            let values = recentData.map { $0.1 }
            let lastValue = values.last ?? 0.0
            let firstValue = values.first ?? 0.0
            
            // Get station count from the most recent data point
            let stationCount = latitudeZone.apiKey == "high" ?
                (lysData.points.last?.stationsHigh ?? 0) :
                (lysData.points.last?.stationsMid ?? 0)
            
            let entry = LysEntry(
                date: currentDate,
                currentValue: lastValue,
                trend: lastValue - firstValue,
                historicalData: recentData,
                stationCount: stationCount,
                timespan: timespan,
                latitudeZone: latitudeZone
            )
            
            // Update every 5 minutes
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: currentDate)!
            return Timeline(entries: [entry], policy: .after(nextUpdate))
            
        } catch {
            print("Error fetching Lys data: \(error)")
            // Fallback to mock data on error
            let entry = createMockEntry(for: configuration)
            let nextUpdate = currentDate.addingTimeInterval(300) // Retry in 5 minutes
            return Timeline(entries: [entry], policy: .after(nextUpdate))
        }
    }
}

// MARK: - Timeline Entry

/// LysEntry: Represents a single widget timeline entry for Lys data
struct LysEntry: TimelineEntry {
    let date: Date
    let currentValue: Double
    let trend: Double
    let historicalData: [(Date, Double)]
    let stationCount: Int
    let timespan: Timespan
    let latitudeZone: LatitudeZone
}

// MARK: - Widget View

/// LysWidgetEntryView: Main view for the Lys widget
struct LysWidgetEntryView: View {
    var entry: LysEntry
    
    /// Calculates the maximum value for scaling the graph (fixed scale 0-1000)
    private var maxValue: Double {
        return 1000.0 // Fixed scale as mentioned in the original JS code
    }
    
    /// Grid lines to show on the chart
    private var gridLineValues: [Double] {
        return [250, 500, 750]
    }
    
    /// Format timespan display text
    private var timespanText: String {
        switch entry.timespan.id {
        case "6h": return "Over 6 hours"
        case "24h": return "Over 24 hours"
        case "7d": return "Over 7 days"
        default: return "Over \(entry.timespan.name.lowercased())"
        }
    }
    
    /// Format latitude zone display text
    private var latitudeText: String {
        return String(entry.latitudeZone.apiKey.prefix(1)).uppercased() + "Lys"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Timespan text
            Text(timespanText)
                .font(.custom("Helvetica", size: 12))
                .fontWeight(.bold)
                .foregroundColor(.gray)
            
            // Current Lys value and trend
            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(latitudeText)
                        .font(.custom("Helvetica", size: 10))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text(String(format: "%.0f", entry.currentValue))
                        .font(.custom("Helvetica", size: 32))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "%+.0f", entry.trend))
                            .font(.custom("Helvetica", size: 14))
                            .fontWeight(.bold)
                            .foregroundColor(entry.trend >= 0 ? .green : .red)
                        
                        Text("(nT)")
                            .font(.custom("Helvetica", size: 6))
                            .fontWeight(.bold)
                            .foregroundColor(.gray)
                    }
            
                }
            }
            .padding(.bottom, 8)
            
            // Historical data chart
            if !entry.historicalData.isEmpty {
                Chart {
                    // Grid lines
                    ForEach(gridLineValues, id: \.self) { value in
                        RuleMark(y: .value("Grid", value))
                            .foregroundStyle(Color.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 0.5))
                            .annotation(position: .leading, alignment: .center) {
                                Text("\(Int(value))")
                                    .font(.custom("Helvetica", size: 8))
                                    .foregroundColor(.gray)
                                    .background(Color.black)
                            }

                    }
                    
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
                .chartPlotStyle { plot in
                    plot.padding(.leading, 16)
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

/// LysWidget: Configures the Lys widget
struct LysWidget: Widget {
    let kind: String = "LysWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectLysConfigurationIntent.self,
            provider: LysProvider()
        ) { entry in
            LysWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Lys Indices Widget")
        .description("Displays Lys index value and trends with configurable timespan and latitude.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Widget Preview

#Preview("Small Widget", as: .systemSmall) {
    LysWidget()
} timeline: {
    let currentDate = Date()
    let timespan = Timespan.allCases[0] // 6 hours
    let latitudeZone = LatitudeZone.allCases[0] // High latitudes
    let startDate = currentDate.addingTimeInterval(-TimeInterval(timespan.hours) * 3600)
    
    // Generate sample data
    let sampleData = (0..<72).map { i in
        let date = startDate.addingTimeInterval(Double(i) * 300) // 5-minute intervals
        let value = 150 + sin(Double(i) * 0.15) * 80 + cos(Double(i) * 0.05) * 40
        return (date, max(0, value))
    }
    
    let entry = LysEntry(
        date: currentDate,
        currentValue: sampleData.last?.1 ?? 150,
        trend: 25.0,
        historicalData: sampleData,
        stationCount: 12,
        timespan: timespan,
        latitudeZone: latitudeZone
    )
    
    return [entry]
}
