import Foundation

/// Decides whether a language model's rewrite of a transcript can be trusted.
///
/// A model asked to tidy dictation sometimes does something else entirely:
/// refuses, prefixes an explanation, or answers the sentence as though it were
/// a question. Those outputs read fluently, so they have to be caught
/// structurally rather than by eye.
public enum RewriteValidator {

    /// Tidying removes words far more often than it adds them, so anything
    /// much longer than the input has stopped being a rewrite.
    public static let maximumGrowthRatio = 1.5

    /// Share of the input's substantial words that must survive into the
    /// output. This is what catches a refusal or an answer: both discuss the
    /// text rather than reproducing it.
    public static let minimumWordRetention = 0.6

    /// Shorter words are function words a legitimate rewrite may well drop.
    private static let significantWordLength = 4

    public static func isPlausibleRewrite(of original: String, result: String) -> Bool {
        let original = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return false }

        let ratio = Double(result.count) / Double(max(original.count, 1))
        guard ratio <= maximumGrowthRatio else { return false }

        let originalWords = significantWords(in: original)
        guard !originalWords.isEmpty else { return true }
        let resultWords = significantWords(in: result)
        let retained = originalWords.filter { resultWords.contains($0) }.count
        return Double(retained) / Double(originalWords.count) >= minimumWordRetention
    }

    private static func significantWords(in text: String) -> Set<String> {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        return Set(words.filter { $0.count >= significantWordLength }.map(String.init))
    }
}
