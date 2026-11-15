import Testing
@testable import CpasteCore

@Test func aChangedLineIsMarkedOnBothSides() {
    let comparison = TextComparison(old: "host: a\nport: 80\ndebug: no", new: "host: a\nport: 8080\ndebug: no")

    #expect(comparison.old.map(\.isChanged) == [false, true, false])
    #expect(comparison.new.map(\.isChanged) == [false, true, false])
    #expect(comparison.separator == "\n")
}

@Test func anAddedLineIsMarkedOnlyOnTheNewSide() {
    let comparison = TextComparison(old: "one\nthree", new: "one\ntwo\nthree")

    #expect(comparison.old.filter(\.isChanged).isEmpty)
    #expect(comparison.new.filter(\.isChanged).map(\.text) == ["two"])
}

@Test func twoSingleLinesAreComparedWordByWord() {
    let comparison = TextComparison(old: "meet at the red door", new: "meet at the blue door")

    #expect(comparison.old.filter(\.isChanged).map(\.text) == ["red"])
    #expect(comparison.new.filter(\.isChanged).map(\.text) == ["blue"])
    #expect(comparison.separator == " ")
}

@Test func equalTextsAreIdentical() {
    #expect(TextComparison(old: "same\ntext", new: "same\ntext").isIdentical)
    #expect(!TextComparison(old: "same", new: "other").isIdentical)
}
