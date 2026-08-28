import Foundation

/// Removes disfluencies from a transcript without changing its meaning.
///
/// This runs on every dictation, so it is deliberately mechanical: a word list
/// and some punctuation tidying, no model and no judgement. It cannot fix
/// grammar or unpick a false start — that is what the optional language-model
/// pass is for — but it also cannot invent words you did not say, and it costs
/// no measurable time.
public enum FillerFilter {

    public struct Options: Sendable, Equatable {
        /// Strip "um", "uh" and friends.
        public var removeFillers: Bool
        /// Also strip conversational padding: "you know", "I mean", and "like"
        /// where it is clearly parenthetical.
        public var removeDiscourseMarkers: Bool

        public init(removeFillers: Bool = true, removeDiscourseMarkers: Bool = false) {
            self.removeFillers = removeFillers
            self.removeDiscourseMarkers = removeDiscourseMarkers
        }

        public static let `default` = Options()
        public static let none = Options(removeFillers: false, removeDiscourseMarkers: false)
    }

    /// Sounds that carry no meaning in any context, so they are always safe to
    /// drop. "ah" and "oh" are deliberately absent: they are real interjections
    /// often meant sincerely ("ah, finally").
    private static let fillerWords: Set<String> = [
        "um", "umm", "ummm", "uhm", "uh", "uhh", "uhhh",
        "er", "err", "erm", "hmm", "hm", "hmmm", "mm", "mmm",
    ]

    /// Padding phrases, longest first so "you know" is matched before "know".
    /// Only removed under `removeDiscourseMarkers`.
    private static let discoursePhrases: [[String]] = [
        ["you", "know"],
        ["i", "mean"],
        ["sort", "of"],
        ["kind", "of"],
    ]

    /// Words that get stuttered. Deliberately excludes pairs that are ordinary
    /// English when doubled — "had had", "that that", "very very".
    private static let stutterProne: Set<String> = [
        "i", "the", "a", "an", "and", "to", "it", "we", "you", "my", "is", "of", "in", "so", "but",
    ]

    public static func clean(_ text: String, options: Options = .default) -> String {
        guard options.removeFillers || options.removeDiscourseMarkers else { return text }

        var tokens = tokenize(text)
        if options.removeFillers {
            tokens = removingFillers(from: tokens)
            tokens = collapsingStutters(in: tokens)
        }
        if options.removeDiscourseMarkers {
            tokens = removingDiscourseMarkers(from: tokens)
        }
        return reassemble(tokens)
    }

    // MARK: - Tokenising

    /// A word plus whatever punctuation trailed it, so punctuation can travel
    /// with its word and be dropped alongside it.
    private struct Token {
        var word: String
        var trailingPunctuation: String

        var comparisonKey: String {
            word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "\u{2019}'"))
        }

        var isEmpty: Bool { word.isEmpty }
    }

    private static let punctuationSuffix = CharacterSet(charactersIn: ",.!?;:")

    private static func tokenize(_ text: String) -> [Token] {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map { raw in
            var word = String(raw)
            var trailing = ""
            while let last = word.unicodeScalars.last, punctuationSuffix.contains(last) {
                trailing = String(last) + trailing
                word.unicodeScalars.removeLast()
            }
            return Token(word: word, trailingPunctuation: trailing)
        }
    }

    // MARK: - Passes

    private static func removingFillers(from tokens: [Token]) -> [Token] {
        var result: [Token] = []
        for token in tokens {
            guard fillerWords.contains(token.comparisonKey) else {
                result.append(token)
                continue
            }
            repairPunctuation(after: token, in: &result)
        }
        return result
    }

    private static func removingDiscourseMarkers(from tokens: [Token]) -> [Token] {
        var result: [Token] = []
        var index = 0
        while index < tokens.count {
            if let length = discoursePhraseLength(at: index, in: tokens) {
                repairPunctuation(after: tokens[index + length - 1], in: &result)
                index += length
                continue
            }
            // "like" only counts as padding when it is parenthetical — set off
            // by a comma, or trailing one. "I like it" and "looks like rain"
            // must survive untouched.
            if tokens[index].comparisonKey == "like", isParenthetical(at: index, in: tokens) {
                repairPunctuation(after: tokens[index], in: &result)
                index += 1
                continue
            }
            result.append(tokens[index])
            index += 1
        }
        return result
    }

    private static func discoursePhraseLength(at index: Int, in tokens: [Token]) -> Int? {
        for phrase in discoursePhrases where index + phrase.count <= tokens.count {
            let slice = tokens[index..<(index + phrase.count)].map(\.comparisonKey)
            if slice == phrase {
                // "sort of" / "kind of" are only padding before an adjective or
                // adverb, which we cannot tell apart here, so require the
                // comma-delimited form to stay safe.
                if phrase.last == "of", !isParenthetical(at: index, in: tokens) { continue }
                return phrase.count
            }
        }
        return nil
    }

    private static func isParenthetical(at index: Int, in tokens: [Token]) -> Bool {
        let precededByComma = index > 0 && tokens[index - 1].trailingPunctuation.contains(",")
        let followedByComma = tokens[index].trailingPunctuation.contains(",")
        return precededByComma || followedByComma
    }

    /// Mends the punctuation left behind when `removed` is deleted.
    ///
    /// Two cases matter: a sentence-ending mark the removed word was carrying
    /// has to move back onto the previous word, and a pause on both sides of
    /// the removed word would otherwise collapse into a stray comma.
    private static func repairPunctuation(after removed: Token, in result: inout [Token]) {
        guard var previous = result.popLast() else { return }
        let terminator = removed.trailingPunctuation.filter { ".!?".contains($0) }
        if !terminator.isEmpty {
            // "I found it, uh." must keep its full stop.
            previous.trailingPunctuation = terminator
        } else if removed.trailingPunctuation.contains(","),
                  previous.trailingPunctuation.contains(",") {
            // "thinking, uh, that" would otherwise read as "thinking, that".
            previous.trailingPunctuation = ""
        }
        result.append(previous)
    }

    private static func collapsingStutters(in tokens: [Token]) -> [Token] {
        var result: [Token] = []
        for token in tokens {
            if let previous = result.last,
               previous.trailingPunctuation.isEmpty,
               stutterProne.contains(token.comparisonKey),
               previous.comparisonKey == token.comparisonKey {
                // Keep the second one so its punctuation survives.
                result.removeLast()
            }
            result.append(token)
        }
        return result
    }

    // MARK: - Reassembly

    private static func reassemble(_ tokens: [Token]) -> String {
        var words: [String] = []
        var capitaliseNext = true

        for token in tokens where !token.isEmpty {
            var word = token.word
            if capitaliseNext {
                word = word.prefix(1).uppercased() + word.dropFirst()
                capitaliseNext = false
            }
            // A comma left dangling where a filler used to be reads as a typo.
            let punctuation = token.trailingPunctuation
            if punctuation.contains(where: { ".!?".contains($0) }) {
                capitaliseNext = true
            }
            words.append(word + punctuation)
        }

        return words.joined(separator: " ")
    }
}
