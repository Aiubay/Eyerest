import XCTest
@testable import EyeRule

final class BreakInsightsTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return result
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testLegacyHistoryDoesNotInventSkipsOrTime() {
        let insights = BreakInsights(trackingStarted: date(2026, 11, 17))
        let week = insights.week(ending: date(2026, 11, 17), history: ["2026-11-16": 4], calendar: calendar)
        XCTAssertEqual(week.completed, 4)
        XCTAssertEqual(week.skipped, 0)
        XCTAssertEqual(week.seconds, 0)
    }

    func testRollingWeeksIncludeTodayWithoutOverlap() {
        let insights = BreakInsights()
        let history = ["2026-11-17": 1, "2026-11-11": 2, "2026-11-10": 4,
                       "2026-11-04": 8, "2026-11-03": 16, "2026-11-18": 32]
        XCTAssertEqual(insights.week(ending: date(2026, 11, 17), history: history, calendar: calendar).completed, 3)
        XCTAssertEqual(insights.previousWeek(ending: date(2026, 11, 17), history: history, calendar: calendar).completed, 12)
    }

    func testEmptyWeeksHaveZeroTotals() {
        let insights = BreakInsights()
        XCTAssertEqual(insights.week(ending: date(2026, 11, 17), history: [:], calendar: calendar), .init())
        XCTAssertEqual(insights.previousWeek(ending: date(2026, 11, 17), history: [:], calendar: calendar), .init())
    }

    func testWeekCrossesYearBoundary() {
        let insights = BreakInsights()
        let history = ["2027-01-02": 1, "2026-12-27": 2, "2026-12-26": 4]
        XCTAssertEqual(insights.week(ending: date(2027, 1, 2), history: history, calendar: calendar).completed, 3)
        XCTAssertEqual(insights.previousWeek(ending: date(2027, 1, 2), history: history, calendar: calendar).completed, 4)
    }

    func testWeekIncludesLeapDay() {
        let insights = BreakInsights()
        let history = ["2028-03-01": 1, "2028-02-29": 2, "2028-02-24": 4, "2028-02-23": 8]
        XCTAssertEqual(insights.week(ending: date(2028, 3, 1), history: history, calendar: calendar).completed, 7)
    }

    func testWeeksCrossDaylightSavingTransitions() {
        let insights = BreakInsights()
        for end in [date(2026, 3, 10, hour: 0), date(2026, 11, 3, hour: 23)] {
            var history: [String: Int] = [:]
            for offset in 0..<14 {
                let day = calendar.date(byAdding: .day, value: -offset, to: end)!
                history[BreakInsights.dayKey(day, calendar: calendar)] = 1
            }
            XCTAssertEqual(insights.week(ending: end, history: history, calendar: calendar).completed, 7)
            XCTAssertEqual(insights.previousWeek(ending: end, history: history, calendar: calendar).completed, 7)
        }
    }

    func testOnlyRunningBreakSecondsCount() {
        var insights = BreakInsights()
        let now = date(2026, 11, 17)
        insights.advance(on: now, running: true, calendar: calendar)
        insights.beginBreak()
        for _ in 0..<5 { insights.advance(on: now, running: true, calendar: calendar) }
        for _ in 0..<50 { insights.advance(on: now, running: false, calendar: calendar) }
        insights.endBreak(.completed, on: now, calendar: calendar)
        insights.advance(on: now, running: true, calendar: calendar)
        XCTAssertEqual(insights.week(ending: now, history: [:], calendar: calendar).seconds, 5)
        XCTAssertEqual(insights.week(ending: now, history: [:], calendar: calendar).skipped, 0)
    }

    func testSkipAndResetFinalizationOnlyCountsOnce() {
        var insights = BreakInsights()
        let now = date(2026, 11, 17)
        insights.beginBreak()
        insights.advance(on: now, running: true, calendar: calendar)
        XCTAssertTrue(insights.endBreak(.skipped, on: now, calendar: calendar))
        XCTAssertFalse(insights.endBreak(.skipped, on: now, calendar: calendar))
        let week = insights.week(ending: now, history: [:], calendar: calendar)
        XCTAssertEqual(week.skipped, 1)
        XCTAssertEqual(week.seconds, 1)
    }

    func testSnoozeAndQuitPreserveTimeWithoutCountingSkips() {
        var insights = BreakInsights()
        let now = date(2026, 11, 17)
        for outcome in [BreakInsights.Outcome.postponed, .stopped] {
            insights.beginBreak()
            insights.advance(on: now, running: true, calendar: calendar)
            insights.endBreak(outcome, on: now, calendar: calendar)
        }
        let week = insights.week(ending: now, history: [:], calendar: calendar)
        XCTAssertEqual(week.seconds, 2)
        XCTAssertEqual(week.skipped, 0)
    }

    func testRepeatedBeginDoesNotResetBreakTime() {
        var insights = BreakInsights()
        let now = date(2026, 11, 17)
        insights.beginBreak()
        insights.advance(on: now, running: true, calendar: calendar)
        insights.beginBreak()
        insights.advance(on: now, running: true, calendar: calendar)
        insights.endBreak(.skipped, on: now, calendar: calendar)
        XCTAssertEqual(insights.week(ending: now, history: [:], calendar: calendar).seconds, 2)
        XCTAssertEqual(insights.week(ending: now, history: [:], calendar: calendar).skipped, 1)
    }

    func testBreakCrossingMidnightAttributesSecondsByDay() {
        var insights = BreakInsights()
        insights.beginBreak()
        insights.advance(on: date(2026, 11, 17, hour: 23, minute: 59), running: true, calendar: calendar)
        insights.advance(on: date(2026, 11, 18, hour: 0), running: true, calendar: calendar)
        insights.endBreak(.skipped, on: date(2026, 11, 18), calendar: calendar)
        XCTAssertEqual(insights.days["2026-11-17"], .init(skipped: 0, seconds: 1))
        XCTAssertEqual(insights.days["2026-11-18"], .init(skipped: 1, seconds: 1))
    }

    func testPersistencePreservesMetricsButNotActiveSession() throws {
        let now = date(2026, 11, 17)
        var insights = BreakInsights(trackingStarted: now)
        insights.beginBreak()
        insights.advance(on: now, running: true, calendar: calendar)
        let decoded = try JSONDecoder().decode(BreakInsights.self, from: JSONEncoder().encode(insights))
        XCTAssertEqual(decoded.days, insights.days)
        XCTAssertEqual(decoded.trackingStarted, now)
        XCTAssertFalse(decoded.breakInProgress)
    }
}

final class DimScreenPolicyTests: XCTestCase {
    func testOnlyAnEligibleOptInRunningBreakMayDim() {
        XCTAssertTrue(DimScreenPolicy.allowsPresentation(enabled: true, resting: true, running: true,
                                                       locked: false, sleeping: false, busy: false, fullscreen: false))
        let denied: [(Bool, Bool, Bool, Bool, Bool, Bool, Bool?)] = [
            (false, true, true, false, false, false, false),
            (true, false, true, false, false, false, false),
            (true, true, false, false, false, false, false),
            (true, true, true, true, false, false, false),
            (true, true, true, false, true, false, false),
            (true, true, true, false, false, true, false),
            (true, true, true, false, false, false, true),
            (true, true, true, false, false, false, nil)
        ]
        for (enabled, resting, running, locked, sleeping, busy, fullscreen) in denied {
            XCTAssertFalse(DimScreenPolicy.allowsPresentation(enabled: enabled, resting: resting, running: running,
                                                            locked: locked, sleeping: sleeping, busy: busy, fullscreen: fullscreen))
        }
    }

    func testFullscreenDetectionUsesBoundsAndSmallTolerance() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertTrue(DimScreenPolicy.coversScreen(screen, screen: screen))
        XCTAssertTrue(DimScreenPolicy.coversScreen(screen.insetBy(dx: 1, dy: 1), screen: screen))
        XCTAssertFalse(DimScreenPolicy.coversScreen(CGRect(x: 0, y: 25, width: 1440, height: 850), screen: screen))
        XCTAssertFalse(DimScreenPolicy.coversScreen(CGRect(x: 1440, y: 0, width: 1440, height: 900), screen: screen))
    }
}
