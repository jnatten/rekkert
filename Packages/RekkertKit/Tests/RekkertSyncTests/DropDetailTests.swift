import Foundation
import Network
import Testing
@testable import RekkertSync

@Suite("Why a local-network link went, in one short code")
struct DropDetailTests {
    @Test func posixErrorsMapToTheirCodes() {
        #expect(DropDetail.code(for: .posix(.ETIMEDOUT)) == "ETIMEDOUT")
        #expect(DropDetail.code(for: .posix(.ECONNRESET)) == "ECONNRESET")
        #expect(DropDetail.code(for: .posix(.ECONNREFUSED)) == "ECONNREFUSED")
        #expect(DropDetail.code(for: .posix(.ENETDOWN)) == "ENETDOWN")
        #expect(DropDetail.code(for: .posix(.ENETUNREACH)) == "ENETDOWN")
        #expect(DropDetail.code(for: .posix(.EPERM)) == "other")
    }

    @Test func tlsAndDnsErrorsAreNamedByKind() {
        #expect(DropDetail.code(for: .tls(errSSLClosedAbort)) == "tls")
        #expect(DropDetail.code(for: .dns(DNSServiceErrorType(kDNSServiceErr_NoSuchRecord))) == "dns")
    }

    /// A link that lost its path before it went is put down to that, whatever the system says
    /// last: by then the keepalive has timed out too.
    @Test func aLostPathOutranksTheErrorThatFollows() {
        #expect(DropDetail.code(for: .posix(.ETIMEDOUT), pathLost: true) == "path unsatisfied")
        #expect(DropDetail.code(for: nil, pathLost: true) == "path unsatisfied")
        #expect(DropDetail.code(for: .posix(.ETIMEDOUT), pathLost: false) == "ETIMEDOUT")
    }

    @Test func noErrorGivesNoCode() {
        #expect(DropDetail.code(for: nil) == nil)
    }

    @Test func noCodeCarriesTheErrorsOwnText() {
        let errors: [NWError] = [.posix(.ETIMEDOUT), .posix(.EHOSTDOWN), .tls(errSSLClosedAbort), .dns(-65_554)]
        for error in errors {
            let code = DropDetail.code(for: error)!
            #expect(DropDetail.all.contains(code))
            #expect(code != error.debugDescription)
        }
    }
}
