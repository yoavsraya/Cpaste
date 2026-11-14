import Foundation
import Testing
@testable import CpasteCore

@Test func retentionCutoffs() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(Retention.week.cutoff(from: now) == now.addingTimeInterval(-7 * 86_400))
    #expect(Retention.forever.cutoff(from: now) == nil)
}

@Test func selectionStopsAtBothEnds() {
    #expect(movedSelection(from: 0, by: -1, count: 3) == 0)
    #expect(movedSelection(from: 1, by: 1, count: 3) == 2)
    #expect(movedSelection(from: 2, by: 1, count: 3) == 2)
    #expect(movedSelection(from: 0, by: 1, count: 0) == nil)
}
