# Contract: The Engine's Pairing API

**Feature**: [../spec.md](../spec.md) · **Data model**: [../data-model.md](../data-model.md)

What `RekkertCore` and `RekkertSync` expose for the apps to render and forward taps
(Principle I). The views hold no rule of their own: every check, count and message source below
is an engine function, and testable on macOS.

## RekkertCore

```swift
public struct PairingRule: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable { case apart, together }
    public let id: UUID
    public var kind: Kind
    public var players: [PlayerID]          // kept sorted
    public init(id: UUID = UUID(), kind: Kind, players: [PlayerID])
    public var isWellFormed: Bool           // apart ≥ 2, together == 2, no duplicates
}

public struct UnkeptRule: Codable, Sendable, Hashable {
    public var kind: PairingRule.Kind
    public var players: [PlayerID]          // two, sorted
}

public struct PairingConflict: Sendable, Hashable {
    public enum Reason: Sendable, Hashable { case sameTwoBothWays, twoPartnersForOne, togetherInsideApart }
    public var rules: [UUID]
    public var reason: Reason
}

public struct PairingForecast: Sendable, Hashable {
    public var rounds: Int
    public var breaking: Int
    public var players: [PlayerID]
}

extension Array where Element == PairingRule {
    public var conflicts: [PairingConflict] { get }
    public func pruned(to players: [PlayerID]) -> [PairingRule]
}

extension FriendlySession {
    public var pairingRules: [PairingRule]             // stored
    public var activeRules: [PairingRule] { get }      // pruned; empty if clashing or < 4 players
    public func nextDraw() -> FriendlyRound?           // unchanged signature; round carries `unkept`
    public func forecast() -> PairingForecast?         // nil for singles or no active rules
}

extension FriendlyRound {
    public var unkept: [UnkeptRule]                    // stored
}

extension FriendlyScheduler {
    public static func forecast(for session: FriendlySession) -> PairingForecast?
}

extension PresetConfiguration {
    // case friendly(name: String, players: [Player], rules: TraditionalRules, pairing: [PairingRule]? = nil)
}
```

**Guarantees** (each pinned by a test; see [../quickstart.md](../quickstart.md)):

- `FriendlyScheduler.nextRound(for:)` on a session whose `activeRules` is empty returns exactly
  what it returns at `0d4ff41b`, for every player count and round (FR-005).
- `nextDraw()` equals the round the next `nextRound` event folds to, on every device, `unkept`
  included (FR-012).
- `forecast()` equals what is then drawn over the same rotation while players and rules stay
  unchanged (SC-008).
- Nothing here reads a score (Principle II).

## RekkertSync — `MatchStore`

```swift
public var canEditPairingRules: Bool { get }
// canRunRounds, state is a friendly, and (role != .guest || host protocol ≥ 3)

public var olderGuestsTurnedAwayByRules: Int { get }
// On the host: how many guests now linked speak a protocol below 3. Zero elsewhere.

public func setPairingRules(_ rules: [PairingRule])
// Guarded by canEditPairingRules and by rules.conflicts.isEmpty.
// Records .configure(.friendly(session with rules)), like setChangeEnds.
```

`nextRound()` for a friendly now records `placed`. Its signature is unchanged.
