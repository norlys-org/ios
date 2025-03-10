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
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), btValue: 0.0, btTrend: 0.0, bzValue: 0.0, bzTrend: 0.0, historicalBtData: [], historicalBzData: [], earthHitIndex: nil, earthHitTimeMinutes: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: Date(), btValue: 0.0, btTrend: 0.0, bzValue: 0.0, bzTrend: 0.0, historicalBtData: [], historicalBzData: [], earthHitIndex: nil, earthHitTimeMinutes: nil)
        completion(entry)
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
                    let bzValue = Double(row[4]) ?? 0.0  // bz_gsm is at index 4
                    let active = row[9] == "0"
                    let date = ISO8601DateFormatter().date(from: row[0].replacingOccurrences(of: " ", with: "T") + "Z") ?? Date()
                    return (btValue, bzValue, active, date)
                }
                .filter { $0.2 } // Only keep points where active is true
                
                // Get the last plasma speed
                if let lastPlasmaRow = plasmaJsonArray.dropFirst().last,
                   let speed = Double(lastPlasmaRow[1]) {
                    let distance = 1_500_000.0 // km
                    let travelTime = distance / speed / 60 // Convert to minutes
                    
                    if let lastDataDate = magneticData.first?.3 {
                        let earthHitDate = lastDataDate.addingTimeInterval(-travelTime * 60) // Convert minutes to seconds
                        
                        // Find the index closest to earth hit date
                        let earthHitIndex = magneticData.enumerated().min { a, b in
                            abs(a.element.3.timeIntervalSince(earthHitDate)) < abs(b.element.3.timeIntervalSince(earthHitDate))
                        }?.offset
                        
                        let btValues = magneticData.map { $0.0 }
                        let bzValues = magneticData.map { $0.1 }
                        let lastBtValue = btValues.first ?? 0.0
                        let firstBtValue = btValues.last ?? 0.0
                        let lastBzValue = bzValues.first ?? 0.0
                        let firstBzValue = bzValues.last ?? 0.0
                        
                        let entry = SimpleEntry(
                            date: currentDate,
                            btValue: lastBtValue,
                            btTrend: lastBtValue - firstBtValue,
                            bzValue: lastBzValue,
                            bzTrend: lastBzValue - firstBzValue,
                            historicalBtData: Array(btValues.reversed()), // Reverse the data to show oldest to newest
                            historicalBzData: Array(bzValues.reversed()),
                            earthHitIndex: earthHitIndex, // The original index is now correct
                            earthHitTimeMinutes: Int(round(travelTime))
                        )
                        
                        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: currentDate)!
                        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                        completion(timeline)
                        return
                    }
                }
                
                // Fallback if plasma data calculation fails
                let btValues = magneticData.map { $0.0 }
                let bzValues = magneticData.map { $0.1 }
                let entry = SimpleEntry(
                    date: currentDate,
                    btValue: btValues.first ?? 0.0,
                    btTrend: (btValues.first ?? 0.0) - (btValues.last ?? 0.0),
                    bzValue: bzValues.first ?? 0.0,
                    bzTrend: (bzValues.first ?? 0.0) - (bzValues.last ?? 0.0),
                    historicalBtData: Array(btValues.reversed()),
                    historicalBzData: Array(bzValues.reversed()),
                    earthHitIndex: nil,
                    earthHitTimeMinutes: nil
                )
                
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
                    .padding(.top, 2)  // Add minimal top padding
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
            
            if !entry.historicalBtData.isEmpty {
                Chart {
                    // Zero line for Bz
                    RuleMark(
                        y: .value("Zero", 0)
                    )
                    .foregroundStyle(.gray.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    
                    // Earth hit vertical line
                    if let earthHitIndex = entry.earthHitIndex {
                        RuleMark(
                            x: .value("Earth Hit", Double(earthHitIndex))
                        )
                        .foregroundStyle(.white)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    }
                    
                    // Bt data points (white)
                    ForEach(Array(entry.historicalBtData.enumerated()), id: \.offset) { index, value in
                        PointMark(
                            x: .value("Index", Double(index)),
                            y: .value("Value", value)
                        )
                        .foregroundStyle(.white)
                        .symbol(.circle)
                        .symbolSize(3)
                    }
                    
                    // Bz data points (red)
                    ForEach(Array(entry.historicalBzData.enumerated()), id: \.offset) { index, value in
                        PointMark(
                            x: .value("Index", Double(index)),
                            y: .value("Value", value)
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
        .padding(.horizontal, 2)  // Reduce horizontal padding from 6 to 4
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
        .configurationDisplayName("Magnetic Field Widget")
        .description("Displays current Bt value with trend")
        .supportedFamilies([.systemSmall])
    }
}

@available(iOSApplicationExtension 17.0, *)
#Preview("Small Widget", as: .systemSmall) {
    norlysWidget()
} timeline: {
    SimpleEntry(date: .now, btValue: 4.5, btTrend: 0.3, bzValue: 0.0, bzTrend: 0.0, historicalBtData: Array(repeating: 4.5, count: 100).enumerated().map { index, value in 
        value + sin(Double(index) * 0.1) * 0.5 
    }, historicalBzData: [], earthHitIndex: 50, earthHitTimeMinutes: 50)
}
