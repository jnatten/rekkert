import Testing

@testable import RekkertCore

@Suite("Explaining before Apple Health asks")
struct HealthAskTests {
    @Test func explainsWhenTheSheetWouldShow() {
        #expect(HealthAsk.explainFirst(.wouldAsk))
    }

    @Test func explainsWhenHealthCannotSay() {
        #expect(HealthAsk.explainFirst(.unknown))
    }

    @Test func goesStraightOnOnceAsked() {
        #expect(!HealthAsk.explainFirst(.alreadyAsked))
    }
}
