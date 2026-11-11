import Foundation
import Network

/// One short code for why a local-network link went, for the sharing record (spec 005, D-3).
/// Never the error's own description, which can carry endpoint details (FR-004).
nonisolated enum DropDetail {
    static let pathUnsatisfied = "path unsatisfied"

    static func code(for error: NWError?, pathLost: Bool) -> String? {
        pathLost ? pathUnsatisfied : code(for: error)
    }

    static func code(for error: NWError?) -> String? {
        guard let error else { return nil }
        switch error {
        case .posix(let code):
            switch code {
            case .ETIMEDOUT: return "ETIMEDOUT"
            case .ECONNRESET: return "ECONNRESET"
            case .ECONNREFUSED: return "ECONNREFUSED"
            case .ENETDOWN, .ENETUNREACH: return "ENETDOWN"
            default: return "other"
            }
        case .tls:
            return "tls"
        case .dns:
            return "dns"
        default:
            return "other"
        }
    }

    static let all: Set<String> = ["ETIMEDOUT", "ECONNRESET", "ECONNREFUSED", "ENETDOWN", pathUnsatisfied, "tls", "dns", "other"]
}
