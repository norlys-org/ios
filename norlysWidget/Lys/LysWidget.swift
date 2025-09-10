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
import SwiftProtobuf

// MARK: - Protobuf Models

/// IndexPoint: Protobuf model representing a single Lys index data point
struct IndexPoint {
    let date: Int64
    let high: Int32
    let mid: Int32
    let stationsHigh: Int32
    let stationsMid: Int32
}

/// LysIndex: Root protobuf model for the Lys index data
struct LysIndex {
    let points: [IndexPoint]
}

// MARK: - Protobuf Decoder

/// Simple protobuf decoder for LysIndex data
struct ProtobufDecoder {
    static func decodeLysIndex(from data: Data) throws -> LysIndex {
        var points: [IndexPoint] = []
        var index = 0
        
        while index < data.count {
            let (fieldNumber, wireType, newIndex) = try decodeTag(from: data, startIndex: index)
            index = newIndex
            
            if fieldNumber == 1 && wireType == 2 { // points field (repeated message)
                let (length, lengthIndex) = try decodeVarint(from: data, startIndex: index)
                index = lengthIndex
                
                let pointData = data.subdata(in: index..<(index + Int(length)))
                let point = try decodeIndexPoint(from: pointData)
                points.append(point)
                
                index += Int(length)
            } else {
                // Skip unknown fields
                index = try skipField(from: data, startIndex: index, wireType: wireType)
            }
        }
        
        return LysIndex(points: points)
    }
    
    private static func decodeIndexPoint(from data: Data) throws -> IndexPoint {
        var date: Int64 = 0
        var high: Int32 = 0
        var mid: Int32 = 0
        var stationsHigh: Int32 = 0
        var stationsMid: Int32 = 0
        var index = 0
        
        while index < data.count {
            let (fieldNumber, wireType, newIndex) = try decodeTag(from: data, startIndex: index)
            index = newIndex
            
            switch fieldNumber {
            case 1: // date
                let (value, valueIndex) = try decodeVarint(from: data, startIndex: index)
                date = Int64(value)
                index = valueIndex
            case 2: // high
                let (value, valueIndex) = try decodeVarint(from: data, startIndex: index)
                high = Int32(value)
                index = valueIndex
            case 3: // mid
                let (value, valueIndex) = try decodeVarint(from: data, startIndex: index)
                mid = Int32(value)
                index = valueIndex
            case 4: // stationsHigh
                let (value, valueIndex) = try decodeVarint(from: data, startIndex: index)
                stationsHigh = Int32(value)
                index = valueIndex
            case 5: // stationsMid
                let (value, valueIndex) = try decodeVarint(from: data, startIndex: index)
                stationsMid = Int32(value)
                index = valueIndex
            default:
                // Skip unknown fields
                index = try skipField(from: data, startIndex: index, wireType: wireType)
            }
        }
        
        return IndexPoint(
            date: date,
            high: high,
            mid: mid,
            stationsHigh: stationsHigh,
            stationsMid: stationsMid
        )
    }
    
    private static func decodeTag(from data: Data, startIndex: Int) throws -> (fieldNumber: UInt32, wireType: UInt32, newIndex: Int) {
        let (tag, newIndex) = try decodeVarint(from: data, startIndex: startIndex)
        let fieldNumber64 = tag >> 3
        let wireType64 = tag & 0x7
        guard let fieldNumber = UInt32(exactly: fieldNumber64),
              let wireType = UInt32(exactly: wireType64) else {
            throw ProtobufError.invalidData
        }
        return (fieldNumber, wireType, newIndex)
    }
    
    private static func decodeVarint(from data: Data, startIndex: Int) throws -> (UInt64, Int) {
        var result: UInt64 = 0
        var shift = 0
        var index = startIndex
        
        while index < data.count {
            let byte = data[index]
            result |= UInt64(byte & 0x7F) << shift
            index += 1
            
            if (byte & 0x80) == 0 {
                break
            }
            
            shift += 7
            if shift >= 64 {
                throw ProtobufError.invalidVarint
            }
        }
        
        return (result, index)
    }
    
    private static func skipField(from data: Data, startIndex: Int, wireType: UInt32) throws -> Int {
        switch wireType {
        case 0: // Varint
            let (_, newIndex) = try decodeVarint(from: data, startIndex: startIndex)
            return newIndex
        case 1: // 64-bit
            return startIndex + 8
        case 2: // Length-delimited
            let (length, lengthIndex) = try decodeVarint(from: data, startIndex: startIndex)
            return lengthIndex + Int(length)
        case 5: // 32-bit
            return startIndex + 4
        default:
            throw ProtobufError.unknownWireType
        }
    }
}

enum ProtobufError: Error {
    case invalidVarint
    case unknownWireType
    case invalidData
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
    
    /// Creates an error entry when data cannot be fetched
    func createErrorEntry(for configuration: SelectLysConfigurationIntent) -> LysEntry {
        let timespan = configuration.timespan ?? Timespan.allCases[0]
        let latitudeZone = configuration.latitudeZone ?? LatitudeZone.allCases[0]
        
        return LysEntry(
            date: Date(),
            currentValue: 0.0,
            trend: 0.0,
            historicalData: [], // Empty data to indicate error state
            stationCount: 0,
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
    
    /// Fetches real-time protobuf data from api.norlys.live
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
            // Fetch Lys index protobuf data
            let (data, _) = try await URLSession.shared.data(from: lysDataURL)
            let lysData = try ProtobufDecoder.decodeLysIndex(from: data)
            
            // Check if we have any data points
            guard !lysData.points.isEmpty else {
                print("No data points available from API")
                let errorEntry = createErrorEntry(for: configuration)
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: currentDate)!
                return Timeline(entries: [errorEntry], policy: .after(nextUpdate))
            }
            
            // Process the data points (converting from milliseconds to seconds for Date)
            let processedData = lysData.points.compactMap { point -> (Date, Double)? in
                let date = Date(timeIntervalSince1970: TimeInterval(point.date) / 1000.0)
                let value = latitudeZone.apiKey == "high" ? Double(point.high) : Double(point.mid)
                return (date, value)
            }
            .sorted { $0.0 < $1.0 } // Sort by date
            
            // Filter to selected timespan
            let hoursAgo = TimeInterval(hours) * 3600
            let timespanStartDate = currentDate.addingTimeInterval(-hoursAgo)
            let recentData = processedData.filter { $0.0 >= timespanStartDate }
            
            // Check if we have data for the selected timespan
            guard !recentData.isEmpty else {
                print("No data available for selected timespan")
                let errorEntry = createErrorEntry(for: configuration)
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: currentDate)!
                return Timeline(entries: [errorEntry], policy: .after(nextUpdate))
            }
            
            let values = recentData.map { $0.1 }
            let lastValue = values.last ?? 0.0
            let firstValue = values.first ?? 0.0
            
            // Get station count from the most recent data point
            let stationCount = latitudeZone.apiKey == "high" ?
                Int(lysData.points.last?.stationsHigh ?? 0) :
                Int(lysData.points.last?.stationsMid ?? 0)
            
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
            // Return error entry instead of mock data
            let errorEntry = createErrorEntry(for: configuration)
            let nextUpdate = currentDate.addingTimeInterval(300) // Retry in 5 minutes
            return Timeline(entries: [errorEntry], policy: .after(nextUpdate))
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
    
    /// Calculates the maximum value for scaling the graph:
    /// max(1000, max value of the dataset)
    private var maxValue: Double {
        let dataMax = entry.historicalData.map { $0.1 }.max() ?? 0
        return Swift.max(1000.0, dataMax)
    }
    
    /// Grid lines to show on the chart, scaled to the dynamic max
    private var gridLineValues: [Double] {
        let m = maxValue
        return [0.25 * m, 0.5 * m, 0.75 * m]
    }
    
    /// Format timespan display text
    private var timespanText: String {
        switch entry.timespan.id {
        case "6h": return "6 hours"
        case "24h": return "24 hours"
        case "7d": return "7 days"
        default: return "Over \(entry.timespan.name.lowercased())"
        }
    }
    
    /// Format latitude zone display text
    private var latitudeText: String {
        return String(entry.latitudeZone.apiKey.prefix(1)).uppercased() + "-Lys Index"
    }
    
    /// Check if this is an error state (no data)
    private var isErrorState: Bool {
        return entry.historicalData.isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Timespan text
            HStack(alignment: .bottom, spacing: 4) {
                Text(latitudeText)
                    .font(.custom("Helvetica", size: 10))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("(" + timespanText + ")")
                    .font(.custom("Helvetica", size: 8))
                    .fontWeight(.bold)
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 6)
            
            if isErrorState {
                // Error state view
                VStack(alignment: .center, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                    
                    Text("No Data Available")
                        .font(.custom("Helvetica", size: 16))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Unable to fetch Lys data")
                        .font(.custom("Helvetica", size: 10))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                // Normal data view
                // Current Lys value and trend
                VStack(alignment: .leading, spacing: -3) {
                    Text("Right now")
                        .font(.custom("Helvetica", size: 8))
                        .fontWeight(.bold)
                        .foregroundColor(.gray)
                    
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(String(format: "%.0f", entry.currentValue))
                            .font(.custom("Helvetica", size: 32))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "%+.0f", entry.trend))
                                .font(.custom("Helvetica", size: 10))
                                .fontWeight(.bold)
                                .foregroundColor(entry.trend >= 0 ? .green : .red)
                            
                            Text("(nT)")
                                .font(.custom("Helvetica", size: 6))
                                .fontWeight(.bold)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.bottom, 0)
                
                // Historical data chart
                Chart {
                    // Grid lines
                    ForEach(gridLineValues, id: \.self) { value in
                        RuleMark(y: .value("Grid", value))
                            .foregroundStyle(Color.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 0.5))
                            .annotation(position: .overlay, alignment: .leading) {
                                Text("\(Int(value))")
                                    .font(.custom("Helvetica", size: 8))
                                    .foregroundColor(.gray)
                                    .background(Color.black)
                                    .offset(x: -20)
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
                    plot.padding(.leading, 15)
                }
                .chartXScale(range: .plotDimension(padding: 0))
                .chartYScale(domain: 0...maxValue) // <-- dynamic scale
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
        .configurationDisplayName("H-Lys & M-Lys indices Widget:")
        .description("Displays a precise geomagnetic activity index with configurable timespan and latitude (H-Lys for high geomagnetic latitudes and M-Lys for mid-geomagnetic latitudes")
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
