import XCTest
@testable import FocusCore

final class DurationsTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    // 2024-01-08 (day 8) in UTC.
    func date(_ hour: Int, _ minute: Int = 0, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2024, month: 1, day: 8, hour: hour, minute: minute, second: second))!
    }

    func testParsesPlainMinutes() {
        XCTAssertEqual(Durations.parse("90"), 90)
        XCTAssertEqual(Durations.parse(" 45 "), 45)
        XCTAssertEqual(Durations.parse("5"), 5)
    }

    func testParsesClockStyle() {
        XCTAssertEqual(Durations.parse("1:30"), 90)
        XCTAssertEqual(Durations.parse("0:05"), 5)
        XCTAssertNil(Durations.parse("1:60"))
        XCTAssertNil(Durations.parse(":30"))
    }

    func testParsesHoursAndMinutes() {
        for text in ["1h30", "1h 30m", "1h30m", "1 h 30 min", "1 hour 30 minutes"] {
            XCTAssertEqual(Durations.parse(text), 90, text)
        }
    }

    func testParsesSingleUnits() {
        XCTAssertEqual(Durations.parse("2h"), 120)
        XCTAssertEqual(Durations.parse("2 hours"), 120)
        XCTAssertEqual(Durations.parse("45m"), 45)
        XCTAssertEqual(Durations.parse("45 min"), 45)
    }

    func testRejectsInvalidInput() {
        for text in ["", "   ", "0", "abc", "h", "1440", "1.5h", "-5", "10x", "1:2:3"] {
            XCTAssertNil(Durations.parse(text), text)
        }
    }

    func testFormats() {
        XCTAssertEqual(Durations.format(45), "45 min")
        XCTAssertEqual(Durations.format(60), "1 h")
        XCTAssertEqual(Durations.format(90), "1 h 30 min")
        XCTAssertEqual(Durations.format(1439), "23 h 59 min")
    }

    func testSteppingUsesFiveMinutesUnderAnHourAndFifteenFromAnHour() {
        XCTAssertEqual(Durations.stepped(55, up: true), 60)
        XCTAssertEqual(Durations.stepped(60, up: true), 75)
        XCTAssertEqual(Durations.stepped(60, up: false), 55)
        XCTAssertEqual(Durations.stepped(75, up: false), 60)
        XCTAssertEqual(Durations.stepped(1435, up: true), 1435)
        XCTAssertEqual(Durations.stepped(1430, up: true), 1435)
        XCTAssertEqual(Durations.stepped(1435, up: false), 1425)
    }

    func testSteppingStaysAtFiveMinutesMinimum() {
        XCTAssertEqual(Durations.stepped(5, up: false), 5)
        XCTAssertEqual(Durations.stepped(6, up: false), 5)
        XCTAssertEqual(Durations.stepped(1, up: true), 5)
    }

    func testMinutesUntilRoundsUpToWholeMinutes() {
        XCTAssertEqual(Durations.minutesUntil(clockTime: date(18, 46), now: date(17, 47), calendar: calendar), 59)
        XCTAssertEqual(Durations.minutesUntil(clockTime: date(18, 46), now: date(17, 47, second: 30), calendar: calendar), 59)
        XCTAssertEqual(Durations.minutesUntil(clockTime: date(17, 48), now: date(17, 47, second: 30), calendar: calendar), 1)
    }

    func testMinutesUntilPastOrCurrentTimeMeansTomorrow() {
        XCTAssertEqual(Durations.minutesUntil(clockTime: date(17, 0), now: date(18, 0), calendar: calendar), 23 * 60)
        XCTAssertEqual(Durations.minutesUntil(clockTime: date(17, 47), now: date(17, 47), calendar: calendar), 24 * 60)
    }

    func testRoundedUpToStep() {
        XCTAssertEqual(Durations.roundedUp(date(18, 47), toMinutes: 5), date(18, 50))
        XCTAssertEqual(Durations.roundedUp(date(18, 50), toMinutes: 5), date(18, 50))
        XCTAssertEqual(Durations.roundedUp(date(18, 47, second: 30), toMinutes: 5), date(18, 50))
    }
}
