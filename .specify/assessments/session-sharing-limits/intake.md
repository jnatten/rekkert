# Idea Intake: More than seven guests in a shared match

- **Slug**: session-sharing-limits
- **Created**: 2026-11-10
- **Source**: pasted text, plus the requester's answers to the first-glance questions (2026-11-10)
- **Type**: improvement

## Idea (as captured)

> "Let users connect more than 7 guests with session sharing, without much delay or battery consumption"

## Restated

Raise the number of guests who can join a host's shared match above today's seven, while keeping
points arriving quickly on every device and keeping battery use low.

## Origin & Context

- **Raised by**: developers and users.
- **Trigger**: groups of more than eight on court hit the limit. Separately, on 2026-11-09 sharing
  got very slow when a number of people who were not on the match came into the hall. The requester
  suspects Bluetooth interference; this is unverified.

What the idea touches today (recorded, not judged):

- Spec 001 (`specs/001-fix-session-sharing/spec.md`, FR-001) sets the limit: a host and up to seven
  guests, each with a phone and a watch, over two neighbouring courts, with no shared Wi-Fi. A guest
  counts once whether on phone, watch or both. An eighth guest is turned away and told so (FR-008).
  The requester says the number seven was picked by an agent, and does not know whether it reflects
  a technical limit.
- The limit is `ParticipantState.limit = 7` in
  `Packages/RekkertKit/Sources/RekkertCore/Sync/ParticipantState.swift`; the host's handshake refuses
  with `noRoom` once it is reached (`RekkertSync/SharedSession.swift`).
- Delay is already specified in spec 001 (FR-002): a point shows on every device in range within
  30 seconds, and within 5 seconds for at least 95% of points, including with phones locked.
- Battery: spec 001 chose "no limit — measured and reported, does not hold the release" (SC-012).
  This idea asks for low battery use, which that spec did not require.

## Answers from the requester

| Question | Answer |
|---|---|
| How many on the match? | At least two full courts plus two sitting out: **10 people including the host** (9 guests) is the minimum. |
| How fast? | Near instant. Ideally at most **1 second** when nothing is wrong; a second or two now and then is acceptable. This is tighter than spec 001's FR-002 (5 s for 95%, 30 s at most). |
| How much battery? | No number; to be found by testing. The bar: today a watch lasts a full day with a 2-hour padel session in the middle. If sharing means charging the watch before and after a session, it is too much. |
| Where? | Usually no Wi-Fi. Two courts, usually side by side. |
| Watch-only guests? | One person counts as one guest, whichever device they join with. |
| Older versions? | They should be able to join, but breaking changes are acceptable if needed. |
| How to test? | Real devices on a real court, with a simulation to check it before going on court. |

## Still Open

- [NEEDS CLARIFICATION: Is 10 people a floor with a larger goal behind it (three courts, a whole
  club night), or the target?]
- [NEEDS CLARIFICATION: Does the battery bar apply to phones too, or only to watches?]
- [NEEDS CLARIFICATION: What delay is acceptable when things go wrong — a crowded hall, a device at
  the edge of range, a locked phone?]
- [NEEDS CLARIFICATION: Did the 2026-11-09 slowdown come from the people entering the hall, or from
  something else? The phone's link record keeps the last 7 days (spec 001, `LinkRecord.keptDays`),
  so that evening may still be on the devices that were there.]
