import Foundation

/// Trims a growing transcript down to what fits in the on-screen readout.
///
/// Dictation can run far longer than the panel can show, so the readout
/// behaves like subtitles: it keeps the most recent words and lets the older
/// ones scroll away, rather than pinning the start and hiding what is
/// currently being said.
public enum SubtitleText {

    /// Roughly three lines at the readout's width.
    public static let defaultLimit = 180

    public static func tail(of text: String, limit: Int = defaultLimit) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit, limit > 0 else { return collapsed }

        let start = collapsed.index(collapsed.endIndex, offsetBy: -limit)
        var slice = collapsed[start...]

        // Start at a word boundary so the line does not open mid-word.
        if let space = slice.firstIndex(of: " ") {
            slice = slice[slice.index(after: space)...]
        }

        let trimmed = slice.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? collapsed : "…" + trimmed
    }
}
