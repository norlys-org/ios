//
//  WebcamIntent.swift
//  norlys
//
//  Created by Hugo Lageneste on 11/03/2025.
//

import AppIntents
import SwiftUI

struct Webcam: AppEntity {
    var id: String
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Webcam location"
    static var defaultQuery = WebcamQuery()
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
    
    static let allCases: [Webcam] = [
        Webcam(id: "tromso", name: "Tromsø")
    ]
}

struct WebcamQuery: EntityQuery {
    func entities(for identifiers: [Webcam.ID]) async throws -> [Webcam] {
        Webcam.allCases.filter { identifiers.contains($0.id) }
    }
    
    func suggestedEntities() async throws -> some ResultsCollection {
        Webcam.allCases
    }
    
    func defaultResult() async -> DefaultValue? {
        Webcam.allCases.first
    }
}

struct SelectWebcamIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "ttt"
    static var description: IntentDescription = IntentDescription("d")
    
    @Parameter(title: "Webcam location")
    var webcam: Webcam
}
