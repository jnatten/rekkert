public enum TeamSide: String, Codable, Sendable, Hashable, CaseIterable {
    case a
    case b

    public var other: TeamSide { self == .a ? .b : .a }
}

public struct BySide<Value> {
    public var a: Value
    public var b: Value

    public init(a: Value, b: Value) {
        self.a = a
        self.b = b
    }

    public init(both value: Value) {
        self.init(a: value, b: value)
    }

    public subscript(side: TeamSide) -> Value {
        get { side == .a ? a : b }
        set { if side == .a { a = newValue } else { b = newValue } }
    }

    public func map<T>(_ transform: (Value) throws -> T) rethrows -> BySide<T> {
        BySide<T>(a: try transform(a), b: try transform(b))
    }
}

extension BySide: Sendable where Value: Sendable {}
extension BySide: Equatable where Value: Equatable {}
extension BySide: Hashable where Value: Hashable {}
extension BySide: Codable where Value: Codable {}

extension BySide where Value == Int {
    public var total: Int { a + b }
    public var isLevel: Bool { a == b }
    public var leader: TeamSide? { a == b ? nil : (a > b ? .a : .b) }

    public func lead(_ side: TeamSide) -> Int { self[side] - self[side.other] }
}
