//
//  NorlysPositionWidget.swift
//  norlys
//
//  Created by Hugo on 09.09.2025.
//

import WidgetKit
import SwiftUI
import CoreLocation

// MARK: - Protobuf Models

struct MapPoint {
    let lat: Double
    let lon: Double
    let score: Double
    let speed: Double
}

struct MapMatrix {
    let timestamp: Int64
    let matrix: [MapPoint]
}

struct MapMatrices {
    let matrices: [MapMatrix]
}

// MARK: - Protobuf Decoder (MapMatrices -> MapMatrix -> MapPoint)

enum NorlysProtoError: Error {
    case invalidVarint
    case invalidData
    case unknownWireType
    case truncated
}

struct NorlysProtoDecoder {
    // Top-level
    static func decodeMapMatrices(from data: Data) throws -> MapMatrices {
        var matrices: [MapMatrix] = []
        var i = 0
        while i < data.count {
            let (field, wire, ni) = try decodeTag(data, i)
            i = ni
            if field == 1 && wire == 2 {
                let (len, li) = try decodeVarint(data, i)
                i = li
                let end = i + Int(len)
                guard end <= data.count else { throw NorlysProtoError.truncated }
                let sub = data.subdata(in: i..<end)
                matrices.append(try decodeMapMatrix(from: sub))
                i = end
            } else {
                i = try skipField(data, i, wire)
            }
        }
        return MapMatrices(matrices: matrices)
    }
    
    // MapMatrix { int64 timestamp = 1; repeated MapPoint matrix = 2; }
    private static func decodeMapMatrix(from data: Data) throws -> MapMatrix {
        var ts: Int64 = 0
        var points: [MapPoint] = []
        var i = 0
        while i < data.count {
            let (field, wire, ni) = try decodeTag(data, i)
            i = ni
            switch field {
            case 1: // timestamp (varint)
                let (v, li) = try decodeVarint(data, i)
                ts = Int64(v)
                i = li
            case 2: // matrix (len-delimited MapPoint)
                let (len, li) = try decodeVarint(data, i)
                i = li
                let end = i + Int(len)
                guard end <= data.count else { throw NorlysProtoError.truncated }
                let sub = data.subdata(in: i..<end)
                points.append(try decodeMapPoint(from: sub))
                i = end
            default:
                i = try skipField(data, i, wire)
            }
        }
        return MapMatrix(timestamp: ts, matrix: points)
    }
    
    // MapPoint { double lat=1; double lon=2; double score=3; double speed=4; }
    private static func decodeMapPoint(from data: Data) throws -> MapPoint {
        var lat = 0.0, lon = 0.0, score = 0.0, speed = 0.0
        var i = 0
        while i < data.count {
            let (field, wire, ni) = try decodeTag(data, i)
            i = ni
            switch field {
            case 1: // double -> 64-bit
                let (d, li) = try decodeFixed64Double(data, i)
                lat = d; i = li
            case 2:
                let (d, li) = try decodeFixed64Double(data, i)
                lon = d; i = li
            case 3:
                let (d, li) = try decodeFixed64Double(data, i)
                score = d; i = li
            case 4:
                let (d, li) = try decodeFixed64Double(data, i)
                speed = d; i = li
            default:
                i = try skipField(data, i, wire)
            }
        }
        return MapPoint(lat: lat, lon: lon, score: score, speed: speed)
    }
    
    // MARK: - Low-level helpers
    private static func decodeTag(_ data: Data, _ start: Int) throws -> (UInt32, UInt32, Int) {
        let (tag, ni) = try decodeVarint(data, start)
        let field = UInt32(tag >> 3)
        let wire = UInt32(tag & 0x7)
        return (field, wire, ni)
    }
    
    private static func decodeVarint(_ data: Data, _ start: Int) throws -> (UInt64, Int) {
        var res: UInt64 = 0
        var shift = 0
        var i = start
        while i < data.count {
            let b = data[i]
            res |= UInt64(b & 0x7F) << shift
            i += 1
            if (b & 0x80) == 0 { return (res, i) }
            shift += 7
            if shift >= 64 { throw NorlysProtoError.invalidVarint }
        }
        throw NorlysProtoError.truncated
    }
    
    // FIXED: Safe double decoding to avoid memory alignment issues
    private static func decodeFixed64Double(_ data: Data, _ start: Int) throws -> (Double, Int) {
        let end = start + 8
        guard end <= data.count else { throw NorlysProtoError.truncated }
        
        // Safe way to read 8 bytes as UInt64, avoiding alignment issues
        var bytes: [UInt8] = Array(data[start..<end])
        let value = bytes.withUnsafeBytes { ptr in
            ptr.load(as: UInt64.self)
        }
        
        return (Double(bitPattern: value), end)
    }
    
    private static func skipField(_ data: Data, _ start: Int, _ wire: UInt32) throws -> Int {
        switch wire {
        case 0:
            let (_, ni) = try decodeVarint(data, start); return ni
        case 1:
            return start + 8
        case 2:
            let (len, li) = try decodeVarint(data, start); return li + Int(len)
        case 5:
            return start + 4
        default:
            throw NorlysProtoError.unknownWireType
        }
    }
}

// MARK: - Location Helper (best-effort)

final class LastKnownLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((CLLocation?) -> Void)?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }
    
    func fetchLastKnown(completion: @escaping (CLLocation?) -> Void) {
        self.completion = completion
        // Widgets cannot prompt; use whatever is available.
        completion(manager.location)
    }
}

// MARK: - Timeline Entry

struct NorlysPositionEntry: TimelineEntry {
    let date: Date
    let location: CLLocationCoordinate2D
    let scoreDiv10: Double?  // score / 10 if available
    let isError: Bool
}

// MARK: - Provider

struct NorlysPositionProvider: TimelineProvider {
    private let apiBase = URL(string: "https://api.norlys.live")! // adjust if needed
    private let endpoint = "/norlys/latest"
    
    func placeholder(in context: Context) -> NorlysPositionEntry {
        NorlysPositionEntry(
            date: Date(),
            location: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
            scoreDiv10: 7.3,
            isError: false
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (NorlysPositionEntry) -> Void) {
        completion(placeholder(in: context))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<NorlysPositionEntry>) -> Void) {
        let now = Date()
        let locProvider = LastKnownLocationProvider()
        
        locProvider.fetchLastKnown { loc in
            let userCoord = loc?.coordinate ?? CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522) // Paris fallback
            
            Task {
                do {
                    let url = apiBase.appendingPathComponent(endpoint)
                    let (data, response) = try await URLSession.shared.data(from: url)
                    
                    // Check HTTP response
                    if let httpResponse = response as? HTTPURLResponse {
                        print("NorlysPositionWidget: HTTP Status: \(httpResponse.statusCode)")
                        guard 200...299 ~= httpResponse.statusCode else {
                            throw URLError(.badServerResponse)
                        }
                    }
                    
                    print("NorlysPositionWidget: Received \(data.count) bytes")
                    
                    let matrices = try NorlysProtoDecoder.decodeMapMatrices(from: data)
                    print("NorlysPositionWidget: Decoded \(matrices.matrices.count) matrices")
                    
                    guard let latest = matrices.matrices.max(by: { $0.timestamp < $1.timestamp }),
                          !latest.matrix.isEmpty else {
                        print("NorlysPositionWidget: No valid data found")
                        let entry = NorlysPositionEntry(date: now, location: userCoord, scoreDiv10: nil, isError: true)
                        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(300))))
                        return
                    }
                    
                    print("NorlysPositionWidget: Latest matrix has \(latest.matrix.count) points")
                    
                    // Find closest point to user location
                    let closest = closestPoint(to: userCoord, in: latest.matrix)
                    let scoreDiv10 = closest != nil ? (closest!.score / 10.0) : nil
                    
                    print("NorlysPositionWidget: Closest score: \(scoreDiv10 ?? 0)")
                    
                    let entry = NorlysPositionEntry(
                        date: now,
                        location: userCoord,
                        scoreDiv10: scoreDiv10,
                        isError: scoreDiv10 == nil
                    )
                    
                    // Refresh every 5 minutes (server updates more often; widgets have limits)
                    completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(300))))
                } catch {
                    print("NorlysPositionWidget: Error - \(error)")
                    let entry = NorlysPositionEntry(date: now, location: userCoord, scoreDiv10: nil, isError: true)
                    completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(300))))
                }
            }
        }
    }
    
    // Haversine for accuracy (km)
    private func distanceKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let R = 6371.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat/2)*sin(dLat/2) + sin(dLon/2)*sin(dLon/2)*cos(lat1)*cos(lat2)
        return 2 * R * asin(min(1, sqrt(h)))
    }
    
    private func closestPoint(to coord: CLLocationCoordinate2D, in points: [MapPoint]) -> MapPoint? {
        var best: MapPoint?
        var bestDist = Double.greatestFiniteMagnitude
        for p in points {
            let d = distanceKm(coord, CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon))
            if d < bestDist {
                bestDist = d
                best = p
            }
        }
        return best
    }
}

// MARK: - Color Helper

extension Color {
    // Primary color palette from 900 (darkest) to 50 (lightest)
    static let norlysColors = [
        Color(red: 0, green: 0, blue: 0),
        Color(red: 13/255, green: 83/255, blue: 33/255),   // 900 - darkest
        Color(red: 10/255, green: 113/255, blue: 41/255),  // 800
        Color(red: 5/255, green: 144/255, blue: 46/255),   // 700
        Color(red: 1/255, green: 184/255, blue: 54/255),   // 600
        Color(red: 9/255, green: 222/255, blue: 70/255),   // 500
        Color(red: 51/255, green: 245/255, blue: 107/255), // 400
        Color(red: 89/255, green: 255/255, blue: 136/255), // 300
        Color(red: 178/255, green: 255/255, blue: 199/255),// 200
        Color(red: 215/255, green: 255/255, blue: 226/255),// 100
        Color(red: 238/255, green: 255/255, blue: 242/255) // 50 - lightest
    ]
    
    static func backgroundColorForScore(_ score: Double) -> Color {
        // Clamp score between 0 and 10
        let clampedScore = max(0, min(10, score))
        
        // Map score to color index (0-9)
        let colorIndex = Int(clampedScore)
        
        if colorIndex >= norlysColors.count {
            return norlysColors.last ?? .black
        }
        
        return norlysColors[colorIndex]
    }
    
    static func textColorForScore(_ score: Double) -> Color {
        // Use white text for darker backgrounds (scores 0-5), black for lighter (6-10)
        return score < 6 ? .white : .black
    }
    
    static func secondaryTextColorForScore(_ score: Double) -> Color {
        // Use gray/white for darker backgrounds, darker gray for lighter backgrounds
        return score < 6 ? .gray : Color(.systemGray)
    }
}

// MARK: - Widget View

struct NorlysPositionEntryView: View {
    var entry: NorlysPositionEntry
    
    var body: some View {
        let score = 0.1
//        let score = entry.scoreDiv10 ?? 0
        let backgroundColor = entry.isError ? Color.black : Color.backgroundColorForScore(score)
        let textColor = entry.isError ? Color.white : Color.textColorForScore(score)
        let secondaryTextColor = entry.isError ? Color.gray : Color.secondaryTextColorForScore(score)
        
        VStack(alignment: .leading, spacing: 0) {
            Text("Aurora at your location")
                .font(.custom("Helvetica", size: 10))
                .fontWeight(.bold)
                .foregroundColor(textColor)
                .lineLimit(1)
                .padding(.bottom, 10)
            
            Text("Right now")
                .font(.custom("Helvetica", size: 8))
                .fontWeight(.bold)
                .foregroundColor(secondaryTextColor)
            
            if entry.isError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 16))
                    Text("Unavailable")
                        .font(.custom("Helvetica", size: 16))
                        .fontWeight(.bold)
                        .foregroundColor(textColor)
                }
                .padding(.top, 2)
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(formattedScore(score))
                        .font(.custom("Helvetica", size: 60))
                        .fontWeight(.bold)
                        .foregroundColor(textColor)
                    
                    Text("out of 10")
                        .font(.custom("Helvetica", size: 8))
                        .fontWeight(.bold)
                        .foregroundColor(secondaryTextColor)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.bottom, 10)
        .padding(.top, 10)
        .background(backgroundColor)
        .clipped()
    }
    
    private func formattedScore(_ value: Double) -> String {
        // If it's an integer like 7.0, show "7". Otherwise show one decimal "7.3"
        let intVal = Int(value.rounded())
        if abs(value - Double(intVal)) < 0.05 {
            return "\(intVal)"
        } else {
            return String(format: "%.1f", value)
        }
    }
}

// MARK: - Widget

struct NorlysPositionWidget: Widget {
    let kind = "NorlysPositionWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NorlysPositionProvider()) { entry in
            NorlysPositionEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Strong aurora above me Widget")
        .description("Displays the probability of strong aurora above the user’s current location.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Preview

#Preview("Small Widget", as: .systemSmall) {
    NorlysPositionWidget()
} timeline: {
    let now = Date()
    let entry = NorlysPositionEntry(
        date: now,
        location: CLLocationCoordinate2D(latitude: 59.91, longitude: 10.75),
        scoreDiv10: 6.8,
        isError: false
    )
    return [entry]
}
