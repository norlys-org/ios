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
        Webcam(id: "svalbard", name: "Longyearbyen"),
        Webcam(id: "skibotn", name: "Skibotn"),
        Webcam(id: "sodankyla", name: "Sodankylä"),
        Webcam(id: "hankasalmi", name: "Hankasalmi"),
        Webcam(id: "ramfjord", name: "Ramfjord"),
        Webcam(id: "pori", name: "Pori"),
        Webcam(id: "kiruna", name: "Kiruna"),
        Webcam(id: "fairbanks", name: "Fairbanks"),
        Webcam(id: "calgary", name: "Calgary"),
        Webcam(id: "kilpisjarvi", name: "Kilpisjarvi"),
        Webcam(id: "kevo", name: "Kevo"),
        Webcam(id: "muonio", name: "Muonio"),
        Webcam(id: "athabasca", name: "Athabasca"),
        Webcam(id: "yellowknife", name: "Yellowknife"),
        Webcam(id: "glacier-np", name: "Glacier National Park"),
        Webcam(id: "maine", name: "Millinocket"),
        Webcam(id: "setermoen", name: "Setermoen"),
        Webcam(id: "stokmarknes", name: "Stokmarknes"),
        Webcam(id: "bodo", name: "Bodø"),
        Webcam(id: "narvik", name: "Narvik"),
        Webcam(id: "saltfjellet", name: "Saltfjellet"),
        Webcam(id: "trofors", name: "Trofors"),
        Webcam(id: "lom", name: "Fossbergom"),
        Webcam(id: "oslo", name: "Oslo"),
        Webcam(id: "tromsonorth", name: "Tromsø (North)"),
        Webcam(id: "tromsowest", name: "Tromsø (West)"),
        Webcam(id: "tromsosouth", name: "Tromsø (South)"),
        Webcam(id: "levi", name: "Levi"),
        Webcam(id: "pyhatunturi", name: "Pyhätunturi"),
        Webcam(id: "rovaniemi", name: "Rovaniemi"),
        Webcam(id: "metsahovi", name: "Metsähovi"),
        Webcam(id: "nyrola", name: "Nyrölä"),
        Webcam(id: "abisko", name: "Abisko"),
        Webcam(id: "akureyri", name: "Akureyri"),
        Webcam(id: "aykhal", name: "Aikal"),
        Webcam(id: "vorkuta", name: "Vorkuta"),
        Webcam(id: "bluff", name: "Bluff"),
        Webcam(id: "kingston", name: "Kingston"),
        Webcam(id: "dunedin", name: "Dunedin"),
        Webcam(id: "troll", name: "Troll Station"),
        Webcam(id: "mcmurdo", name: "McMurdo Station"),
        Webcam(id: "davis", name: "Davis Station"),
        Webcam(id: "toolik", name: "Toolik Lake")
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
