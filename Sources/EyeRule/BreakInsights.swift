import Foundation

struct BreakInsights: Codable {
    struct Day: Codable, Equatable {
        var skipped = 0
        var seconds = 0
    }

    struct Week: Equatable {
        var completed = 0
        var skipped = 0
        var seconds = 0
    }

    enum Outcome {
        case completed, skipped, postponed, stopped
    }

    let trackingStarted: Date
    private(set) var days: [String: Day] = [:]
    private(set) var breakInProgress = false

    private enum CodingKeys: String, CodingKey {
        case trackingStarted, days
    }

    init(trackingStarted: Date = Date()) {
        self.trackingStarted = trackingStarted
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    mutating func beginBreak() {
        breakInProgress = true
    }

    mutating func advance(on date: Date, running: Bool, calendar: Calendar = .current) {
        guard breakInProgress, running else { return }
        days[Self.dayKey(date, calendar: calendar), default: Day()].seconds += 1
    }

    @discardableResult
    mutating func endBreak(_ outcome: Outcome, on date: Date, calendar: Calendar = .current) -> Bool {
        guard breakInProgress else { return false }
        breakInProgress = false
        if outcome == .skipped {
            days[Self.dayKey(date, calendar: calendar), default: Day()].skipped += 1
        }
        return true
    }

    func week(ending date: Date, history: [String: Int], calendar: Calendar = .current) -> Week {
        let end = calendar.startOfDay(for: date)
        return (0..<7).reduce(into: Week()) { total, offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: end)!
            let key = Self.dayKey(day, calendar: calendar)
            total.completed += history[key, default: 0]
            total.skipped += days[key]?.skipped ?? 0
            total.seconds += days[key]?.seconds ?? 0
        }
    }

    func previousWeek(ending date: Date, history: [String: Int], calendar: Calendar = .current) -> Week {
        let previousEnd = calendar.date(byAdding: .day, value: -7, to: date)!
        return week(ending: previousEnd, history: history, calendar: calendar)
    }
}
