import XCTest
@testable import FocusCore

final class EngineTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    // 2024-01-08 is a Monday (weekday 2), 2024-01-07 a Sunday (weekday 1).
    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2024, month: 1, day: day, hour: hour, minute: minute))!
    }

    func state(mode: Mode? = nil) -> (AppState, Mode) {
        var s = AppState.seeded()
        let m = mode ?? s.modes[0]
        s.modes = [m]
        return (s, m)
    }

    func session(_ s: inout AppState, mode: Mode, from start: Date, to end: Date) {
        s.sessions.append(Session(modeID: mode.id, start: start, end: end))
    }

    func testScheduleWrapsPastMidnight() {
        let (s0, m) = state()
        var s = s0
        s.schedules = [Schedule(modeID: m.id, weekdays: [2], startMinute: 22 * 60, endMinute: 2 * 60)]
        XCTAssertEqual(Engine.activeBlocks(s, now: date(9, 1), calendar: calendar).count, 1)
        XCTAssertEqual(Engine.activeBlocks(s, now: date(8, 23), calendar: calendar).count, 1)
        XCTAssertEqual(Engine.activeBlocks(s, now: date(9, 3), calendar: calendar).count, 0)
        XCTAssertEqual(Engine.activeBlocks(s, now: date(7, 23), calendar: calendar).count, 0)
    }

    func testDomainSuffixMatching() {
        var (s, m) = state()
        m.domains = ["youtube.com"]
        s.modes = [m]
        session(&s, mode: m, from: date(8, 9), to: date(8, 10))
        let now = date(8, 9, 30)
        XCTAssertNotEqual(Engine.decision(forHost: "youtube.com", s, now: now), .allowed)
        XCTAssertNotEqual(Engine.decision(forHost: "www.youtube.com", s, now: now), .allowed)
        XCTAssertEqual(Engine.decision(forHost: "notyoutube.com", s, now: now), .allowed)
        XCTAssertEqual(Engine.decision(forHost: "youtube.com.evil.io", s, now: now), .allowed)
    }

    func testBlockedDecisionReportsBlockEnd() {
        var (s, m) = state()
        m.domains = ["x.com"]
        s.modes = [m]
        session(&s, mode: m, from: date(8, 9), to: date(8, 10))
        let now = date(8, 9, 30)
        XCTAssertEqual(Engine.decision(forHost: "x.com", s, now: now), .blocked(until: date(8, 10)))
        XCTAssertEqual(Engine.decision(forApp: "com.hnc.Discord", s, now: now), .blocked(until: date(8, 10)))
        XCTAssertEqual(Engine.decision(forApp: "com.example.other", s, now: now), .allowed)
        XCTAssertEqual(Engine.decision(forHost: "x.com", s, now: date(8, 10)), .allowed)
    }

    func testEmergencyOverridesActiveBlock() {
        var (s, m) = state()
        m.domains = ["x.com"]
        s.modes = [m]
        session(&s, mode: m, from: date(8, 9), to: date(8, 10))
        let now = date(8, 9, 1)

        Engine.applyEmergency(&s, now: now)
        let later = date(8, 9, 2)
        XCTAssertFalse(Engine.isBlockActive(s, now: later))
        XCTAssertEqual(Engine.decision(forHost: "x.com", s, now: later), .allowed)
        XCTAssertNil(s.emergency)
    }

    func testValidateEditRejectsRemovalDuringBlock() {
        var (s, m) = state()
        m.domains = ["x.com", "reddit.com"]
        s.modes = [m]
        session(&s, mode: m, from: date(8, 9), to: date(8, 10))
        let now = date(8, 9, 30)

        var removed = s
        removed.modes[0].domains = ["x.com"]
        XCTAssertFalse(Engine.validateEdit(old: s, new: removed, now: now))

        var added = s
        added.modes[0].domains.append("news.com")
        XCTAssertTrue(Engine.validateEdit(old: s, new: added, now: now))

        var shortened = s
        shortened.sessions[0].end = date(8, 9, 15)
        XCTAssertFalse(Engine.validateEdit(old: s, new: shortened, now: now))

        XCTAssertTrue(Engine.validateEdit(old: s, new: removed, now: date(8, 11)))
    }

    func testEmergencyPhraseFormat() {
        let phrase = Engine.emergencyPhrase(length: 12)
        XCTAssertEqual(phrase.split(separator: " ").map(\.count), [5, 5, 2])
        XCTAssertTrue(phrase.allSatisfy { $0 == " " || $0.isLetter || $0.isNumber })
    }
}
