import Foundation

public enum TargetKind: String, Codable { case domain, app }

public struct Mode: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var domains: [String]
    public var appBundleIDs: [String]

    public init(id: UUID = UUID(), name: String, symbol: String, domains: [String] = [], appBundleIDs: [String] = []) {
        self.id = id; self.name = name; self.symbol = symbol; self.domains = domains; self.appBundleIDs = appBundleIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "circle"
        domains = try c.decodeIfPresent([String].self, forKey: .domains) ?? []
        appBundleIDs = try c.decodeIfPresent([String].self, forKey: .appBundleIDs) ?? []
    }
}

public struct Schedule: Codable, Identifiable, Equatable {
    public var id: UUID
    public var modeID: UUID
    public var weekdays: Set<Int>
    public var startMinute: Int
    public var endMinute: Int
    public var enabled: Bool

    public init(id: UUID = UUID(), modeID: UUID, weekdays: Set<Int>, startMinute: Int, endMinute: Int,
                enabled: Bool = true) {
        self.id = id; self.modeID = modeID; self.weekdays = weekdays; self.startMinute = startMinute
        self.endMinute = endMinute; self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        modeID = try c.decode(UUID.self, forKey: .modeID)
        weekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? []
        startMinute = try c.decodeIfPresent(Int.self, forKey: .startMinute) ?? 0
        endMinute = try c.decodeIfPresent(Int.self, forKey: .endMinute) ?? 0
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

public struct Session: Codable, Identifiable, Equatable {          // manual, ad-hoc block
    public var id: UUID
    public var modeID: UUID
    public var start: Date
    public var end: Date

    public init(id: UUID = UUID(), modeID: UUID, start: Date, end: Date) {
        self.id = id; self.modeID = modeID; self.start = start; self.end = end
    }

    // Missing dates default to distantPast, so an incomplete session is never an active block.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        modeID = try c.decode(UUID.self, forKey: .modeID)
        start = try c.decodeIfPresent(Date.self, forKey: .start) ?? .distantPast
        end = try c.decodeIfPresent(Date.self, forKey: .end) ?? .distantPast
    }
}

public struct Settings: Codable, Equatable {
    public var emergencyEnabled = true
    public var emergencyWaitMinutes = 15
    public var emergencyPhraseLength = 200
    // Browser bundle ids allowed during a session. Only the keys are used; values are ignored (kept for decoding).
    public var supportedBrowsers: [String: String] = ["company.thebrowser.Browser": "", "com.officecommun.search": ""]
    public var knownBrowsers: [String] = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.google.Chrome.canary", "org.chromium.Chromium", "com.brave.Browser",
        "com.microsoft.edgemac", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
        "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "com.kagi.kagimacOS", "app.zen-browser.zen",
        "company.thebrowser.dia", "ai.perplexity.comet",
        "company.thebrowser.Browser", "com.officecommun.search",
    ]

    public init() {}

    // Every field falls back to its default, so a state.json written by an older version still decodes.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        emergencyEnabled = try c.decodeIfPresent(Bool.self, forKey: .emergencyEnabled) ?? d.emergencyEnabled
        emergencyWaitMinutes = try c.decodeIfPresent(Int.self, forKey: .emergencyWaitMinutes) ?? d.emergencyWaitMinutes
        emergencyPhraseLength = try c.decodeIfPresent(Int.self, forKey: .emergencyPhraseLength) ?? d.emergencyPhraseLength
        supportedBrowsers = try c.decodeIfPresent([String: String].self, forKey: .supportedBrowsers) ?? d.supportedBrowsers
        knownBrowsers = try c.decodeIfPresent([String].self, forKey: .knownBrowsers) ?? d.knownBrowsers
    }
}

public struct EmergencyRequest: Codable, Equatable {
    public var requestedAt: Date
    public var phrase: String

    public init(requestedAt: Date, phrase: String) {
        self.requestedAt = requestedAt; self.phrase = phrase
    }
}

public struct ClockAnchor: Codable, Equatable {
    public var trusted: Date
    public var monotonicNanos: UInt64

    public init(trusted: Date, monotonicNanos: UInt64) {
        self.trusted = trusted; self.monotonicNanos = monotonicNanos
    }
}

public struct AppState: Codable, Equatable {
    public var modes: [Mode]
    public var schedules: [Schedule]
    public var sessions: [Session]
    public var settings: Settings
    public var emergency: EmergencyRequest?        // pending emergency exit
    public var emergencyAt: Date?
    public var overrideUntil: Date?                // blocks active at emergencyAt are ignored until overrideUntil
    public var clock: ClockAnchor?

    public init(modes: [Mode] = [], schedules: [Schedule] = [], sessions: [Session] = [],
                settings: Settings = Settings(), emergency: EmergencyRequest? = nil,
                emergencyAt: Date? = nil, overrideUntil: Date? = nil, clock: ClockAnchor? = nil) {
        self.modes = modes; self.schedules = schedules; self.sessions = sessions
        self.settings = settings; self.emergency = emergency
        self.emergencyAt = emergencyAt; self.overrideUntil = overrideUntil; self.clock = clock
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modes = try c.decodeIfPresent([Mode].self, forKey: .modes) ?? Self.seeded().modes
        schedules = try c.decodeIfPresent([Schedule].self, forKey: .schedules) ?? []
        sessions = try c.decodeIfPresent([Session].self, forKey: .sessions) ?? []
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        emergency = try c.decodeIfPresent(EmergencyRequest.self, forKey: .emergency)
        emergencyAt = try c.decodeIfPresent(Date.self, forKey: .emergencyAt)
        overrideUntil = try c.decodeIfPresent(Date.self, forKey: .overrideUntil)
        clock = try c.decodeIfPresent(ClockAnchor.self, forKey: .clock)
    }

    public static func seeded() -> AppState {
        let social = ["youtube.com", "x.com", "twitter.com", "instagram.com", "tiktok.com", "reddit.com",
                      "facebook.com", "netflix.com", "twitch.tv"]
        let modes = [
            Mode(name: "Work", symbol: "briefcase.fill",
                 domains: social + ["news.ycombinator.com", "cnn.com", "bbc.com", "nytimes.com"],
                 appBundleIDs: ["com.hnc.Discord", "com.spotify.client"]),
            Mode(name: "Personal", symbol: "house.fill", domains: social),
            Mode(name: "Training", symbol: "figure.run", domains: social,
                 appBundleIDs: ["com.spotify.client"]),
        ]
        return AppState(modes: modes)
    }
}

public enum HistoryEvent: Codable {
    case sessionStarted(modeID: UUID, minutes: Int)
    case emergencyUsed(reason: String)
    case editRejected(reason: String)
}
