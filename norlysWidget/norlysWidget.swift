//
//  norlysWidget.swift
//  norlysWidget
//
//  Created by Hugo on 10.03.2025.
//

import WidgetKit
import SwiftUI
import Charts

struct MagneticData: Codable {
    let time_tag: String
    let bt: String
    let bx_gsm: String
    let by_gsm: String
    let bz_gsm: String
    let lat_gsm: String
    let lon_gsm: String
    let quality: String
    let source: String
    let active: String
}

struct Provider: TimelineProvider {
    func loadMockData() -> [[String]] {
        if let path = Bundle.main.path(forResource: "mockData", ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let jsonArray = try? JSONDecoder().decode([[String]].self, from: data) {
            return Array(jsonArray.dropFirst()) // Convert subsequence back to array
        }
        return []
    }
    
    func createMockEntry() -> SimpleEntry {
        let mockData = loadMockData()
        let magneticData = mockData.map { row -> (Double, Double, Bool, Date) in
            let btValue = Double(row[1]) ?? 0.0
            let bzValue = Double(row[4]) ?? 0.0
            let active = row[9] == "1"
            let date = ISO8601DateFormatter().date(from: row[0].replacingOccurrences(of: " ", with: "T") + "Z") ?? Date()
            return (btValue, bzValue, active, date)
        }
        .filter { $0.2 }
        .sorted { $0.3 < $1.3 }
        
        let btValues = magneticData.map { $0.0 }
        let bzValues = magneticData.map { $0.1 }
        let lastBtValue = btValues.last ?? 0.0
        let firstBtValue = btValues.first ?? 0.0
        let lastBzValue = bzValues.last ?? 0.0
        let firstBzValue = bzValues.first ?? 0.0
        
        // Calculate a realistic earth hit index about 1/3 through the data
        let earthHitIndex = magneticData.count
        
        var entry = SimpleEntry(
            date: Date(),
            btValue: lastBtValue,
            btTrend: lastBtValue - firstBtValue,
            bzValue: lastBzValue,
            bzTrend: lastBzValue - firstBzValue,
            historicalBtData: btValues,
            historicalBzData: bzValues,
            earthHitIndex: earthHitIndex,
            earthHitTimeMinutes: 42
        )
        
        entry.historicalData = magneticData.map { ($0.3, $0.0, $0.1) }
        return entry
    }

    func placeholder(in context: Context) -> SimpleEntry {
        return createMockEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(createMockEntry())
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        Task {
            let currentDate = Date()
            let magDataURL = URL(string: "https://services.swpc.noaa.gov/text/rtsw/data/mag-6-hour.i.json")!
            let plasmaDataURL = URL(string: "https://services.swpc.noaa.gov/text/rtsw/data/plasma-6-hour.i.json")!
            
            do {
                // Fetch magnetic data
                let (magData, _) = try await URLSession.shared.data(from: magDataURL)
                let magJsonArray = try JSONDecoder().decode([[String]].self, from: magData)
                
                // Fetch plasma data for speed calculation
                let (plasmaData, _) = try await URLSession.shared.data(from: plasmaDataURL)
                let plasmaJsonArray = try JSONDecoder().decode([[String]].self, from: plasmaData)
                
                // Process magnetic data
                let magneticData = magJsonArray.dropFirst().map { row -> (Double, Double, Bool, Date) in
                    let btValue = Double(row[1]) ?? 0.0
                    let bzValue = Double(row[4]) ?? 0.0
                    let active = row[9] == "1"
                    let date = ISO8601DateFormatter().date(from: row[0].replacingOccurrences(of: " ", with: "T") + "Z") ?? Date()
                    return (btValue, bzValue, active, date)
                }
                .filter { $0.2 }
                .sorted { $0.3 < $1.3 }  // Sort by date, oldest first
                
                // Create historical data array with timestamps
                let historicalData = magneticData.map { ($0.3, $0.0, $0.1) }
                
                // Get the last plasma speed
                if let lastPlasmaRow = plasmaJsonArray.dropFirst().last,
                   let speed = Double(lastPlasmaRow[1]) {
                    let distance = 1_500_000.0 // km
                    let travelTime = distance / speed / 60 // Convert to minutes
                    
                    if let lastDataDate = magneticData.last?.3 {
                        let earthHitDate = lastDataDate.addingTimeInterval(-travelTime * 60)
                        
                        // Find the index closest to earth hit date
                        let earthHitIndex = magneticData.enumerated().min { a, b in
                            abs(a.element.3.timeIntervalSince(earthHitDate)) < abs(b.element.3.timeIntervalSince(earthHitDate))
                        }?.offset
                        
                        let btValues = magneticData.map { $0.0 }
                        let bzValues = magneticData.map { $0.1 }
                        let lastBtValue = btValues.last ?? 0.0
                        let firstBtValue = btValues.first ?? 0.0
                        let lastBzValue = bzValues.last ?? 0.0
                        let firstBzValue = bzValues.first ?? 0.0
                        
                        var entry = SimpleEntry(
                            date: currentDate,
                            btValue: lastBtValue,
                            btTrend: lastBtValue - firstBtValue,
                            bzValue: lastBzValue,
                            bzTrend: lastBzValue - firstBzValue,
                            historicalBtData: btValues,
                            historicalBzData: bzValues,
                            earthHitIndex: earthHitIndex,
                            earthHitTimeMinutes: Int(round(travelTime))
                        )
                        entry.historicalData = historicalData
                        
                        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: currentDate)!
                        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                        completion(timeline)
                        return
                    }
                }
                
                // Fallback if plasma data calculation fails
                let btValues = magneticData.map { $0.0 }
                let bzValues = magneticData.map { $0.1 }
                var entry = SimpleEntry(
                    date: currentDate,
                    btValue: btValues.last ?? 0.0,
                    btTrend: (btValues.last ?? 0.0) - (btValues.first ?? 0.0),
                    bzValue: bzValues.last ?? 0.0,
                    bzTrend: (bzValues.last ?? 0.0) - (bzValues.first ?? 0.0),
                    historicalBtData: btValues,
                    historicalBzData: bzValues,
                    earthHitIndex: nil,
                    earthHitTimeMinutes: nil
                )
                entry.historicalData = historicalData
                
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: currentDate)!
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                completion(timeline)
            } catch {
                let entry = SimpleEntry(
                    date: currentDate,
                    btValue: 0.0,
                    btTrend: 0.0,
                    bzValue: 0.0,
                    bzTrend: 0.0,
                    historicalBtData: [],
                    historicalBzData: [],
                    earthHitIndex: nil,
                    earthHitTimeMinutes: nil
                )
                let timeline = Timeline(entries: [entry], policy: .after(currentDate.addingTimeInterval(60)))
                completion(timeline)
            }
        }
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let btValue: Double
    let btTrend: Double
    let bzValue: Double
    let bzTrend: Double
    let historicalBtData: [Double]
    let historicalBzData: [Double]
    let earthHitIndex: Int?
    let earthHitTimeMinutes: Int?
    var historicalData: [(date: Date, bt: Double, bz: Double)]  // Changed to var instead of let
    
    init(date: Date, btValue: Double, btTrend: Double, bzValue: Double, bzTrend: Double, historicalBtData: [Double], historicalBzData: [Double], earthHitIndex: Int? = nil, earthHitTimeMinutes: Int? = nil) {
        self.date = date
        self.btValue = btValue
        self.btTrend = btTrend
        self.bzValue = bzValue
        self.bzTrend = bzTrend
        self.historicalBtData = historicalBtData
        self.historicalBzData = historicalBzData
        self.earthHitIndex = earthHitIndex
        self.earthHitTimeMinutes = earthHitTimeMinutes
        self.historicalData = []  // This will be replaced in the actual timeline provider
    }
}

struct norlysWidgetEntryView : View {
    var entry: SimpleEntry
    
    private func formatTimeEstimate(_ minutes: Int) -> String {
        if minutes < 60 {
            return "In \(minutes) minutes"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "In \(hours) hour\(hours > 1 ? "s" : "")"
            } else {
                return "In \(hours)h \(remainingMinutes)m"
            }
        }
    }
    
    private func calculateMaxMagnitude() -> Double {
        let btMax = entry.historicalBtData.map { abs($0) }.max() ?? 0
        let bzMax = entry.historicalBzData.map { abs($0) }.max() ?? 0
        return max(btMax, bzMax)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let timeMinutes = entry.earthHitTimeMinutes {
                Text(formatTimeEstimate(timeMinutes))
                    .font(.custom("Helvetica", size: 12))
                    .fontWeight(.bold)
                    .foregroundColor(.gray)
            }
            
            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("Bt")
                        .font(.custom("Helvetica", size: 10))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text(String(format: "%.1f", abs(entry.btValue)))
                        .font(.custom("Helvetica", size: 32))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("(nT)")
                        .font(.custom("Helvetica", size: 10))
                        .fontWeight(.bold)
                        .foregroundColor(.gray)
                }
                
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(String(format: "%+.1f", entry.btTrend))
                        .font(.custom("Helvetica", size: 14))
                        .fontWeight(.bold)
                        .foregroundColor(entry.btTrend >= 0 ? .green : .red)
                }
            }
            .padding(.bottom, 8)  // Add spacing between text and graph
            
            if !entry.historicalData.isEmpty {
                Chart {
                    // Zero line for Bz
                    RuleMark(
                        y: .value("Zero", 0)
                    )
                    .foregroundStyle(.gray.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    
                    // Earth hit vertical line
                    if let earthHitIndex = entry.earthHitIndex,
                       earthHitIndex < entry.historicalData.count {
                        RuleMark(
                            x: .value("Earth Hit", entry.historicalData[earthHitIndex].date)
                        )
                        .foregroundStyle(.white)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    }
                    
                    // Bt data points (white)
                    ForEach(entry.historicalData, id: \.date) { dataPoint in
                        PointMark(
                            x: .value("Time", dataPoint.date),
                            y: .value("Bt", dataPoint.bt)
                        )
                        .foregroundStyle(.white)
                        .symbol(.circle)
                        .symbolSize(3)
                    }
                    
                    // Bz data points (red)
                    ForEach(entry.historicalData, id: \.date) { dataPoint in
                        PointMark(
                            x: .value("Time", dataPoint.date),
                            y: .value("Bz", dataPoint.bz)
                        )
                        .foregroundStyle(Color(uiColor: UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)))
                        .symbol(.circle)
                        .symbolSize(3)
                    }
                }
                .chartYScale(domain: -calculateMaxMagnitude()...calculateMaxMagnitude())
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 50)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(2)
        .background(Color.black)
    }
}

struct norlysWidget: Widget {
    let kind: String = "norlysWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            norlysWidgetEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Solar Wind Magnetic Field Widget")
        .description("Displays the solar wind magnetic field strength's value and the last 6 hours of Bz and Bt values as a scatter plot.")
        .supportedFamilies([.systemSmall])
    }
}

@available(iOSApplicationExtension 17.0, *)
#Preview("Small Widget", as: .systemSmall) {
    norlysWidget()
} timeline: {
    var entry = SimpleEntry(
        date: .now,
        btValue: 4.5,
        btTrend: 0.3,
        bzValue: 0.0,
        bzTrend: 0.0,
        historicalBtData: Array(repeating: 4.5, count: 100).enumerated().map { index, value in
            value + sin(Double(index) * 0.1) * 0.5
        },
        historicalBzData: [],
        earthHitIndex: 50,
        earthHitTimeMinutes: 50
    )
    
    // Add sample historical data for preview
    let now = Date()
    entry.historicalData = (0..<100).map { i in
        let date = now.addingTimeInterval(TimeInterval(-6 * 3600 + i * 360))  // 6 hours of data
        let bt = 4.5 + sin(Double(i) * 0.1) * 0.5
        let bz = 2.0 + cos(Double(i) * 0.1) * 0.5
        return (date, bt, bz)
    }
    return [entry]  // Return an array containing the entry
}
