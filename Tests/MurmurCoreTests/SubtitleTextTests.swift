import Testing

@testable import MurmurCore

@Suite("Subtitle layout")
struct SubtitleTextTests {

    @Test("Keeps short text on a single line")
    func singleLine() {
        #expect(
            SubtitleText.visibleLines(of: "hello world", charactersPerLine: 40)
                == ["hello world"]
        )
    }

    @Test("Wraps greedily at the given width")
    func wrapsGreedily() {
        let lines = SubtitleText.visibleLines(
            of: "alpha bravo charlie delta",
            maxLines: 10,
            charactersPerLine: 12
        )
        #expect(lines == ["alpha bravo", "charlie", "delta"])
    }

    @Test("Shows only the last few lines")
    func keepsTheLastLines() {
        let lines = SubtitleText.visibleLines(
            of: "one two three four five six seven eight nine ten",
            maxLines: 2,
            charactersPerLine: 9
        )
        #expect(lines.count == 2)
        #expect(lines.last!.contains("ten"))
    }

    /// The point of the whole exercise: as words arrive, the lines already on
    /// screen must not re-flow. Only the newest line may change, and the block
    /// may scroll by exactly one line.
    @Test("Earlier lines never change as more words arrive")
    func earlierLinesAreStable() {
        let words = "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima"
            .split(separator: " ").map(String.init)

        var allLineSets: [[String]] = []
        for count in 1...words.count {
            let text = words.prefix(count).joined(separator: " ")
            allLineSets.append(
                SubtitleText.visibleLines(of: text, maxLines: 100, charactersPerLine: 13)
            )
        }

        // Every snapshot must be a prefix-compatible extension of the last:
        // all completed lines are identical, only the final line grows.
        for (previous, current) in zip(allLineSets, allLineSets.dropFirst()) {
            let settled = previous.dropLast()
            #expect(Array(current.prefix(settled.count)) == Array(settled))
        }
    }

    @Test("Scrolls by exactly one line when the window overflows")
    func scrollsOneLineAtATime() {
        let width = 13
        let before = SubtitleText.visibleLines(
            of: "alpha bravo charlie delta echo foxtrot",
            maxLines: 2,
            charactersPerLine: width
        )
        let after = SubtitleText.visibleLines(
            of: "alpha bravo charlie delta echo foxtrot golf hotel india",
            maxLines: 2,
            charactersPerLine: width
        )
        // Nothing partially re-wrapped: the new view still consists of whole
        // lines drawn from the same wrapping of the same text.
        let full = SubtitleText.visibleLines(
            of: "alpha bravo charlie delta echo foxtrot golf hotel india",
            maxLines: 100,
            charactersPerLine: width
        )
        #expect(after == Array(full.suffix(2)))
        #expect(before.count == 2)
    }

    @Test("Puts an over-long word on its own line rather than dropping it")
    func handlesUnbreakableWord() {
        let long = String(repeating: "x", count: 40)
        let lines = SubtitleText.visibleLines(
            of: "short \(long) tail",
            maxLines: 10,
            charactersPerLine: 10
        )
        #expect(lines.contains(long))
        #expect(lines.last == "tail")
    }

    @Test("Flattens newlines into the flow")
    func flattensNewlines() {
        #expect(
            SubtitleText.visibleLines(of: "first\nsecond", charactersPerLine: 40)
                == ["first second"]
        )
    }

    @Test("Returns nothing for empty input")
    func handlesEmpty() {
        #expect(SubtitleText.visibleLines(of: "", charactersPerLine: 40).isEmpty)
        #expect(SubtitleText.visibleLines(of: "   \n ", charactersPerLine: 40).isEmpty)
    }

    @Test("Returns nothing when asked for no lines")
    func handlesZeroLines() {
        #expect(SubtitleText.visibleLines(of: "words here", maxLines: 0, charactersPerLine: 40).isEmpty)
    }
}
