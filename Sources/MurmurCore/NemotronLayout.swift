import Foundation

/// Where a given Nemotron configuration keeps its files.
///
/// Nemotron ships one build per vocabulary and per chunk tier, so a machine
/// can hold several at once and only one of them is the one in use. Knowing
/// which directory the current settings resolve to is what lets the settings
/// list mark that one and leave the rest plainly deletable.
///
/// This mirrors the host's own naming; it is deliberately narrow, and anything
/// it does not recognise falls through to the full-vocabulary build.
public enum NemotronLayout {

    /// Languages that get the vocabulary-pruned Latin-script build.
    private static let latinPrefixes = ["en", "es", "fr", "it", "pt", "de"]

    public static func vocabularyDirectory(for languageCode: String) -> String {
        let code = languageCode.lowercased()
        return latinPrefixes.contains(where: code.hasPrefix) ? "latin" : "multilingual"
    }

    public static func chunkDirectory(for chunkMilliseconds: Int) -> String {
        "\(chunkMilliseconds)ms"
    }

    /// True when `pathComponents` names the build these settings would load.
    public static func matches(
        pathComponents: [String],
        languageCode: String,
        chunkMilliseconds: Int
    ) -> Bool {
        guard pathComponents.count >= 2 else { return false }
        let chunk = pathComponents[pathComponents.count - 1]
        let vocabulary = pathComponents[pathComponents.count - 2]
        return vocabulary == vocabularyDirectory(for: languageCode)
            && chunk == chunkDirectory(for: chunkMilliseconds)
    }
}
