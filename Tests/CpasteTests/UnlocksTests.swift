import Foundation
import Testing
@testable import Cpaste

@Test func anUnlockedCategoryStaysOpenForAMinute() {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    var unlocks = Unlocks()
    unlocks.unlock(7, at: start)

    #expect(unlocks.open(at: start.addingTimeInterval(59)) == [7])
    #expect(unlocks.open(at: start.addingTimeInterval(60)).isEmpty)
}

@Test func unlockingAgainStartsANewMinute() {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    var unlocks = Unlocks()
    unlocks.unlock(7, at: start)
    unlocks.unlock(7, at: start.addingTimeInterval(50))
    unlocks.unlock(8, at: start)

    #expect(unlocks.open(at: start.addingTimeInterval(70)) == [7])
}
