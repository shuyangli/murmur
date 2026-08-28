import Testing

@testable import MurmurCore

@Suite("Filler removal")
struct FillerFilterTests {

    @Test("Strips standalone fillers and repairs the pause around them")
    func stripsFillers() {
        #expect(
            FillerFilter.clean("Um, so I was thinking, uh, that we should refactor.")
                == "So I was thinking that we should refactor."
        )
    }

    @Test("Keeps a sentence-ending mark the filler was carrying")
    func keepsTerminator() {
        #expect(FillerFilter.clean("Never mind, uh. I found it.") == "Never mind. I found it.")
        #expect(FillerFilter.clean("Are you sure, um?") == "Are you sure?")
    }

    @Test("Recapitalises when the opening word was a filler")
    func recapitalises() {
        #expect(FillerFilter.clean("Uh, hey there.") == "Hey there.")
        #expect(FillerFilter.clean("Um. Can you send it?") == "Can you send it?")
    }

    @Test("Leaves sincere interjections alone")
    func keepsInterjections() {
        // "ah" and "oh" carry meaning; dropping them changes the sentence.
        #expect(FillerFilter.clean("Ah, finally.") == "Ah, finally.")
        #expect(FillerFilter.clean("Oh, I see.") == "Oh, I see.")
    }

    @Test("Collapses a stuttered word")
    func collapsesStutter() {
        #expect(FillerFilter.clean("I I think the the plan works.") == "I think the plan works.")
    }

    @Test("Leaves doubled words that are ordinary English")
    func keepsLegitimateDoubles() {
        // These are the reason stutter collapsing uses an allow-list rather
        // than collapsing every repeat.
        #expect(FillerFilter.clean("I had had enough.") == "I had had enough.")
        #expect(FillerFilter.clean("I know that that works.") == "I know that that works.")
        #expect(FillerFilter.clean("It was very very good.") == "It was very very good.")
    }

    @Test("Does not touch a repeat that spans a sentence boundary")
    func keepsRepeatAcrossPunctuation() {
        #expect(FillerFilter.clean("That is it. It works.") == "That is it. It works.")
    }

    @Test("Leaves discourse markers alone by default")
    func discourseMarkersOffByDefault() {
        #expect(
            FillerFilter.clean("So, you know, we could split it up.")
                == "So, you know, we could split it up."
        )
    }

    @Test("Removes discourse markers when asked")
    func removesDiscourseMarkers() {
        let options = FillerFilter.Options(removeFillers: true, removeDiscourseMarkers: true)
        #expect(
            FillerFilter.clean("So, you know, we could split it up.", options: options)
                == "So we could split it up."
        )
        #expect(
            FillerFilter.clean("It is, I mean, mostly done.", options: options)
                == "It is mostly done."
        )
    }

    @Test("Only removes 'like' where it is parenthetical")
    func likeIsHandledCarefully() {
        let options = FillerFilter.Options(removeFillers: true, removeDiscourseMarkers: true)
        // Meaningful uses must survive even in aggressive mode.
        #expect(FillerFilter.clean("I like it.", options: options) == "I like it.")
        #expect(FillerFilter.clean("It looks like rain.", options: options) == "It looks like rain.")
        #expect(
            FillerFilter.clean("It is, like, mostly done.", options: options)
                == "It is mostly done."
        )
    }

    @Test("Only removes 'kind of' where it is parenthetical")
    func hedgesAreHandledCarefully() {
        let options = FillerFilter.Options(removeFillers: true, removeDiscourseMarkers: true)
        // "kind of a mess" is the noun sense and must not lose words.
        #expect(
            FillerFilter.clean("It is kind of a mess.", options: options) == "It is kind of a mess."
        )
    }

    @Test("Does nothing when both passes are off")
    func respectsDisabledOptions() {
        let text = "Um, so, uh, I I think so."
        #expect(FillerFilter.clean(text, options: .none) == text)
    }

    @Test("Leaves clean text untouched")
    func leavesCleanTextAlone() {
        let text = "Hello world. This is a test of the dictation system."
        #expect(FillerFilter.clean(text) == text)
    }

    @Test("Handles a transcript that is only fillers")
    func handlesAllFillers() {
        #expect(FillerFilter.clean("Um, uh, hmm.") == "")
    }

    @Test("Handles empty input")
    func handlesEmpty() {
        #expect(FillerFilter.clean("") == "")
    }

    @Test("Cleans a real transcript captured from the Nemotron engine")
    func cleansRealTranscript() {
        // Verbatim output from `--selftest` on a clip with natural fillers.
        let transcribed = "Uh hey um can you uh send me that file or actually never mind uh I found it"
        #expect(
            FillerFilter.clean(transcribed)
                == "Hey can you send me that file or actually never mind I found it"
        )
    }
}
