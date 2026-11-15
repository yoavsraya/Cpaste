import Foundation

/// Which private categories Touch ID has opened, and until when.
struct Unlocks {
    static let duration: TimeInterval = 60
    private var expiry: [Int64: Date] = [:]

    mutating func unlock(_ categoryID: Int64, at now: Date = .now) {
        expiry[categoryID] = now.addingTimeInterval(Self.duration)
    }

    /// The categories still open at `now`. The rest are forgotten.
    mutating func open(at now: Date = .now) -> Set<Int64> {
        expiry = expiry.filter { $0.value > now }
        return Set(expiry.keys)
    }
}
