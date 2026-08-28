import Testing

@testable import MurmurCore

/// The accept/reject cases are real: every rejected string below was produced
/// by Apple's on-device model when it was prompted for free-form text instead
/// of guided output, and every accepted string is a genuine rewrite it
/// returned once guided generation was in place.
@Suite("Rewrite validation")
struct RewriteValidatorTests {

    @Test("Accepts a genuine tidy-up")
    func acceptsRealRewrite() {
        #expect(
            RewriteValidator.isPlausibleRewrite(
                of: "um so the the thing is I I wanted to to ask about the deployment uh schedule for next week",
                result: "So the thing is, I wanted to ask about the deployment schedule for next week."
            )
        )
    }

    @Test("Accepts a rewrite that only adds punctuation")
    func acceptsPunctuationOnly() {
        #expect(
            RewriteValidator.isPlausibleRewrite(
                of: "Hey can you send me that file or actually never mind I found it",
                result: "Hey, can you send me that file or actually never mind, I found it"
            )
        )
    }

    @Test("Accepts a grammar repair")
    func acceptsGrammarRepair() {
        #expect(
            RewriteValidator.isPlausibleRewrite(
                of: "can you take a look at the pull request? I open this morning. I refactored the transcription layer so the engine is behind a protocol",
                result: "Can you take a look at the pull request? I opened this morning. I refactored the transcription layer so the engine is behind a protocol."
            )
        )
    }

    @Test("Rejects a refusal")
    func rejectsRefusal() {
        #expect(
            !RewriteValidator.isPlausibleRewrite(
                of: "Hey can you send me that file or actually never mind I found it",
                result: "I'm sorry, but I cannot assist with that request."
            )
        )
    }

    @Test("Rejects the model answering the dictation instead of editing it")
    func rejectsAnswer() {
        #expect(
            !RewriteValidator.isPlausibleRewrite(
                of: "can you take a look at the pull request? I open this morning. I refactored the transcription layer so the engine is behind a protocol",
                result: "Sure, I'd be happy to take a look at the pull request. Could you please provide me with the details of the pull request, including the code changes and any relevant information about the transcription layer and the protocol?"
            )
        )
    }

    @Test("Rejects a conversational preamble wrapped around the text")
    func rejectsPreamble() {
        #expect(
            !RewriteValidator.isPlausibleRewrite(
                of: "So I was thinking that we should probably refactor the transcription layer like it's kind of a mess right now",
                result: "Sure, I can help with that. Here's a cleaned version of the text:\n\n\"So I was thinking that we should probably refactor the transcription layer like it's kind of a mess right now.\""
            )
        )
    }

    @Test("Rejects an empty or whitespace result")
    func rejectsEmpty() {
        #expect(!RewriteValidator.isPlausibleRewrite(of: "Some real words here", result: ""))
        #expect(!RewriteValidator.isPlausibleRewrite(of: "Some real words here", result: "   \n "))
    }

    @Test("Rejects a result that dropped most of the content")
    func rejectsTruncation() {
        #expect(
            !RewriteValidator.isPlausibleRewrite(
                of: "The deployment schedule slipped because the migration script kept timing out overnight",
                result: "The deployment slipped."
            )
        )
    }

    @Test("Accepts when the input has no substantial words to compare")
    func acceptsShortInput() {
        // Nothing to measure retention against, so length alone decides.
        #expect(RewriteValidator.isPlausibleRewrite(of: "ok so no", result: "OK, so no."))
    }
}
