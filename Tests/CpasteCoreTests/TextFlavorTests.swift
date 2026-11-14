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
