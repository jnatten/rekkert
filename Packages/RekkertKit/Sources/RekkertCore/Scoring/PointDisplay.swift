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

    static func ladder(_ rawPoints: Int) -> PointDisplay {
        switch rawPoints {
        case 0: .love
        case 1: .fifteen
        case 2: .thirty
        default: .forty
        }
    }
}
