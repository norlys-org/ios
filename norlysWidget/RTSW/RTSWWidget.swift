//
//  RTSWWidget.swift
//  RTSWWidget
//
//  Created by Hugo on 10.03.2025.
//  This widget displays the solar wind magnetic field strength and trends.
//  It uses either local mock data or real-time data fetched from NOAA's SWPC,
//  processes magnetic field measurements, and displays a scatter plot for the last 6 hours of data.
//

import WidgetKit
import SwiftUI
import Charts

// MARK: - Data Models

/// MagneticData: Data model representing a magnetic field measurement from the source.
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

// MARK: - Timeline Provider

/// Provider: Supplies timeline entries for the widget by loading either mock data or real-time data.
struct Provider: TimelineProvider {
    
    // This function loads local mock JSON data for testing.
    // It returns an array of data rows (excluding the header row) if available.
    func loadMockData() -> [[String]] {
        if let path = Bundle.main.path(forResource: "mockData", ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let jsonArray = try? JSONDecoder().decode([[String]].self, from: data) {
            return Array(jsonArray.dropFirst()) // Drop header row if present.
        }
        return []
    }
    
    /// Creates a mock timeline entry using local mock data.
    func createMockEntry() -> SimpleEntry {
        let mockData = loadMockData()
        let endDateComponents = DateComponents(year: 2025, month: 3, day: 11, hour: 10, minute: 7)
        let endDate = Calendar.current.date(from: endDateComponents)!
        let startDate = endDate.addingTimeInterval(-6 * 3600)
        
        // Process each row of mock data to extract magnetic field values (bt and bz),
        // active flag, and convert the time tag into a Date object.
        let magneticData = mockData.map { row -> (Double, Double, Bool, Date) in
            let btValue = Double(row[1]) ?? 0.0
            let bzValue = Double(row[4]) ?? 0.0
            let active = row[9] == "1"
            let date = ISO8601DateFormatter().date(from: row[0].replacingOccurrences(of: " ", with: "T") + "Z") ?? Date()
            return (btValue, bzValue, active, date)
        }
        .filter { $0.2 }  // Filter only active data points.
        .sorted { $0.3 < $1.3 }  // Sort by date (oldest first).
        
        let btValues = magneticData.map { $0.0 }
        let bzValues = magneticData.map { $0.1 }
        let lastBtValue = btValues.last ?? 0.0
        let firstBtValue = btValues.first ?? 0.0
        let lastBzValue = bzValues.last ?? 0.0
        let firstBzValue = bzValues.first ?? 0.0
        
        // Compute the trend for bt and bz values using the first and last data points,
        // and estimate the earth hit index based on the count of active data points.
        let earthHitIndex = magneticData.count
        
        var entry = SimpleEntry(
            date: endDate,
            btValue: lastBtValue,
            btTrend: lastBtValue - firstBtValue,
            bzValue: lastBzValue,
            bzTrend: lastBzValue - firstBzValue,
            historicalBtData: btValues,
            historicalBzData: bzValues,
            earthHitIndex: earthHitIndex,
            earthHitTimeMinutes: 42
        )
        
        // Create a timeline of historical data points with evenly spaced timestamps.
        let totalPoints = magneticData.count
        if totalPoints > 1 {
            let interval = endDate.timeIntervalSince(startDate) / Double(totalPoints - 1)
            entry.historicalData = (0..<totalPoints).map { i in
                let date = startDate.addingTimeInterval(Double(i) * interval)
                return (date, btValues[i], bzValues[i])
            }
        } else {
            entry.historicalData = []
        }
        return entry
    }
    
    /// Provides a placeholder entry for widget previews.
    func placeholder(in context: Context) -> SimpleEntry {
        return createMockEntry()
    }
    
    /// Provides a snapshot entry for widget previews.
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(createMockEntry())
    }
    
    /// Fetches real-time data from remote endpoints and constructs timeline entries for the widget.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        Task {
            let currentDate = Date()
            let magDataURL = URL(string: "https://services.swpc.noaa.gov/text/rtsw/data/mag-6-hour.i.json")!
            let plasmaDataURL = URL(string: "https://services.swpc.noaa.gov/text/rtsw/data/plasma-6-hour.i.json")!
            
            do {
                // Fetch real-time magnetic data from NOAA's SWPC endpoint.
                let (magData, _) = try await URLSession.shared.data(from: magDataURL)
                let magJsonArray = try JSONDecoder().decode([[String]].self, from: magData)
                
                // Fetch real-time plasma data needed to calculate the solar wind travel time.
                let (plasmaData, _) = try await URLSession.shared.data(from: plasmaDataURL)
                let plasmaJsonArray = try JSONDecoder().decode([[String]].self, from: plasmaData)
                
                // Process magnetic data: parse, filter active entries, and sort by date (oldest first).
                let magneticData = magJsonArray.dropFirst().map { row -> (Double, Double, Bool, Date) in
                    let btValue = Double(row[1]) ?? 0.0
                    let bzValue = Double(row[4]) ?? 0.0
                    let active = row[9] == "1"
                    let date = ISO8601DateFormatter().date(from: row[0].replacingOccurrences(of: " ", with: "T") + "Z") ?? Date()
                    return (btValue, bzValue, active, date)
                }
                .filter { $0.2 }
                .sorted { $0.3 < $1.3 }
                
                // Create historical data array with timestamps.
                let historicalData = magneticData.map { ($0.3, $0.0, $0.1) }
                
                // Process plasma data to calculate travel time.
                if let lastPlasmaRow = plasmaJsonArray.dropFirst().last,
                   let speed = Double(lastPlasmaRow[1]) {
                    let distance = 1_500_000.0 // km
                    // Calculate the travel time (in minutes) based on a fixed distance and the measured plasma speed.
                    let travelTime = distance / speed / 60
                    
                    if let lastDataDate = magneticData.last?.3 {
                        let earthHitDate = lastDataDate.addingTimeInterval(-travelTime * 60)
                        
                        // Determine the index in the magnetic data array that is closest to the estimated earth hit time.
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
                
                // Fallback if plasma data calculation fails.
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
                // In case of an error, provide a default entry with empty data.
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

// MARK: - Timeline Entry

/// SimpleEntry: Represents a single widget timeline entry containing measurement data.
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
    /// historicalData: Stores tuples of (date, bt, bz) values for plotting.
    var historicalData: [(date: Date, bt: Double, bz: Double)]
    
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

// MARK: - Widget View

/// norlysWidgetEntryView: Main view for the widget displaying magnetic field data.
struct norlysWidgetEntryView : View {
    var entry: SimpleEntry
    
    // Helper function to convert a time in minutes to a formatted string (e.g., 'In 45 minutes' or 'In 1h 15m').
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
    
    /// Calculates the maximum magnitude from the historical data for scaling the graph.
    private func calculateMaxMagnitude() -> Double {
        let btMax = entry.historicalBtData.map { abs($0) }.max() ?? 0
        let bzMax = entry.historicalBzData.map { abs($0) }.max() ?? 0
        return max(btMax, bzMax)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Display the time estimate for the next event (e.g., earth hit) if available.
            if let timeMinutes = entry.earthHitTimeMinutes {
                Text(formatTimeEstimate(timeMinutes))
                    .font(.custom("Helvetica", size: 12))
                    .fontWeight(.bold)
                    .foregroundColor(.gray)
            }
            
            // Display the Bt measurement and its trend.
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
            .padding(.bottom, 8)
            
            // Display the historical data graph if available.
            if !entry.historicalData.isEmpty {
                // Prepare data series for the scatter plot by mapping historical data for Bt (white) and Bz (red) values.
                // Also, determine a vertical marker based on the earth hit index to indicate the event time on the graph.
                let maxMagnitude = max(
                    entry.historicalData.map { abs($0.bt) }.max() ?? 0,
                    entry.historicalData.map { abs($0.bz) }.max() ?? 0
                )
                
                // Prepare data series for Bt (white) and Bz (red) for graph plotting.
                let btSeries = GraphDataSeries(
                    label: "Bt",
                    data: entry.historicalData.map { DataPoint(date: $0.date, value: $0.bt) },
                    color: .white
                )
                let bzSeries = GraphDataSeries(
                    label: "Bz",
                    data: entry.historicalData.map { DataPoint(date: $0.date, value: $0.bz) },
                    color: Color(red: 1.0, green: 0.0, blue: 0.0)
                )
                
                // Determine vertical marker date from earth hit index, if available.
                let verticalMarker: Date? = {
                    if let index = entry.earthHitIndex, index < entry.historicalData.count {
                        return entry.historicalData[index].date
                    }
                    return nil
                }()
                
                // Use a reusable graph view to display the data series.
                ReusableGraphView(
                    dataSeries: [btSeries, bzSeries],
                    zeroLine: true,
                    verticalMarkerDate: verticalMarker,
                    chartDomain: entry.date.addingTimeInterval(-21600)...entry.date,
                    yDomain: -maxMagnitude...maxMagnitude
                )
                .frame(height: 80)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.bottom, 5)
        .padding(.top, 10)
        .background(Color.black)
        .clipped()  // Ensures the background extends to edges
    }
}

// MARK: - Widget Configuration

/// RTSWWidget: Configures the widget with the timeline provider and display settings.
struct RTSWWidget: Widget {
    let kind: String = "RTSWWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            norlysWidgetEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Solar Wind Magnetic Field Widget")
        .description("Displays the solar wind magnetic field strength's value and the last 6 hours of Bz and Bt values as a scatter plot.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Widget Preview

// Preview configuration: Uses sample data to simulate widget appearance in the small widget family.
#Preview("Small Widget", as: .systemSmall) {
    RTSWWidget()
} timeline: {
    let endDateComponents = DateComponents(year: 2025, month: 3, day: 11, hour: 10, minute: 7)
    let endDate = Calendar.current.date(from: endDateComponents)!
    let startDate = endDate.addingTimeInterval(-6 * 3600)
    var entry = SimpleEntry(
        date: endDate,
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
    
    let totalPoints = 100
    let interval = endDate.timeIntervalSince(startDate) / Double(totalPoints - 1)
    entry.historicalData = (0..<totalPoints).map { i in
        let date = startDate.addingTimeInterval(Double(i) * interval)
        let bt = 4.5 + sin(Double(i) * 0.1) * 0.5
        let bz = 2.0 + cos(Double(i) * 0.1) * 0.5
        return (date, bt, bz)
    }
    return [entry]
}
