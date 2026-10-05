import Foundation
import Testing
@testable import RekkertCore

@Suite("A code as a link")
struct SessionCodeLinkTests {
    @Test func theCodeTravelsInTheFragment() {
        let code = SessionCode("482915")!
        #expect(code.joinLink.absoluteString == "https://rekkert.natten.dev/join#482915")
        #expect(SessionCode(joinLink: code.joinLink) == code)
    }

    @Test func aLinkWrittenTheWayTheCodeIsReadOutStillOpens() {
        #expect(SessionCode(joinLink: URL(string: "https://rekkert.natten.dev/join#482-915")!) == SessionCode("482915"))
        #expect(SessionCode(joinLink: URL(string: "https://Rekkert.Natten.dev/join/#482915")!) == SessionCode("482915"))
    }

    @Test func onlyTheJoinLinkOpensAMatch() {
        for raw in [
            "https://example.com/join#482915",
            "https://rekkert.natten.dev/privacy#482915",
            "https://rekkert.natten.dev/#482915",
            "http://rekkert.natten.dev/join#482915",
            "rekkert://join#482915",
            "https://rekkert.natten.dev/join",
            "https://rekkert.natten.dev/join#",
            "https://rekkert.natten.dev/join#48291",
            "https://rekkert.natten.dev/join#48291!",
            "https://rekkert.natten.dev/join?code=482915",
        ] {
            #expect(SessionCode(joinLink: URL(string: raw)!) == nil, "\(raw)")
        }
    }
}
