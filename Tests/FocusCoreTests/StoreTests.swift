import XCTest
@testable import FocusCore

final class StoreTests: XCTestCase {
    func testSettingsWithOnlyOneFieldDecodesDefaultsForTheRest() throws {
        let json = Data(#"{"emergencyWaitMinutes":5}"#.utf8)
        let settings = try JSONDecoder().decode(Settings.self, from: json)
        XCTAssertEqual(settings.emergencyWaitMinutes, 5)
        XCTAssertEqual(settings.emergencyPhraseLength, Settings().emergencyPhraseLength)
        XCTAssertEqual(settings.knownBrowsers, Settings().knownBrowsers)
    }

    func testAppStateWithMissingFieldsKeepsWhatIsPresent() throws {
        let json = Data(#"{"settings":{"emergencyWaitMinutes":3}}"#.utf8)
        let state = try JSONDecoder().decode(AppState.self, from: json)
        XCTAssertEqual(state.settings.emergencyWaitMinutes, 3)
        XCTAssertEqual(state.modes.map(\.name), AppState.seeded().modes.map(\.name))
        XCTAssertNil(state.emergency)
    }

    // state.json files written by older versions still contain these keys (including the removed accent); they must decode and keep the rest.
    func testStateWithRemovedKeysStillDecodes() throws {
        let json = Data(#"""
        {
          "modes": [{"id": "11111111-1111-1111-1111-111111111111", "name": "Work", "symbol": "briefcase.fill",
                     "domains": ["x.com"], "appBundleIDs": []}],
          "schedules": [{"id": "22222222-2222-2222-2222-222222222222", "modeID": "11111111-1111-1111-1111-111111111111",
                         "weekdays": [2], "startMinute": 540, "endMinute": 1020, "strictness": "hard", "enabled": true}],
          "sessions": [{"id": "33333333-3333-3333-3333-333333333333", "modeID": "11111111-1111-1111-1111-111111111111",
                        "start": 0, "end": 60, "strictness": "purposeful"}],
          "grants": [{"id": "44444444-4444-4444-4444-444444444444", "target": "x.com", "kind": "domain",
                      "justification": "tutorial", "taskMinutes": 30, "start": 0, "end": 60, "status": "active",
                      "visitedURLs": []}],
          "purposefulLockedUntil": 100,
          "settings": {
            "gatekeeper": {"baseURL": "https://example.invalid/v1", "model": "legacy-model", "jsonMode": false},
            "verifier": {"baseURL": "https://example.invalid/v1", "model": "legacy-model-2",
                         "reasoningEffort": "low", "jsonMode": true},
            "accent": "hot pink",
            "dayBoundaryHour": 7,
            "proofTimeoutMinutes": 5,
            "emergencyWaitMinutes": 5
          }
        }
        """#.utf8)
        let state = try JSONDecoder().decode(AppState.self, from: json)
        XCTAssertEqual(state.modes.map(\.domains), [["x.com"]])
        XCTAssertEqual(state.schedules.map(\.startMinute), [540])
        XCTAssertEqual(state.sessions.count, 1)
        XCTAssertEqual(state.settings.emergencyWaitMinutes, 5)
    }
}
