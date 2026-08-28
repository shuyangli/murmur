import Testing

@testable import MurmurCore

@Suite("Nemotron layout")
struct NemotronLayoutTests {

    @Test("Latin-script languages use the pruned build")
    func latinLanguages() {
        for code in ["en-US", "en-GB", "es-ES", "fr-FR", "it-IT", "pt-BR", "de-DE"] {
            #expect(NemotronLayout.vocabularyDirectory(for: code) == "latin")
        }
    }

    @Test("Other languages use the full-vocabulary build")
    func otherLanguages() {
        for code in ["zh-CN", "ja-JP", "auto", "ko-KR"] {
            #expect(NemotronLayout.vocabularyDirectory(for: code) == "multilingual")
        }
    }

    @Test("Language matching ignores case")
    func ignoresCase() {
        #expect(NemotronLayout.vocabularyDirectory(for: "EN-US") == "latin")
    }

    @Test("Matches the build the current settings would load")
    func matchesActiveBuild() {
        #expect(
            NemotronLayout.matches(
                pathComponents: ["nemotron-multilingual", "latin", "2240ms"],
                languageCode: "en-US",
                chunkMilliseconds: 2240
            )
        )
    }

    /// The reason this exists: with two tiers on disk, only one is in use.
    @Test("Does not match a different chunk tier of the same language")
    func rejectsOtherChunkTier() {
        #expect(
            !NemotronLayout.matches(
                pathComponents: ["nemotron-multilingual", "latin", "560ms"],
                languageCode: "en-US",
                chunkMilliseconds: 2240
            )
        )
    }

    @Test("Does not match a different vocabulary at the same tier")
    func rejectsOtherVocabulary() {
        #expect(
            !NemotronLayout.matches(
                pathComponents: ["nemotron-multilingual", "multilingual", "2240ms"],
                languageCode: "en-US",
                chunkMilliseconds: 2240
            )
        )
        #expect(
            NemotronLayout.matches(
                pathComponents: ["nemotron-multilingual", "multilingual", "2240ms"],
                languageCode: "ja-JP",
                chunkMilliseconds: 2240
            )
        )
    }

    @Test("Rejects a path too short to name a build")
    func rejectsShortPath() {
        #expect(
            !NemotronLayout.matches(
                pathComponents: ["nemotron-multilingual"],
                languageCode: "en-US",
                chunkMilliseconds: 2240
            )
        )
    }
}
