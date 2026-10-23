import Foundation

public struct ActiveBlock: Equatable {
    public var mode: Mode
    public var start: Date
    public var end: Date

    public init(mode: Mode, start: Date, end: Date) {
        self.mode = mode; self.start = start; self.end = end
    }
}

public enum Decision: Equatable {
    case allowed
    case blocked(until: Date)
}

public enum Engine {
    public static func activeBlocks(_ s: AppState, now: Date, calendar: Calendar = .current) -> [ActiveBlock] {
        var blocks: [ActiveBlock] = []
        for session in s.sessions where session.start <= now && now < session.end {
            guard let mode = s.modes.first(where: { $0.id == session.modeID }) else { continue }
            blocks.append(ActiveBlock(mode: mode, start: session.start, end: session.end))
        }
        for schedule in s.schedules where schedule.enabled {
            guard let occurrence = occurrence(of: schedule, now: now, calendar: calendar),
                  let mode = s.modes.first(where: { $0.id == schedule.modeID }) else { continue }
            blocks.append(ActiveBlock(mode: mode, start: occurrence.start, end: occurrence.end))
        }
        return blocks.filter { !isOverridden($0.start, s, now: now) }
    }

    public static func isBlockActive(_ s: AppState, now: Date) -> Bool {
        !activeBlocks(s, now: now).isEmpty
    }

    public static func blockedDomains(_ s: AppState, now: Date) -> [String] {
        unique(activeBlocks(s, now: now).flatMap { $0.mode.domains.map { $0.lowercased() } })
    }

    public static func blockedApps(_ s: AppState, now: Date) -> [String] {
        unique(activeBlocks(s, now: now).flatMap { $0.mode.appBundleIDs })
    }

    public static func decision(forHost host: String, _ s: AppState, now: Date) -> Decision {
        untilDecision(activeBlocks(s, now: now).filter { block in
            block.mode.domains.contains { domainMatches(host, $0) }
        })
    }

    public static func decision(forApp bundleID: String, _ s: AppState, now: Date) -> Decision {
        untilDecision(activeBlocks(s, now: now).filter { $0.mode.appBundleIDs.contains(bundleID) })
    }

    // Emergency exit ends running sessions now and ignores the blocks active at this moment until they would have ended.
    public static func applyEmergency(_ s: inout AppState, now: Date) {
        var withoutOverride = s
        withoutOverride.emergencyAt = nil
        withoutOverride.overrideUntil = nil
        s.emergencyAt = now
        s.overrideUntil = activeBlocks(withoutOverride, now: now).map(\.end).max() ?? now
        for i in s.sessions.indices where s.sessions[i].start <= now && now < s.sessions[i].end {
            s.sessions[i].end = now
        }
        s.emergency = nil
    }

    public static func validateEdit(old: AppState, new: AppState, now: Date) -> Bool {
        let blocks = activeBlocks(old, now: now)
        if blocks.isEmpty { return true }

        let oldSettings = old.settings, newSettings = new.settings
        if newSettings.emergencyEnabled != oldSettings.emergencyEnabled
            || newSettings.emergencyWaitMinutes != oldSettings.emergencyWaitMinutes
            || newSettings.emergencyPhraseLength != oldSettings.emergencyPhraseLength
            || newSettings.knownBrowsers != oldSettings.knownBrowsers
            || newSettings.supportedBrowsers != oldSettings.supportedBrowsers {
            return false
        }

        for block in blocks {
            guard let mode = new.modes.first(where: { $0.id == block.mode.id }),
                  Set(block.mode.domains).isSubset(of: mode.domains),
                  Set(block.mode.appBundleIDs).isSubset(of: mode.appBundleIDs) else { return false }
        }

        for session in old.sessions where session.start <= now && now < session.end {
            guard let updated = new.sessions.first(where: { $0.id == session.id }), updated.end >= session.end else {
                return false
            }
        }

        for schedule in old.schedules where schedule.enabled {
            guard let occurrence = occurrence(of: schedule, now: now, calendar: .current),
                  !isOverridden(occurrence.start, old, now: now) else { continue }
            guard let updated = new.schedules.first(where: { $0.id == schedule.id }), updated == schedule else {
                return false
            }
        }
        return true
    }

    public static func emergencyPhrase(length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let chars = (0..<max(length, 0)).map { _ in String(alphabet.randomElement()!) }
        return stride(from: 0, to: chars.count, by: 5)
            .map { chars[$0..<min($0 + 5, chars.count)].joined() }
            .joined(separator: " ")
    }

    // MARK: - Helpers

    private static func occurrence(of schedule: Schedule, now: Date, calendar: Calendar) -> (start: Date, end: Date)? {
        let today = calendar.startOfDay(for: now)
        let duration = schedule.endMinute > schedule.startMinute
            ? schedule.endMinute - schedule.startMinute
            : 1440 - schedule.startMinute + schedule.endMinute
        for dayOffset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today),
                  schedule.weekdays.contains(calendar.component(.weekday, from: day)),
                  let start = calendar.date(byAdding: .minute, value: schedule.startMinute, to: day),
                  let end = calendar.date(byAdding: .minute, value: duration, to: start),
                  start <= now, now < end else { continue }
            return (start, end)
        }
        return nil
    }

    private static func isOverridden(_ start: Date, _ s: AppState, now: Date) -> Bool {
        guard let at = s.emergencyAt, let until = s.overrideUntil, now < until else { return false }
        return start <= at
    }

    private static func domainMatches(_ host: String, _ domain: String) -> Bool {
        let h = host.lowercased(), d = domain.lowercased()
        return h == d || h.hasSuffix("." + d)
    }

    private static func untilDecision(_ matching: [ActiveBlock]) -> Decision {
        matching.map(\.end).max().map { .blocked(until: $0) } ?? .allowed
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
