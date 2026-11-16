# Data Model: Pairing Rules for a Friendly

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md) · **Decisions**: [research.md](research.md)

Everything here is in `RekkertCore` and nonisolated, except the protocol table in
`RekkertSync`'s `MatchStore`. All new stored fields are additive, and read with
`decodeIfPresent`. `FriendlyRound.unkept` and a preset's `pairing` are written only when they
hold something. `FriendlySession`'s rules are always written by this build, an empty list
included, so that an absent key means "an older build wrote this" (research D-1).

## PairingRule *(new)*

`RekkertCore/Friendly/PairingRules.swift`

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | Identity in the editor and in clash messages. Minted when the rule is added. |
| `kind` | `PairingRule.Kind` | `.apart` or `.together`; raw values `"apart"` and `"together"`. |
| `players` | `[PlayerID]` | Sorted ascending, so equal rules encode to equal bytes. |

**Validation** (a rule on its own):

- `.apart` needs two or more distinct players.
- `.together` needs exactly two distinct players.
- A rule that fails either is not a rule: the editor cannot save it, and the draw ignores it.

**Meaning**:

- `.apart`: no two of `players` are partners in a round drawn while it stands (FR-002).
- `.together`: the two are partners in every round drawn while it stands in which both are on
  court. It never decides who sits out (FR-003).

## A set of rules *(helpers on `[PairingRule]`)*

| Helper | Returns | Requirement |
|---|---|---|
| `conflicts` | `[PairingConflict]`: the clashing rule ids and the reason (`sameTwoBothWays`, `twoPartnersForOne`, `togetherInsideApart`) | FR-009 |
| `pruned(to: [PlayerID])` | The rules with missing players removed, and any rule left below its minimum dropped | FR-011 |
| `breaks(_ teams: BySide<[PlayerID]>)` | `[UnkeptRule]` for a line-up: pairs together against an `.apart`, and `.together` pairs split while both play | FR-006, FR-007 |
| `isActive(for players: Int)` | False for fewer than four players: singles have no partners | Edge case "Singles" |

A set with any conflict is treated by the draw as no rules (D-8). The editor never saves one.

## UnkeptRule *(new)*

What a drawn round could not keep. Value type, `Codable`, `Hashable`.

| Field | Type | Notes |
|---|---|---|
| `kind` | `PairingRule.Kind` | Which promise broke |
| `players` | `[PlayerID]` | Exactly two, sorted: the pair put together, or the pair split |

## FriendlySession *(changed)*

| Field | Type | Change |
|---|---|---|
| `statedPairingRules` | `[PairingRule]?` | **New, stored**, under the key `pairingRules`. `nil` means "never stated": the friendly came from a build older than this feature. Decoded with `decodeIfPresent`. Encoded whenever it is not nil, an empty list included. Every `FriendlySession` this build creates states it (`[]` by default). Needs a hand-written `init(from:)`/`encode(to:)`, like `FriendlyRound`'s. |
| `pairingRules` | `[PairingRule]` | **New, computed**: `statedPairingRules ?? []`. Setting it states it. |

New read-only API:

- `activeRules` is `pairingRules` pruned to `players`, or empty when they clash or when there are
  fewer than four players.
- `nextDraw()` is unchanged in signature. It now returns a round carrying `unkept`.
- `forecast()` is `FriendlyScheduler.forecast(for: self)`; see below.

**Lifecycle**:

1. **Set up.** The setup form starts the friendly with
   `configure(.friendly(session with rules))`, or a preset does, with ids remapped and pruned
   (D-10).
2. **Changed in play.** `setPairingRules` records another `configure(.friendly(…))`. The reducer
   adopts the rules beside `name`, `rules` and `players` **only when the incoming friendly states
   them** (`statedPairingRules != nil`), and keeps the id and the rounds. An older build's
   correction states nothing, and leaves the rules as they were.
3. **Read by every draw after that.** No round already drawn is touched.
4. **Finished, restored or saved as a preset.** The rules travel unchanged.

A change of `players` through a correcting `configure` comes with rules already pruned by the
sender. The draw prunes again defensively.

## FriendlyRound *(changed)*

| Field | Type | Change |
|---|---|---|
| `unkept` | `[UnkeptRule]` | **New.** Filled in when the round is drawn, from the rules then in force (D-4). Encoded only when not empty. Never recomputed afterwards: a later rule change leaves it as it was. |

## RoundPlacement *(changed use)*

There are no new fields. A friendly draw now carries one, with `courts` holding the single
court's two sides and `sitOuts` the bench. A new internal reading,
`friendlyRound(for: FriendlySession) -> FriendlyRound?`, accepts it only when:

- every listed player appears exactly once across the sides and the bench;
- each side has `teamSize` players;
- the bench has `sitOutCount` players.

Otherwise it returns nil, and the round is drawn as today.

## PairingForecast *(new)*

The result of `FriendlyScheduler.forecast(for:)`, which draws one full rotation forward from the
session as it stands (D-7).

| Field | Type | Notes |
|---|---|---|
| `rounds` | `Int` | The rotation's length: `n / gcd(n, 4)` for n ≥ 5; the number of allowed line-ups for n = 4 |
| `breaking` | `Int` | How many of those rounds break a rule |
| `unkept` | `[UnkeptRule]` | Every distinct pair broken in those rounds, in the order first met, so the message can name the players and say "apart", "together" or both |

The forecast is nil for fewer than four players, or with no active rules.

## PresetConfiguration *(changed)*

| Case | Change |
|---|---|
| `.friendly(name:players:rules:)` | Gains `pairing: [PairingRule]? = nil`, written only when not empty. `makeSetup()` maps member ids old → new along with the fresh players, then prunes. |

## The sharing protocol *(changed)*

| Item | Was | Now |
|---|---|---|
| `Wire.sharingProtocol` | `2` | `3`: the first build that draws with pairing rules |
| `MatchStore` peer bookkeeping | `olderDevices` / `currentDevices` sets | Adds each device's protocol number (`nil` read as 1). The sets stay, derived from it, for the code that reads them. |

While the friendly has active rules, a guest below 3 is turned away by the host, as in
[contracts/wire-protocol.md](contracts/wire-protocol.md). A phone's own watch below 3 is held
back by its phone:

| `MatchStore` member | Type | Meaning |
|---|---|---|
| `pairNeedsUpdateForRules` | `Bool`, observable | True on a phone whose paired watch last said hello below protocol 3 while the session in play is a friendly with active rules. While it is true, the phone sends the watch nothing of that session, and its board says so. |
| The pair's protocol | persisted with `pairedDevice` | So a relaunched phone knows an older watch before that watch says hello. |
| `PeerTransport.holdsSessionFromPair` | `Bool`, settable; default reads false | Set by `MatchStore` from `pairNeedsUpdateForRules`. `FanOutTransport` skips its paired-device child for `.events` and `.snapshot` while it is true. |
