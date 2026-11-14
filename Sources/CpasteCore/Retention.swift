import Foundation

/// How long unsaved history is kept.
public enum Retention: String, CaseIterable, Sendable {
    case day, week, month, quarter, year, forever

    public var label: String {
        switch self {
        case .day: "1 day"
        case .week: "1 week"
        case .month: "1 month"
        case .quarter: "3 months"
        case .year: "1 year"
        case .forever: "Forever"
        }
    }

    /// Clips last used before this date have expired. Nil means nothing expires.
    public func cutoff(from now: Date) -> Date? {
        let days: Double? = switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .year: 365
        case .forever: nil
        }
        return days.map { now.addingTimeInterval(-$0 * 86_400) }
    }
}

/// The selection after moving `delta` places in a list of `count` clips, stopping at either end.
public func movedSelection(from index: Int, by delta: Int, count: Int) -> Int? {
    guard count > 0 else { return nil }
    return min(max(index + delta, 0), count - 1)
}
