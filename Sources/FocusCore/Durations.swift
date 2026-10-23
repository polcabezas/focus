import Foundation

/// Pure helpers for choosing a session length: parsing typed input, stepping, formatting and clock-time maths.
public enum Durations {
    /// A session can be 1 minute to 23 h 59 min long.
    public static let valid = 1...1439
    /// The +/- buttons stop at 5 minutes and 23 h 55 minutes.
    public static let stepRange = 5...1435

    private static let pattern = try! NSRegularExpression(
        pattern: #"^(?:(\d+)\s*h(?:ours?|rs?)?)?\s*(?:(\d+)\s*(?:m|min|mins|minutes?)?)?$"#)

    /// Accepts "90", "1:30", "1h30", "1h 30m", "1 h 30 min", "2h", "45m". Returns minutes, or nil if invalid or out of `valid`.
    public static func parse(_ text: String) -> Int? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }
        let minutes: Int
        if s.contains(":") {
            let parts = s.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let h = number(parts[0]), let m = number(parts[1]), m < 60 else { return nil }
            minutes = h * 60 + m
        } else {
            guard let match = pattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
            let hours = group(match, 1, in: s), mins = group(match, 2, in: s)
            guard hours != nil || mins != nil else { return nil }
            minutes = (hours ?? 0) * 60 + (mins ?? 0)
        }
        return valid.contains(minutes) ? minutes : nil
    }

    /// "45 min", "1 h", "1 h 30 min".
    public static func format(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h) h" }
        return "\(h) h \(m) min"
    }

    /// The +/- step: 5 min up to 1 h, 15 min from 1 h up, kept inside `stepRange` and symmetric (60 up is 75, 75 down is 60).
    public static func stepped(_ minutes: Int, up: Bool) -> Int {
        if up {
            let step = minutes < 60 ? 5 : 15
            let next = (minutes / step + 1) * step
            return next > stepRange.upperBound ? max(minutes, stepRange.upperBound) : next
        }
        guard minutes > stepRange.lowerBound else { return minutes }
        let step = minutes <= 60 ? 5 : 15
        return max(((minutes - 1) / step) * step, stepRange.lowerBound)
    }

    /// Minutes from `now` until the next occurrence of the hour and minute in `clockTime` (tomorrow if that time is not
    /// after now). Rounded up to whole minutes, at least 1.
    public static func minutesUntil(clockTime: Date, now: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: clockTime)
        var target = calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: now) ?? now
        if target <= now {
            target = calendar.date(byAdding: .day, value: 1, to: target) ?? target
        }
        return max(1, Int((target.timeIntervalSince(now) / 60).rounded(.up)))
    }

    /// `date` moved forward to the next multiple of `step` minutes (unchanged if already on one).
    public static func roundedUp(_ date: Date, toMinutes step: Int) -> Date {
        let unit = TimeInterval(step * 60)
        return Date(timeIntervalSince1970: (date.timeIntervalSince1970 / unit).rounded(.up) * unit)
    }

    private static func number(_ part: Substring) -> Int? {
        let t = part.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(t)
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in s: String) -> Int? {
        let r = match.range(at: index)
        guard r.location != NSNotFound, let range = Range(r, in: s) else { return nil }
        return Int(s[range])
    }
}
