import Testing
@testable import CpasteCore

@Test(arguments: ["#4C8DF6", "#4c8df6", " #4C8DF6FF\n", "rgb(76, 141, 246)", "rgba(76,141,246,0.5)", "rgb(76 141 246 / 50%)"])
func colourCodesAreColours(text: String) {
    guard case .color(let red, let green, let blue) = TextFlavor(text) else {
        Issue.record("\(text) is not a colour")
        return
    }
    #expect(abs(red - 76 / 255) < 0.01 && abs(green - 141 / 255) < 0.01 && abs(blue - 246 / 255) < 0.01)
}

@Test func shortHexExpands() {
    #expect(TextFlavor("#f00") == .color(red: 1, green: 0, blue: 0))
}

@Test(arguments: [
    "git log --oneline -5\nswift test\n./scripts/build-app.sh",
    "kubectl get pods",
    "./scripts/build-app.sh",
    "func move(by delta: Int) {\n    selection += delta\n}",
    "const total = items.reduce((a, b) => a + b, 0);",
    "SELECT id FROM clip WHERE kind = 'image';",
])
func commandsAndCodeAreCode(text: String) {
    #expect(TextFlavor(text) == .code)
}

@Test(arguments: [
    "kamala beach estate", "מספר הזמנה 48213907", "#hashtag", "#12345", "rgb", "go", "git",
    "Thavorn Beach Village Resort & Spa Phuket",
    "Please make sure the class starts at nine.\nBring the import papers and let me know.\nSee you there.\nThanks",
    "IL62 0108 0000 0009 9999 999", "rgb(300, 0, 0)",
])
func ordinaryTextIsPlain(text: String) {
    #expect(TextFlavor(text) == .plain)
}

@Test(arguments: ["yoav@example.com", " first.last+tag@mail.example.co.il\n"])
func emailAddressesAreEmails(text: String) {
    #expect(TextFlavor(text) == .email)
}

@Test(arguments: ["+972 54-123-4567", "054-123-4567", "(415) 555-0132", "+14155550132"])
func phoneNumbersArePhones(text: String) {
    #expect(TextFlavor(text) == .phone)
}

@Test func jsonIsPrettyPrinted() {
    guard case .json(let pretty) = TextFlavor(#"{"name":"Cpaste","tags":["mac","clipboard"]}"#) else {
        Issue.record("not JSON")
        return
    }
    #expect(pretty.contains("\"name\" : \"Cpaste\""))
    #expect(pretty.split(whereSeparator: \.isNewline).count == 7)
}

@Test(arguments: ["14 November 2026", "2026-11-14 18:30", "Nov 14, 2026 at 6:30 PM"])
func datesAreDates(text: String) {
    guard case .date = TextFlavor(text) else {
        Issue.record("\(text) is not a date")
        return
    }
}

@Test func aPostalAddressIsAnAddress() {
    #expect(TextFlavor("1 Infinite Loop, Cupertino, CA 95014") == .address)
}

@Test(arguments: [
    "48213907", "4155550132", "IL62 0108 0000 0009 9999 999", "meet me tomorrow", "version 2.9.4",
    "yoav@example", "call +972 54-123-4567 after five", "12:30", "today",
])
func lookalikesStayPlain(text: String) {
    #expect(TextFlavor(text) == .plain)
}

@Test func bracesThatDoNotParseAreNotJSON() {
    #expect(TextFlavor("{not json}") == .code)
}

@Test func aPickedColourBecomesAHexCodeCpasteReadsBack() {
    #expect(hexColorCode(red: 76.0 / 255, green: 141.0 / 255, blue: 246.0 / 255) == "#4C8DF6")
    #expect(hexColorCode(red: 0, green: 1.2, blue: -0.1) == "#00FF00")
    #expect(TextFlavor(hexColorCode(red: 1, green: 0.5, blue: 0)) == .color(red: 1, green: 128.0 / 255, blue: 0))
}
