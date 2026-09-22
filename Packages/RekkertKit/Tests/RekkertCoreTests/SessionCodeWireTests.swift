import Foundation
import Testing
@testable import RekkertCore

@Suite("A code on the wire")
struct SessionCodeWireTests {
    @Test func sixCharactersAndNothingAroundThem() throws {
        let code = SessionCode("H7K3MR")!
        let encoded = try JSONCoding.encoder.encode(code)

        #expect(String(data: encoded, encoding: .utf8) == "\"H7K3MR\"", "a string, not a wrapped field")
        #expect(try JSONCoding.decoder.decode(SessionCode.self, from: encoded) == code)
    }

    /// Put back through `init?` on the way in, so a payload that is not a code cannot arrive
    /// as one and be handed to a transport.
    @Test func somethingThatIsNotACodeDoesNotDecodeAsOne() {
        for raw in ["\"H7K\"", "\"H7K3MRX\"", "\"H7K3M!\"", "\"\""] {
            #expect(throws: (any Error).self) {
                try JSONCoding.decoder.decode(SessionCode.self, from: Data(raw.utf8))
            }
        }
    }

    @Test func aCodeWrittenTheWayItIsReadOutStillDecodes() throws {
        let spoken = try JSONCoding.decoder.decode(SessionCode.self, from: Data("\"h7k-3mr\"".utf8))
        #expect(spoken == SessionCode("H7K3MR"))
    }

    // MARK: - Folding as it is typed

    @Test func theAmbiguousOnesFoldRatherThanBeingRefused() {
        #expect(SessionCode.folding("o") == "0")
        #expect(SessionCode.folding("il") == "11")
        #expect(SessionCode.folding("h7k3mr") == "H7K3MR")
    }

    /// Half a code is not yet wrong, which is the difference between this and `init?`.
    @Test func aCodeHalfTypedIsKept() {
        #expect(SessionCode.folding("H7K") == "H7K")
        #expect(SessionCode("H7K") == nil, "but it is still not a code")
    }

    @Test func whatCannotBeInACodeIsDropped() {
        #expect(SessionCode.folding("H7K 3MR") == "H7K3MR", "dictation puts spaces in")
        #expect(SessionCode.folding("H7K-3MR") == "H7K3MR")
        #expect(SessionCode.folding("H7K!3MR") == "H7K3MR")
    }

    @Test func itStopsAtSix() {
        #expect(SessionCode.folding("H7K3MRXYZ") == "H7K3MR")
    }

    // MARK: - The hyphen, put in as you type

    @Test func theHyphenArrivesWithTheFourthCharacter() {
        #expect(SessionCode.grouped("H7K") == "H7K", "nothing to put after it yet")
        #expect(SessionCode.grouped("H7K3") == "H7K-3")
        #expect(SessionCode.grouped("H7K3MR") == "H7K-3MR")
    }

    /// A trailing `H7K-` would come straight back every time it was deleted, and there would be
    /// no way past it. So each backspace has to take a real character off.
    @Test func backspacingWalksBackOutAgain() {
        var field = SessionCode.grouped("H7K3MR")
        var seen = [field]
        while !field.isEmpty {
            field = SessionCode.grouped(String(field.dropLast()))
            seen.append(field)
        }
        #expect(seen == ["H7K-3MR", "H7K-3M", "H7K-3", "H7K", "H7", "H", ""])
    }

    @Test func aGroupedFieldStillParses() {
        #expect(SessionCode("H7K-3MR") == SessionCode("H7K3MR"))
        #expect(SessionCode(SessionCode.grouped("h7k3mr")) == SessionCode("H7K3MR"))
    }

    @Test func regroupingWhatIsAlreadyGroupedChangesNothing() {
        for raw in ["H7K3MR", "H7K3", "H7K", "H", ""] {
            let once = SessionCode.grouped(raw)
            #expect(SessionCode.grouped(once) == once)
        }
    }

    /// What the host reads off their screen is what the joiner watches appear on theirs.
    @Test func theCodeIsShownTheWayItIsTyped() {
        let code = SessionCode("H7K3MR")!
        #expect(code.description == SessionCode.grouped(code.letters))
        #expect(code.description == "H7K-3MR")
    }

    /// The two agree wherever both have an answer: anything the field lets you finish typing
    /// is a code, and folding it again changes nothing.
    @Test func foldingAndParsingAgree() {
        for raw in ["h7k3mr", "H7K-3MR", "o1l234", "H7K 3MR"] {
            let folded = SessionCode.folding(raw)
            #expect(SessionCode(raw)?.letters == (folded.count == SessionCode.length ? folded : nil))
            #expect(SessionCode.folding(folded) == folded, "and it settles")
        }
    }
}
