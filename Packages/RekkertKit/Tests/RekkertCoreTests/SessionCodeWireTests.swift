import Foundation
import Testing
@testable import RekkertCore

@Suite("A code on the wire")
struct SessionCodeWireTests {
    @Test func sixDigitsAndNothingAroundThem() throws {
        let code = SessionCode("482915")!
        let encoded = try JSONCoding.encoder.encode(code)

        #expect(String(data: encoded, encoding: .utf8) == "\"482915\"", "a string, not a wrapped field")
        #expect(try JSONCoding.decoder.decode(SessionCode.self, from: encoded) == code)
    }

    /// Put back through `init?` on the way in, so a payload that is not a code cannot arrive
    /// as one and be handed to a transport.
    @Test func somethingThatIsNotACodeDoesNotDecodeAsOne() {
        for raw in ["\"482\"", "\"4829157\"", "\"48291!\"", "\"\""] {
            #expect(throws: (any Error).self) {
                try JSONCoding.decoder.decode(SessionCode.self, from: Data(raw.utf8))
            }
        }
    }

    @Test func aCodeWrittenTheWayItIsReadOutStillDecodes() throws {
        let spoken = try JSONCoding.decoder.decode(SessionCode.self, from: Data("\"482-915\"".utf8))
        #expect(spoken == SessionCode("482915"))
    }

    // MARK: - Folding as it is typed

    @Test func theAmbiguousOnesFoldRatherThanBeingRefused() {
        #expect(SessionCode.folding("o") == "0")
        #expect(SessionCode.folding("il") == "11")
        #expect(SessionCode.folding("482915") == "482915")
    }

    /// Half a code is not yet wrong, which is the difference between this and `init?`.
    @Test func aCodeHalfTypedIsKept() {
        #expect(SessionCode.folding("482") == "482")
        #expect(SessionCode("482") == nil, "but it is still not a code")
    }

    @Test func whatCannotBeInACodeIsDropped() {
        #expect(SessionCode.folding("482 915") == "482915", "dictation puts spaces in")
        #expect(SessionCode.folding("482-915") == "482915")
        #expect(SessionCode.folding("482!915") == "482915")
        #expect(SessionCode.folding("48A2") == "482", "letters are not digits")
    }

    @Test func itStopsAtSix() {
        #expect(SessionCode.folding("482915789") == "482915")
    }

    // MARK: - The hyphen, put in as you type

    @Test func theHyphenArrivesWithTheFourthDigit() {
        #expect(SessionCode.grouped("482") == "482", "nothing to put after it yet")
        #expect(SessionCode.grouped("4829") == "482-9")
        #expect(SessionCode.grouped("482915") == "482-915")
    }

    /// A trailing `482-` would come straight back every time it was deleted, and there would be
    /// no way past it. So each backspace has to take a real character off.
    @Test func backspacingWalksBackOutAgain() {
        var field = SessionCode.grouped("482915")
        var seen = [field]
        while !field.isEmpty {
            field = SessionCode.grouped(String(field.dropLast()))
            seen.append(field)
        }
        #expect(seen == ["482-915", "482-91", "482-9", "482", "48", "4", ""])
    }

    @Test func aGroupedFieldStillParses() {
        #expect(SessionCode("482-915") == SessionCode("482915"))
        #expect(SessionCode(SessionCode.grouped("482915")) == SessionCode("482915"))
    }

    @Test func regroupingWhatIsAlreadyGroupedChangesNothing() {
        for raw in ["482915", "4829", "482", "4", ""] {
            let once = SessionCode.grouped(raw)
            #expect(SessionCode.grouped(once) == once)
        }
    }

    /// What the host reads off their screen is what the joiner watches appear on theirs.
    @Test func theCodeIsShownTheWayItIsTyped() {
        let code = SessionCode("482915")!
        #expect(code.description == SessionCode.grouped(code.letters))
        #expect(code.description == "482-915")
    }

    /// The two agree wherever both have an answer: anything the field lets you finish typing
    /// is a code, and folding it again changes nothing.
    @Test func foldingAndParsingAgree() {
        for raw in ["482915", "482-915", "o1l234", "482 915"] {
            let folded = SessionCode.folding(raw)
            #expect(SessionCode(raw)?.letters == (folded.count == SessionCode.length ? folded : nil))
            #expect(SessionCode.folding(folded) == folded, "and it settles")
        }
    }
}
