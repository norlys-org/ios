//
//  AuroraGlobeIntent.swift
//  norlysWidget
//
//  Configuration of the aurora globe widget: what the globe is turned to face.
//

import AppIntents

/// GlobeCentre: What the globe faces. Each hemisphere is shown centred on its geomagnetic pole, which
/// its auroral oval rings.
enum GlobeCentre: String, AppEnum {
    case location
    case north
    case south

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Centre"
    static var caseDisplayRepresentations: [GlobeCentre: DisplayRepresentation] = [
        .location: "Current location",
        .north: "Northern hemisphere",
        .south: "Southern hemisphere"
    ]

    /// The point the globe is turned to. Without the reader's position, the current location falls back
    /// on the website's opening view, as the website itself does.
    func point(userLocation: GeoPoint?) -> GeoPoint {
        switch self {
        case .location: return userLocation ?? GeoPoint(lon: -50, lat: 67)
        case .north: return GlobeDensity.northGeomagneticPole
        case .south: return GlobeDensity.southGeomagneticPole
        }
    }
}

struct SelectGlobeConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Aurora Globe Configuration"
    static var description: IntentDescription = IntentDescription("Choose what the aurora globe is centred on")

    @Parameter(title: "Centre on", default: .location) var centre: GlobeCentre
}
