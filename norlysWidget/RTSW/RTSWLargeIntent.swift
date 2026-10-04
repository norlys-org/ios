//
//  RTSWLargeIntent.swift
//  norlysWidget
//
//  Configuration of the large solar wind widget: the satellite and time period to
//  show, and which of the optional components to draw. The choices mirror the
//  selects and component toggles on norlys.live/rtsw.
//

import AppIntents

/// RTSWSatellite: Which satellite's data is drawn in colour. The others are drawn in grey behind it.
enum RTSWSatellite: String, AppEnum {
    case auto
    case solar1
    case dscovr
    case ace
    case imap
    case stereo

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Satellite"
    static var caseDisplayRepresentations: [RTSWSatellite: DisplayRepresentation] = [
        .auto: "Auto",
        .solar1: "SOLAR 1",
        .dscovr: "DSCOVR",
        .ace: "ACE",
        .imap: "IMAP",
        .stereo: "STEREO A"
    ]

    /// Source code of the chosen satellite, nil for auto (whichever NOAA marks as active).
    var sourceCode: Int? {
        switch self {
        case .auto: return nil
        case .solar1: return RTSWSourceCode.solar1
        case .dscovr: return RTSWSourceCode.dscovr
        case .ace: return RTSWSourceCode.ace
        case .imap: return RTSWSourceCode.imap
        case .stereo: return RTSWSourceCode.stereo
        }
    }

    /// IMAP and STEREO come from feeds that are only practical to fetch a day of in a widget
    /// (the website also stops IMAP at a day).
    var longestTimespan: RTSWTimespan {
        switch self {
        case .imap, .stereo: return .oneDay
        default: return .fiveYears
        }
    }
}

/// RTSWTimespan: How far back the widget reaches. Raw values follow the website's span keys.
enum RTSWTimespan: String, AppEnum {
    case twoHours = "2-hour"
    case sixHours = "6-hour"
    case oneDay = "1-day"
    case threeDays = "3-day"
    case sevenDays = "7-day"
    case thirtyDays = "30-day"
    case fiftyFourDays = "54-day"
    case oneYear = "1-year"
    case fiveYears = "5-year"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Time period"
    static var caseDisplayRepresentations: [RTSWTimespan: DisplayRepresentation] = [
        .twoHours: "2 hours",
        .sixHours: "6 hours",
        .oneDay: "24 hours",
        .threeDays: "3 days",
        .sevenDays: "7 days",
        .thirtyDays: "30 days",
        .fiftyFourDays: "54 days",
        .oneYear: "1 year",
        .fiveYears: "5 years"
    ]

    var duration: TimeInterval {
        let hour: TimeInterval = 3600
        switch self {
        case .twoHours: return 2 * hour
        case .sixHours: return 6 * hour
        case .oneDay: return 24 * hour
        case .threeDays: return 3 * 24 * hour
        case .sevenDays: return 7 * 24 * hour
        case .thirtyDays: return 30 * 24 * hour
        case .fiftyFourDays: return 54 * 24 * hour
        case .oneYear: return 365 * 24 * hour
        case .fiveYears: return 5 * 365 * 24 * hour
        }
    }

    /// The HAPI dataset read for this span, as the website picks it. Two hours would be
    /// one-second data there, which has no plasma and is too heavy for a widget, so it
    /// stays on one-minute data like six hours and a day.
    var cadence: HAPI.Cadence {
        switch self {
        case .twoHours, .sixHours, .oneDay: return .pt1m
        case .threeDays, .sevenDays: return .pt5m
        case .thirtyDays: return .pt30m
        case .fiftyFourDays: return .pt1h
        case .oneYear: return .pt6h
        case .fiveYears: return .pt1d
        }
    }

    /// Spacing of the samples, in seconds.
    var resolution: TimeInterval {
        switch cadence {
        case .pt1m: return 60
        case .pt5m: return 5 * 60
        case .pt30m: return 30 * 60
        case .pt1h: return 3600
        case .pt6h: return 6 * 3600
        case .pt1d: return 24 * 3600
        }
    }

    /// How often the widget asks to be reloaded. The website re-reads the feed as often as the data
    /// changes (once a minute at best) and at least every quarter of an hour, but WidgetKit reloads a
    /// widget every five minutes at most, so asking for more would only count down to nothing.
    var reloadInterval: TimeInterval {
        min(max(resolution, 5 * 60), 15 * 60)
    }

    /// The shorter of two spans.
    func clamped(to longest: RTSWTimespan) -> RTSWTimespan {
        duration <= longest.duration ? self : longest
    }
}

struct SelectRTSWConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Solar Wind Configuration"
    static var description: IntentDescription = IntentDescription("Configure the satellite, time period and components shown by the solar wind widget")

    @Parameter(title: "Satellite", default: .auto) var satellite: RTSWSatellite
    @Parameter(title: "Time period", default: .oneDay) var timespan: RTSWTimespan
    @Parameter(title: "Show By", default: false) var showBy: Bool
    @Parameter(title: "Show Bz", default: true) var showBz: Bool
    @Parameter(title: "Show Phi", default: true) var showPhi: Bool
    @Parameter(title: "Show Theta", default: false) var showTheta: Bool
}
