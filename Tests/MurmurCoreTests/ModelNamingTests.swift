import Testing

@testable import MurmurCore

/// The path components below are the ones actually written to
/// ~/Library/Application Support/FluidAudio/Models on this machine.
@Suite("Model naming")
struct ModelNamingTests {

    @Test("Names a Nemotron variant by vocabulary and chunk length")
    func namesNemotronVariant() {
        let described = ModelNaming.describe(pathComponents: ["nemotron-multilingual", "latin", "2240ms"])
        #expect(described.engineName == "Nemotron 3.5 ASR")
        #expect(described.variant == "Western European languages · 2.2 s chunks")
    }

    @Test("Names the short-chunk Nemotron tier")
    func namesShortChunkTier() {
        let described = ModelNaming.describe(pathComponents: ["nemotron-multilingual", "latin", "560ms"])
        #expect(described.variant == "Western European languages · 0.6 s chunks")
    }

    @Test("Names the full-vocabulary Nemotron build")
    func namesMultilingualBuild() {
        let described = ModelNaming.describe(pathComponents: ["nemotron-multilingual", "multilingual", "1120ms"])
        #expect(described.variant == "All languages · 1.1 s chunks")
    }

    @Test("Names Parakeet without a variant")
    func namesParakeet() {
        let described = ModelNaming.describe(pathComponents: ["parakeet-tdt-0.6b-v3"])
        #expect(described.engineName == "Parakeet TDT v3")
        #expect(described.variant == nil)
    }

    @Test("Tidies an unrecognised directory rather than showing it raw")
    func handlesUnknownModel() {
        let described = ModelNaming.describe(pathComponents: ["some-future_model"])
        #expect(described.engineName == "some future model")
        #expect(described.variant == nil)
    }

    @Test("Copes with a Nemotron directory that has no variant beneath it")
    func handlesPartialNemotronPath() {
        let described = ModelNaming.describe(pathComponents: ["nemotron-multilingual"])
        #expect(described.engineName == "Nemotron 3.5 ASR")
        #expect(described.variant == nil)
    }

    @Test("Ignores a chunk directory it cannot parse")
    func handlesUnparsableChunk() {
        let described = ModelNaming.describe(pathComponents: ["nemotron-multilingual", "latin", "weird"])
        #expect(described.variant == "Western European languages")
    }

    @Test("Copes with empty input")
    func handlesEmpty() {
        #expect(ModelNaming.describe(pathComponents: []).engineName == "Unknown model")
    }
}
