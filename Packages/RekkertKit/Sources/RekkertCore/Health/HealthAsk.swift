/// Whether Rekkert explains itself before Apple Health puts up its permission sheet.
public enum HealthAsk {
    public enum Status: Sendable {
        case wouldAsk
        case alreadyAsked
        case unknown
    }

    /// A status Health could not give is treated as a first time: an explanation too many
    /// costs a tap, a request with no lead-in is what the review turned down.
    public static func explainFirst(_ status: Status) -> Bool {
        status != .alreadyAsked
    }
}
