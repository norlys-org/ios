//
//  LysIntent.swift
//  norlys
//
//  Created by Hugo on 01.09.2025.
//

import AppIntents
import SwiftUI

struct Timespan: AppEntity {
    var id: String
    var name: String
    var hours: Int

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Timespan"
    static var defaultQuery = TimespanQuery()
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
    
    static let allCases: [Timespan] = [
        Timespan(id: "6h", name: "6 hours", hours: 6),
        Timespan(id: "24h", name: "24 hours", hours: 24),
        Timespan(id: "7d", name: "7 days", hours: 168) // 7 * 24
    ]
}

struct TimespanQuery: EntityQuery {
    func entities(for identifiers: [Timespan.ID]) async throws -> [Timespan] {
        Timespan.allCases.filter { identifiers.contains($0.id) }
    }
    
    func suggestedEntities() async throws -> [Timespan] {
        Timespan.allCases
    }
    
    func defaultResult() async -> Timespan? {
        Timespan.allCases.first // 6 hours by default
    }
}

struct LatitudeZone: AppEntity {
    var id: String
    var name: String
    var apiKey: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Latitude Zone"
    static var defaultQuery = LatitudeZoneQuery()
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
    
    static let allCases: [LatitudeZone] = [
        LatitudeZone(id: "high", name: "High Latitudes", apiKey: "high"),
        LatitudeZone(id: "mid", name: "Mid Latitudes", apiKey: "mid")
    ]
}

struct LatitudeZoneQuery: EntityQuery {
    func entities(for identifiers: [LatitudeZone.ID]) async throws -> [LatitudeZone] {
        LatitudeZone.allCases.filter { identifiers.contains($0.id) }
    }
    
    func suggestedEntities() async throws -> [LatitudeZone] {
        LatitudeZone.allCases
    }
    
    func defaultResult() async -> LatitudeZone? {
        LatitudeZone.allCases.first // High latitudes by default
    }
}

struct SelectLysConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Lys Index Configuration"
    static var description: IntentDescription = IntentDescription("Configure timespan and latitude for Lys Index widget")
    
    @Parameter(title: "Timespan") var timespan: Timespan?
    @Parameter(title: "Latitude") var latitudeZone: LatitudeZone?
}
