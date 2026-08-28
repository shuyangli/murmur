import Foundation

/// Lays a growing transcript out as a fixed number of subtitle lines.
///
/// Trimming to a character budget looks unstable: every new word shifts where
/// the visible text starts, so all the lines re-wrap and the block jitters on
/// each update. Wrapping the whole transcript and keeping the last few lines
/// instead means earlier lines never change — greedy wrapping depends only on
/// the text before it — so the readout scrolls up one whole line at a time and
/// nothing else moves.
public enum SubtitleText {

    /// Rows the readout shows at once.
    public static let defaultLineCount = 3

    /// Splits `text` into lines that satisfy `fits`, and returns the last
    /// `maxLines` of them.
    ///
    /// - Parameter fits: whether a candidate line is short enough to display.
    ///   The caller supplies this so the split can be measured against the
    ///   real font and panel width, which a character count cannot approximate
    ///   across both Latin and CJK text.
    public static func visibleLines(
        of text: String,
        maxLines: Int = defaultLineCount,
        fits: (String) -> Bool
    ) -> [String] {
        guard maxLines > 0 else { return [] }

        let words = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard !words.isEmpty else { return [] }

        var lines: [String] = []
        var current = ""

        for word in words {
            let candidate = current.isEmpty ? word : current + " " + word
            if current.isEmpty || fits(candidate) {
                // A single word too long for the line still has to go
                // somewhere; it lands alone and the display truncates it.
                current = candidate
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }

        return Array(lines.suffix(maxLines))
    }

    /// Convenience for callers measuring in characters rather than points.
    public static func visibleLines(
        of text: String,
        maxLines: Int = defaultLineCount,
        charactersPerLine: Int
    ) -> [String] {
        visibleLines(of: text, maxLines: maxLines) { $0.count <= charactersPerLine }
    }
}
