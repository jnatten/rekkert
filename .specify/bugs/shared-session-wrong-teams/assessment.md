# Bug Assessment: A 32-bit watch draws different Americano teams from everyone else

- **Slug**: shared-session-wrong-teams
- **Created**: 2026-11-06
- **Source**: pasted text
- **Verdict**: valid. The cause is clear from the code and reproduced off the device by emulating the watch's 32-bit `Int`. It has not yet been watched on the SE itself.
- **Severity**: high

## Report (verbatim or summarized)

> previous run where we did a bunch of session sharing testing (5 people + host) someone (1 person) got completely wrong names in the initial round of americano (Different teams than the real tournament had).
>
> Not sure why, but they were on the first watchos 10 commit (on a 1 gen apple watch se).
> Worked for the others i think, no other complaints at least.

"The first watchOS 10 commit" is `21c1252 feat(watch): install on watchOS 10 so the Apple Watch SE (1st generation) gets Rekkert`. Nothing in `RekkertCore` has changed since then, so `HEAD` behaves the same way.

## Symptom

In a shared Americano session, the player with an Apple Watch SE (1st generation) saw different teams in round 1 from the ones the rest of the tournament had. Everyone else saw the right teams. Expected: every phone and watch shows the same teams, because they all draw from the same log.

## Reproduction

Off the device (done, 2026-11-06): the draw was emulated on a Mac with the watch's integer width.

1. Copy `SeededGenerator` as it is and shuffle six players with `Array.shuffled(using:)`. Then mirror the stdlib's Fisher–Yates loop twice, drawing with `Int64.random(in:using:)` once and `Int32.random(in:using:)` once.
2. Run this for 2,000 random tournament ids.
3. Result: the 64-bit mirror matched the stdlib's `shuffled(using:)` every time. The 32-bit draw differed from the 64-bit one **2000/2000** times, for example `[2, 3, 0, 5, 4, 1]` against `[4, 1, 2, 0, 5, 3]`. So the watch and the phones put different players on the courts in practically every tournament.

On the device (not yet done):

1. Install a build from `21c1252` or later on an iPhone paired with an Apple Watch SE (1st generation). A Series 4 or Series 5 should behave the same.
2. On the phone, start an Americano with 6 players. A shared session is not needed.
3. Compare round 1 on the phone and on the watch. Expected (bug): the teams differ. A Friendly with 4 or more players should also differ.

[NEEDS CLARIFICATION: did the affected person's phone show the right teams, with only the watch wrong? The hypothesis says yes.]

## Suspected Code Paths

- `Packages/RekkertKit/Sources/RekkertCore/Tournament/RoundScheduler.swift:26`: `players.map(\.id).shuffled(using: &generator)`. The stdlib's shuffle draws each swap with `Int.random(in: 0 ..< amount, using:)`, so it works at the width of `Int`. On arm64_32 (the S4/S5 chips in Series 4, Series 5 and SE 1st generation) `Int` is 32 bits. There the draw truncates each `UInt64` from the generator to its low 32 bits and keeps the high half of a 32×32 product. On 64-bit hardware it keeps the high half of a 64×64 product. The seed is the same but the permutation is different. Both the bench and the order fed to `PairingSearch.teams` come from this shuffle.
- `RoundScheduler.swift:174-195` (`AmericanoScheduler.nextRound`): every Americano round is drawn through `split` on each device.
- `RoundScheduler.swift:274-289` (`TournamentEngine.placement`) returns `nil` for Americano ("Nil for Americano, which never reads a score"). So the drawing device's result never travels, and every device trusts its own draw. Mexicano and winner court carry `placed`, so their rounds survive a different draw.
- `Packages/RekkertKit/Sources/RekkertCore/Sync/SessionReducer.swift:146-166`: `.nextRound(after: -1)` is folded on every device, the watch included. Round 1 is not in the `configure` event (`SessionReducer.swift:247-252`), so the watch draws it itself.
- `Packages/RekkertKit/Sources/RekkertCore/Friendly/FriendlyScheduler.swift:30,46-49`: a Friendly uses the same `RoundScheduler.split`. It has no `placed` to fall back on, and the doc comment relies on "the phone and the watch fold the same event log into the same draw". It is affected in the same way, even with no sharing (your own phone and SE disagree).
- `Packages/RekkertKit/Sources/RekkertCore/Tournament/LadderScheduler.swift:68`: a random ladder start uses the same width-dependent shuffle. It is mostly masked because ladder rounds carry `placed`, but `placed?.round(for:) ?? LadderScheduler.nextRound(...)` falls back to the local draw when there is no placement (events from older builds).
- `Packages/RekkertKit/Sources/RekkertCore/Tournament/SeededGenerator.swift`: the generator itself is width-independent (all `UInt64`). The problem is in the stdlib helpers layered on top of it.

How the wrong draw can spread to other devices:

- `WatchApp/Sources/Views/WatchResultView.swift:59` → `MatchStore.undoResult()` → `record(.restore(rewind.state, takingBack: filed))` (`Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift:1023`). `.restore` carries the whole state. If "Back to it" is tapped on an arm64_32 watch, its wrong rounds go to every device and replace the right ones.

## Root Cause Hypothesis

The tournament and friendly draws must come out identical on every device. They depend on `Array.shuffled(using:)`, and that function depends on the platform's `Int` width. iPhones and newer watches are 64-bit. The Apple Watch SE (1st generation) runs the arm64_32 slice, where `Int` is 32 bits, so the same seed gives a different permutation. The players are then split and paired differently, and the names land on different teams. Nobody saw this before `21c1252` because the floor was watchOS 26, which no S4/S5 watch can run. The local Debug watch builds are arm64 only, and the simulator pair (SE 3) is arm64, so no test or simulator check could catch it. Row 5 of the SE validation ("Every mode") has not been run on the SE yet. **Confidence: high.** The arithmetic is deterministic, the emulation diverged on every seed, and only the arm64_32 watch is wrong, which matches the report.

## Proposed Remediation

**Preferred**: Make the seeded draw independent of `Int` width while keeping today's 64-bit results exactly. In `SeededGenerator.swift`, add a draw below `n` computed entirely in `UInt64`. It should be Lemire's nearly divisionless method, the same steps as the stdlib's `next(upperBound:)` for `UInt64`, written out by hand so a toolchain change cannot move it. Add a seeded shuffle that walks the array the way `MutableCollection.shuffle(using:)` does: from the front, swapping the current slot with `current + draw(below: remaining)`. On 64-bit hardware this gives exactly what `shuffled(using:)` gives today (the emulation confirmed this for 2,000 seeds). So phones and arm64 watches on any build already installed keep agreeing with the new build, and arm64_32 watches now agree too. Use it at `RoundScheduler.swift:26` and `LadderScheduler.swift:68`. No wire or log change is needed.

To stop this coming back, drop `SeededGenerator`'s `RandomNumberGenerator` conformance. Then `shuffled(using:)`, `Int.random(in:using:)` and `randomElement(using:)` no longer compile against it, and every seeded draw has to go through the width-independent path. The demo data in `Shared/AppModel.swift:255-308` uses `Double.random`/`Int.random` with `SeededGenerator`. It needs its own small conforming generator, since nothing has to agree across devices there.

**Alternatives**:

- Carry the Americano draw in `.nextRound(placed:)` the way Mexicano and ladder already do. This is good defense in depth for later, but it does not fix the bug on its own. Installed builds ignore `placed` for Americano (`RoundScheduler.swift:247`) and still draw for themselves. An arm64_32 watch that draws carries its wrong draw. Friendly has nowhere to carry one.
- Switch to a different seeded shuffle (for example, sort by generated keys). This is simpler, but it changes every draw on every device. A shared session mixing new and installed builds would then disagree everywhere, which is worse than today.

**Files likely to change**:

- `Packages/RekkertKit/Sources/RekkertCore/Tournament/SeededGenerator.swift`
- `Packages/RekkertKit/Sources/RekkertCore/Tournament/RoundScheduler.swift`
- `Packages/RekkertKit/Sources/RekkertCore/Tournament/LadderScheduler.swift`
- `Shared/AppModel.swift` (demo data, only if the conformance is dropped)
- `Packages/RekkertKit/Tests/RekkertCoreTests/TournamentTests.swift`, `FriendlyTests.swift`, and a new `SeededGeneratorTests.swift`

**Tests to add or update**:

- **Golden draws, captured from the current code before the change.** Pin these against the fixed ids the tests already use (for example `00000000-0000-0000-0000-0000000000FF`): Americano rounds 1-3 with 6 and with 9 players, a Friendly with 4 and with 5 players, and a random ladder start. They must still pass unchanged after the fix. That shows installed 64-bit builds still agree.
- **Compatibility with the stdlib on 64-bit.** For about 1,000 seeds and lengths 0-16, the new shuffle equals `Array.shuffled(using:)` on the test host. This test can only run on a 64-bit host, which is also the only kind CI has.
- **Pinned draw arithmetic.** A fixed seed's sequence of draws below 2, 3, 6, 7 and 1,000 is pinned to literal values. The code is all `UInt64`, so the same values hold on arm64_32.
- **Optional CI step:** build `RekkertCore` for `arm64_32-apple-watchos10.0`. It can only be built, not run (there is no arm64_32 simulator), but it catches arm64_32-only compile errors.
- **Manual, on the SE (quickstart § 3 row 5):** Americano and Friendly, a few rounds each, solo and in a shared session with another phone. Phone and SE show the same teams and sit-outs. After a finished Americano, "Back to it" on the SE changes nobody's teams.

## Risks & Considerations

- **Compatibility is the whole point of the fix.** If the hand-written draw differs from the stdlib's in even one step, it changes everyone's draws compared with installed builds. The golden and compatibility tests must exist and pass before the swap.
- **Installed builds stay wrong.** An arm64_32 watch on a build from before the fix keeps drawing its own teams until it is updated, and can still spread them with "Back to it". Testers on an SE, Series 4 or Series 5 should update. Mixing fixed and unfixed builds is otherwise harmless, because 64-bit results do not change.
- **Side effects while a watch shows the wrong draw.** A point tapped on the watch addresses round, court and side, so it lands correctly in everyone's log. But the wearer may tap the wrong side, because the names on the buttons are wrong. The watch's standings and bench also diverge, and later rounds drift further because `PairingHistory` is built from the watch's own rounds.
- **A related arm64_32 bug, out of scope here:** `Packages/RekkertKit/Sources/RekkertSync/BluetoothTransport.swift:92` computes `Int(seconds) * 1_000_000_000`. That overflows a 32-bit `Int` for any delay of 3 s or more, and the radio arms 4 s, 10 s and 15 s timers (`RadioCore.swift:145-148`, `:794`). The watch builds a `BluetoothTransport` (`Shared/AppModel.swift:75`), so on arm64_32 this traps as soon as one of those timers is armed. It needs its own assessment.
- Any other code that assumes a 64-bit `Int` and has to agree across devices or across the wire would show the same split. A grep found no other seeded `Int`-width draws in the sync or tournament paths. `SessionCode.random` uses the system generator, so nothing there has to agree.

## Open Questions

- [NEEDS CLARIFICATION: was it the watch that showed the wrong teams, and did the same person's phone show the right ones?]
- [NEEDS CLARIFICATION: did later rounds also differ on that watch? The hypothesis predicts every Americano round would.]
- [NEEDS CLARIFICATION: did anyone tap "Back to it" on the SE after a result? If so, the wrong draw may have reached other devices for the rest of that session.]
- [NEEDS CLARIFICATION: which watches did the other five have? Series 6-8, SE (2nd generation) and Ultra (1st generation) may also run the arm64_32 slice on watchOS 26. If they do, this bug predates `21c1252`, and anyone with one of those watches who looked at it would have seen the same thing.]
