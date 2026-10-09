public enum HelpChapter: String, CaseIterable, Sendable {
    case watch
    case modes
    case phone

    public var title: String {
        switch self {
        case .watch: "Watch"
        case .modes: "Modes"
        case .phone: "Phone"
        }
    }
}

public enum HelpPicture: Hashable, Sendable {
    case board(GameMode)
    case watchScore
    case watchButtons
    case phoneScore
    case phoneButtons
}

public struct HelpSpot: Hashable, Sendable {
    public let x: Double
    public let y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

public struct HelpItem: Hashable, Sendable, Identifiable {
    public let label: String
    public let symbol: String?
    public let alsoSymbols: [String]
    public let what: String
    public let example: String
    public let only: String?
    public let spot: HelpSpot?
    public let needsWatch: Bool

    public var id: String { label }

    init(
        _ label: String,
        symbol: String? = nil,
        also alsoSymbols: [String] = [],
        what: String,
        example: String,
        only: String? = nil,
        spot: HelpSpot? = nil,
        needsWatch: Bool = false
    ) {
        self.label = label
        self.symbol = symbol
        self.alsoSymbols = alsoSymbols
        self.what = what
        self.example = example
        self.only = only
        self.spot = spot
        self.needsWatch = needsWatch
    }
}

public struct HelpPage: Hashable, Sendable, Identifiable {
    public let id: String
    public let chapter: HelpChapter
    public let title: String
    public let symbol: String
    public let whereToFind: String
    public let picture: HelpPicture
    public let items: [HelpItem]
    public let readme: [String]

    init(
        id: String,
        chapter: HelpChapter,
        title: String,
        symbol: String,
        whereToFind: String,
        picture: HelpPicture,
        readme: [String] = [],
        items: [HelpItem]
    ) {
        self.id = id
        self.chapter = chapter
        self.title = title
        self.symbol = symbol
        self.whereToFind = whereToFind
        self.picture = picture
        self.items = items
        self.readme = readme
    }

    public var mode: GameMode? {
        if case .board(let mode) = picture { return mode }
        return nil
    }

    public var needsWatch: Bool { chapter == .watch }
}
