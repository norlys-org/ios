//
//  RTSWMediumWidget.swift
//  RTSWWidget
//
//  Created by Hugo on 10.03.2025.
//  Medium widget displaying three line graphs: Bt+Bz, Speed, and Density
//  with gradient overlays and value labels.
//

import WidgetKit
import SwiftUI
import Charts

// MARK: - Data Models

/// PlasmaData: Data model representing plasma measurements from the source.
struct PlasmaData: Codable {
    let time_tag: String
    let speed: String
    let density: String
    let temperature: String
    let quality: String
    let source: String
    let active: String
}

// MARK: - Timeline Provider for Medium Widget

struct MediumProvider: TimelineProvider {
    
    func loadMockData() -> ([[String]], [[String]]) {
        // Load mock magnetic data
        let mockMagData: [[String]] = {
            if let path = Bundle.main.path(forResource: "mockMagData", ofType: "json"),
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let jsonArray = try? JSONDecoder().decode([[String]].self, from: data) {
                return Array(jsonArray.dropFirst())
            }
            return []
        }()
        
        // Load mock plasma data
        let mockPlasmaData: [[String]] = {
            if let path = Bundle.main.path(forResource: "mockPlasmaData", ofType: "json"),
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let jsonArray = try? JSONDecoder().decode([[String]].self, from: data) {
                return Array(jsonArray.dropFirst())
            }
            return []
        }()
        
        return (mockMagData, mockPlasmaData)
    }
    
    func createMockEntry() -> MediumEntry {
        let (mockMagData, mockPlasmaData) = loadMockData()
        let endDateComponents = DateComponents(year: 2025, month: 3, day: 11, hour: 10, minute: 7)
        let endDate = Calendar.current.date(from: endDateComponents)!
        let startDate = endDate.addingTimeInterval(-6 * 3600)
        
        // Process magnetic data
        let magneticData = mockMagData.map { row -> (Double, Double, Bool, Date) in
            let btValue = Double(row[1]) ?? 0.0
            let bzValue = Double(row[4]) ?? 0.0
            let active = row[9] == "1"
            let date = ISO8601DateFormatter().date(from: row[0].replacingOccurrences(of: " ", with: "T") + "Z") ?? Date()
            return (btValue, bzValue, active, date)
        }
        .filter { $0.2 }
        .sorted { $0.3 < $1.3 }
        
        // Process plasma data
        let plasmaData = mockPlasmaData.map { row -> (Double, Double, Bool, Date) in
            let speed = Double(row[1]) ?? 0.0
            let density = Double(row[2]) ?? 0.0
            let active = row[6] == "1"
            let date = ISO8601DateFormatter().date(from: row[0].replacingOccurrences(of: " ", with: "T") + "Z") ?? Date()
            return (speed, density, active, date)
        }
        .filter { $0.2 }
        .sorted { $0.3 < $1.3 }
        
        let btValues = magneticData.map { $0.0 }
        let bzValues = magneticData.map { $0.1 }
        let speedValues = plasmaData.map { $0.0 }
        let densityValues = plasmaData.map { $0.1 }
        
        let earthHitIndex = magneticData.count / 2
        
        var entry = MediumEntry(
            date: endDate,
            btValue: btValues.last ?? 0.0,
            btTrend: (btValues.last ?? 0.0) - (btValues.first ?? 0.0),
            bzValue: bzValues.last ?? 0.0,
            bzTrend: (bzValues.last ?? 0.0) - (bzValues.first ?? 0.0),
            speedValue: speedValues.last ?? 0.0,
            speedTrend: (speedValues.last ?? 0.0) - (speedValues.first ?? 0.0),
            densityValue: densityValues.last ?? 0.0,
            densityTrend: (densityValues.last ?? 0.0) - (densityValues.first ?? 0.0),
            historicalBtData: btValues,
            historicalBzData: bzValues,
            historicalSpeedData: speedValues,
            historicalDensityData: densityValues,
            earthHitIndex: earthHitIndex,
            earthHitTimeMinutes: 42
        )
        
        // Create historical data points with timestamps
        let totalMagPoints = magneticData.count
        let totalPlasmaPoints = plasmaData.count
        
        if totalMagPoints > 1 {
            let interval = endDate.timeIntervalSince(startDate) / Double(totalMagPoints - 1)
            entry.historicalMagData = (0..<totalMagPoints).map { i in
                let date = startDate.addingTimeInterval(Double(i) * interval)
                return (date, btValues[i], bzValues[i])
            }
        }
        
        if totalPlasmaPoints > 1 {
            let interval = endDate.timeIntervalSince(startDate) / Double(totalPlasmaPoints - 1)
            entry.historicalPlasmaData = (0..<totalPlasmaPoints).map { i in
                let date = startDate.addingTimeInterval(Double(i) * interval)
                return (date, speedValues[i], densityValues[i])
            }
        }
        
        return entry
    }
    
    func placeholder(in context: Context) -> MediumEntry {
        return createMockEntry()
    }
    
    func getSnapshot(in context: Context, completion: @escaping (MediumEntry) -> Void) {
        completion(createMockEntry())
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<MediumEntry>) -> Void) {
        Task {
            let currentDate = Date()
            let magDataURL = URL(string: "https://services.swpc.noaa.gov/text/rtsw/data/mag-6-hour.i.json")!
            let plasmaDataURL = URL(string: "https://services.swpc.noaa.gov/text/rtsw/data/plasma-6-hour.i.json")!
            
            do {
                // Fetch magnetic data
                let (magData, _) = try await URLSession.shared.data(from: magDataURL)
                let magJsonArray = try JSONDecoder().decode([[String]].self, from: magData)
                
                // Fetch plasma data
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
                .sorted { $0.3 < $1.3 }
                
                // Process plasma data (speed in row[1], density in row[2])
                let processedPlasmaData = plasmaJsonArray.dropFirst().map { row -> (Double, Double, Bool, Date) in
                    let speed = Double(row[1]) ?? 0.0
                    let density = Double(row[2]) ?? 0.0
                    let active = row[6] == "1"
                    let date = ISO8601DateFormatter().date(from: row[0].replacingOccurrences(of: " ", with: "T") + "Z") ?? Date()
                    return (speed, density, active, date)
                }
                .filter { $0.2 }
                .sorted { $0.3 < $1.3 }
                
                // Calculate earth hit timing
                let earthHitIndex: Int?
                let earthHitTimeMinutes: Int?
                
                if let lastPlasmaRow = plasmaJsonArray.dropFirst().last,
                   let speed = Double(lastPlasmaRow[1]) {
                    let distance = 1_500_000.0 // km
                    let travelTime = distance / speed / 60
                    
                    if let lastDataDate = magneticData.last?.3 {
                        let earthHitDate = lastDataDate.addingTimeInterval(-travelTime * 60)
                        earthHitIndex = magneticData.enumerated().min { a, b in
                            abs(a.element.3.timeIntervalSince(earthHitDate)) < abs(b.element.3.timeIntervalSince(earthHitDate))
                        }?.offset
                        earthHitTimeMinutes = Int(round(travelTime))
                    } else {
                        earthHitIndex = nil
                        earthHitTimeMinutes = nil
                    }
                } else {
                    earthHitIndex = nil
                    earthHitTimeMinutes = nil
                }
                
                let btValues = magneticData.map { $0.0 }
                let bzValues = magneticData.map { $0.1 }
                let speedValues = processedPlasmaData.map { $0.0 }
                let densityValues = processedPlasmaData.map { $0.1 }
                
                var entry = MediumEntry(
                    date: currentDate,
                    btValue: btValues.last ?? 0.0,
                    btTrend: (btValues.last ?? 0.0) - (btValues.first ?? 0.0),
                    bzValue: bzValues.last ?? 0.0,
                    bzTrend: (bzValues.last ?? 0.0) - (bzValues.first ?? 0.0),
                    speedValue: speedValues.last ?? 0.0,
                    speedTrend: (speedValues.last ?? 0.0) - (speedValues.first ?? 0.0),
                    densityValue: densityValues.last ?? 0.0,
                    densityTrend: (densityValues.last ?? 0.0) - (densityValues.first ?? 0.0),
                    historicalBtData: btValues,
                    historicalBzData: bzValues,
                    historicalSpeedData: speedValues,
                    historicalDensityData: densityValues,
                    earthHitIndex: earthHitIndex,
                    earthHitTimeMinutes: earthHitTimeMinutes
                )
                
                // Create historical data arrays
                entry.historicalMagData = magneticData.map { ($0.3, $0.0, $0.1) }
                entry.historicalPlasmaData = processedPlasmaData.map { ($0.3, $0.0, $0.1) }
                
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: currentDate)!
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                completion(timeline)
                
            } catch {
                // Fallback entry
                let entry = MediumEntry(
                    date: currentDate,
                    btValue: 0.0,
                    btTrend: 0.0,
                    bzValue: 0.0,
                    bzTrend: 0.0,
                    speedValue: 0.0,
                    speedTrend: 0.0,
                    densityValue: 0.0,
                    densityTrend: 0.0,
                    historicalBtData: [],
                    historicalBzData: [],
                    historicalSpeedData: [],
                    historicalDensityData: [],
                    earthHitIndex: nil,
                    earthHitTimeMinutes: nil
                )
                let timeline = Timeline(entries: [entry], policy: .after(currentDate.addingTimeInterval(60)))
                completion(timeline)
            }
        }
    }
}

// MARK: - Timeline Entry for Medium Widget

struct MediumEntry: TimelineEntry {
    let date: Date
    let btValue: Double
    let btTrend: Double
    let bzValue: Double
    let bzTrend: Double
    let speedValue: Double
    let speedTrend: Double
    let densityValue: Double
    let densityTrend: Double
    let historicalBtData: [Double]
    let historicalBzData: [Double]
    let historicalSpeedData: [Double]
    let historicalDensityData: [Double]
    let earthHitIndex: Int?
    let earthHitTimeMinutes: Int?
    
    var historicalMagData: [(date: Date, bt: Double, bz: Double)] = []
    var historicalPlasmaData: [(date: Date, speed: Double, density: Double)] = []
}

// MARK: - Medium Widget View

struct RTSWMediumWidgetEntryView: View {
    var entry: MediumEntry
    
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Time estimate header
            if let timeMinutes = entry.earthHitTimeMinutes {
                Text(formatTimeEstimate(timeMinutes))
                    .font(.custom("Helvetica", size: 8))
                    .fontWeight(.bold)
                    .foregroundColor(.gray)
                    .padding(.bottom, -5)
            }
            
            // Graph 1: Bt + Bz
            HStack(alignment: .center, spacing: 2) {
        
                VStack(alignment: .leading, spacing: -3) {
                
                    
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("Bt")
                            .font(.custom("Helvetica", size: 10))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    
                        Text(String(format: "%.1f", abs(entry.btValue)))
                            .font(.custom("Helvetica", size: 30))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(format: "%+.1f", entry.btTrend))
                                .font(.custom("Helvetica", size: 10))
                                .fontWeight(.bold)
                                .foregroundColor(entry.btTrend >= 0 ? .green : .red)
                            
                            Text("(nT)")
                                .font(.custom("Helvetica", size: 6))
                                .fontWeight(.bold)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .frame(width: 90, alignment: .leading)
                
                // Graph section
                if !entry.historicalMagData.isEmpty {
                    let maxMagMagnitude = max(
                        entry.historicalMagData.map { abs($0.bt) }.max() ?? 0,
                        entry.historicalMagData.map { abs($0.bz) }.max() ?? 0
                    )
                    
                    let btSeries = GraphDataSeries(
                        label: "Bt",
                        data: entry.historicalMagData.map { DataPoint(date: $0.date, value: $0.bt) },
                        color: .white
                    )
                    let bzSeries = GraphDataSeries(
                        label: "Bz",
                        data: entry.historicalMagData.map { DataPoint(date: $0.date, value: $0.bz) },
                        color: Color(red: 1.0, green: 0.0, blue: 0.0)
                    )
                    
                    let verticalMarker: Date? = {
                        if let index = entry.earthHitIndex, index < entry.historicalMagData.count {
                            return entry.historicalMagData[index].date
                        }
                        return nil
                    }()
                    
                    ReusableGraphView(
                        dataSeries: [btSeries, bzSeries],
                        zeroLine: true,
                        verticalMarkerDate: verticalMarker,
                        chartDomain: entry.date.addingTimeInterval(-21600)...entry.date,
                        yDomain: -maxMagMagnitude...maxMagMagnitude
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 35)
            
            Spacer().frame(height: 2)
            
            // Graph 2: Speed
            HStack(alignment: .center, spacing: 2) {
                // Labels section
                VStack(alignment: .leading, spacing: -3) {
                    Text("Speed")
                        .font(.custom("Helvetica", size: 10))
                        .fontWeight(.bold)
                        .foregroundColor(.yellow)
                    
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.0f", abs(entry.speedValue)))
                            .font(.custom("Helvetica", size: 30))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(format: "%+.1f", entry.speedTrend))
                                .font(.custom("Helvetica", size: 10))
                                .fontWeight(.bold)
                                .foregroundColor(entry.speedTrend >= 0 ? .green : .red)
                            
                            Text("(km/s)")
                                .font(.custom("Helvetica", size: 6))
                                .fontWeight(.bold)
                                .foregroundColor(.gray)
                        }

                    }
                }
                .frame(width: 90, alignment: .leading)
                
                // Graph section
                if !entry.historicalPlasmaData.isEmpty {
                    let maxSpeed = entry.historicalPlasmaData.map { $0.speed }.max() ?? 0
                    let minSpeed = entry.historicalPlasmaData.map { $0.speed }.min() ?? 0
                    
                    let speedSeries = GraphDataSeries(
                        label: "Speed",
                        data: entry.historicalPlasmaData.map { DataPoint(date: $0.date, value: $0.speed) },
                        color: .yellow
                    )
                    
                    // Calculate vertical marker date for plasma data
                    let verticalMarker: Date? = {
                        if let index = entry.earthHitIndex, index < entry.historicalMagData.count {
                            return entry.historicalMagData[index].date
                        }
                        return nil
                    }()
                    
                    ReusableGraphView(
                        dataSeries: [speedSeries],
                        zeroLine: false,
                        verticalMarkerDate: verticalMarker,
                        chartDomain: entry.date.addingTimeInterval(-21600)...entry.date,
                        yDomain: minSpeed...maxSpeed
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 35)
            
            Spacer().frame(height: 2)
            
            // Graph 3: Density
            HStack(alignment: .center, spacing: 2) {
                // Labels section
                VStack(alignment: .leading, spacing: -3) {
                    Text("Density")
                        .font(.custom("Helvetica", size: 10))
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", abs(entry.densityValue)))
                            .font(.custom("Helvetica", size: 30))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(format: "%+.1f", entry.densityTrend))
                                .font(.custom("Helvetica", size: 10))
                                .fontWeight(.bold)
                                .foregroundColor(entry.densityTrend >= 0 ? .green : .red)
                            
                            
                            Text("(p/cm³)")
                                .font(.custom("Helvetica", size: 6))
                                .fontWeight(.bold)
                                .foregroundColor(.gray)
                        }
                    
                    }
                }
                .frame(width: 90, alignment: .leading)
                
                // Graph section
                if !entry.historicalPlasmaData.isEmpty {
                    let maxDensity = entry.historicalPlasmaData.map { $0.density }.max() ?? 0
                    let minDensity = entry.historicalPlasmaData.map { $0.density }.min() ?? 0
                    
                    let densitySeries = GraphDataSeries(
                        label: "Density",
                        data: entry.historicalPlasmaData.map { DataPoint(date: $0.date, value: $0.density) },
                        color: .orange
                    )
                    
                    // Calculate vertical marker date for plasma data
                    let verticalMarker: Date? = {
                        if let index = entry.earthHitIndex, index < entry.historicalMagData.count {
                            return entry.historicalMagData[index].date
                        }
                        return nil
                    }()
                    
                    ReusableGraphView(
                        dataSeries: [densitySeries],
                        zeroLine: false,
                        verticalMarkerDate: verticalMarker,
                        chartDomain: entry.date.addingTimeInterval(-21600)...entry.date,
                        yDomain: minDensity...maxDensity
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 35)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.bottom, 10)
        .padding(.top, 10)
        .background(Color.black)
        .clipped()
    }
}

// MARK: - Medium Widget Configuration

struct RTSWMediumWidget: Widget {
    let kind: String = "RTSWMediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MediumProvider()) { entry in
            RTSWMediumWidgetEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Solar Wind Widget")
        .description("Displays magnetic field (Bt/Bz), solar wind speed, and plasma density with 6-hour trends.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Preview

#Preview("Medium Widget", as: .systemMedium) {
    RTSWMediumWidget()
} timeline: {
    let endDateComponents = DateComponents(year: 2025, month: 3, day: 11, hour: 10, minute: 7)
    let endDate = Calendar.current.date(from: endDateComponents)!
    let startDate = endDate.addingTimeInterval(-6 * 3600)
    
    var entry = MediumEntry(
        date: endDate,
        btValue: 4.5,
        btTrend: 0.3,
        bzValue: -2.1,
        bzTrend: -0.5,
        speedValue: 425.0,
        speedTrend: 15.0,
        densityValue: 8.2,
        densityTrend: -1.1,
        historicalBtData: [],
        historicalBzData: [],
        historicalSpeedData: [],
        historicalDensityData: [],
        earthHitIndex: 50,
        earthHitTimeMinutes: 45
    )
    
    // Generate sample data for preview
    let totalPoints = 100
    let interval = endDate.timeIntervalSince(startDate) / Double(totalPoints - 1)
    
    entry.historicalMagData = (0..<totalPoints).map { i in
        let date = startDate.addingTimeInterval(Double(i) * interval)
        let bt = 4.5 + sin(Double(i) * 0.1) * 0.8
        let bz = -2.1 + cos(Double(i) * 0.15) * 1.2
        return (date, bt, bz)
    }
    
    entry.historicalPlasmaData = (0..<totalPoints).map { i in
        let date = startDate.addingTimeInterval(Double(i) * interval)
        let speed = 425.0 + sin(Double(i) * 0.08) * 25.0
        let density = 8.2 + cos(Double(i) * 0.12) * 2.0
        return (date, speed, density)
    }
    
    return [entry]
}
