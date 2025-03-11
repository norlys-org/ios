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

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Webcam Location"
    static var defaultQuery = WebcamQuery()
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
    
    static let allCases: [Webcam] = [
        Webcam(id: "skibotn", name: "Skibotn"),
        Webcam(id: "svalbard", name: "Longyearbyen"),
        Webcam(id: "kilpisjarvi", name: "Kilpisjärvi")
    ]
}

struct WebcamQuery: EntityQuery {
    func entities(for identifiers: [Webcam.ID]) async throws -> [Webcam] {
        Webcam.allCases.filter { identifiers.contains($0.id) }
    }
    
    func suggestedEntities() async throws -> [Webcam] {
        Webcam.allCases
    }
    
    func defaultResult() async -> Webcam? {
        Webcam.allCases.first
    }
}

struct SelectWebcamIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Webcam Location"
    static var description: IntentDescription = IntentDescription("Select webcam location")
    
    @Parameter(title: "Webcam location")
    var webcam: Webcam?
}
