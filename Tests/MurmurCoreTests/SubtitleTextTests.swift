import Testing

@testable import MurmurCore

@Suite("Subtitle trimming")
struct SubtitleTextTests {

    @Test("Leaves short text untouched")
    func leavesShortTextAlone() {
        #expect(SubtitleText.tail(of: "hello world", limit: 40) == "hello world")
    }

    @Test("Keeps the end of a long transcript")
    func keepsTheEnd() {
        let text = "one two three four five six seven eight nine ten eleven twelve"
        let result = SubtitleText.tail(of: text, limit: 20)
        #expect(result.hasSuffix("twelve"))
        #expect(!result.contains("one two"))
    }

    @Test("Opens at a word boundary, never mid-word")
    func opensOnAWord() {
        let text = "alpha bravo charlie delta echo foxtrot golf hotel india juliet"
        let result = SubtitleText.tail(of: text, limit: 20)
        // Drop the leading ellipsis, then the first token must be a whole word.
        let firstWord = result.dropFirst().split(separator: " ").first.map(String.init)
        #expect(firstWord != nil)
        #expect(text.split(separator: " ").map(String.init).contains(firstWord!))
    }

    @Test("Marks that earlier words were dropped")
    func marksTruncation() {
        let text = String(repeating: "word ", count: 100)
        #expect(SubtitleText.tail(of: text, limit: 30).hasPrefix("…"))
    }

    @Test("Flattens newlines so the readout stays on its own lines")
    func flattensNewlines() {
        #expect(SubtitleText.tail(of: "first\nsecond", limit: 40) == "first second")
    }

    @Test("Handles empty and whitespace-only input")
    func handlesEmpty() {
        #expect(SubtitleText.tail(of: "") == "")
        #expect(SubtitleText.tail(of: "   \n  ") == "")
    }

    @Test("Still honours the limit when there is no word boundary to cut on")
    func handlesUnbrokenText() {
        // One very long token has no space to break at. Cutting mid-word is
        // ugly, but it is the only option that still fits the panel.
        let text = String(repeating: "x", count: 60)
        #expect(SubtitleText.tail(of: text, limit: 20) == "…" + String(repeating: "x", count: 20))
    }
}
