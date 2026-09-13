public enum PointDisplay: Hashable, Sendable {
    case love
    case fifteen
    case thirty
    case forty
    case advantage
    case count(Int)

    public var text: String {
        switch self {
        case .love: "0"
        case .fifteen: "15"
        case .thirty: "30"
        case .forty: "40"
        case .advantage: "AD"
        case .count(let value): String(value)
        }
    }

    /// How an umpire says it. Counts stay as digits: the synthesiser reads those
    /// correctly and a spelled-out table would only be one more thing to keep in step.
    public var spoken: String {
        switch self {
        case .love: "love"
        case .fifteen: "fifteen"
        case .thirty: "thirty"
        case .forty: "forty"
        case .advantage: "advantage"
        case .count(let value): String(value)
        }
    }

    public var isZero: Bool {
        switch self {
        case .love: true
        case .count(let value): value == 0
        default: false
        }
    }

    static func ladder(_ rawPoints: Int) -> PointDisplay {
        switch rawPoints {
        case 0: .love
        case 1: .fifteen
        case 2: .thirty
        default: .forty
        }
    }
}
