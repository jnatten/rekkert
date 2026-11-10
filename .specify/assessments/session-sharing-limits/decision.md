# Decision: Everyone at a two-court evening following one shared match

- **Slug**: session-sharing-limits
- **Decided**: 2026-11-10
- **Verdict**: go (Option A, with its circuit breaker)
- **Artifacts reviewed**: intake.md | research.md | problem.md | concept.md

## Scorecard

| Criterion | Rating | Justification |
|-----------|--------|---------------|
| Problem validity | strong | The code refuses the ninth person (`ParticipantState.limit = 7`), and the requester's usual two-court format is 10 people. The sharing records show links dropping about once a minute on 8 and 9 November, with one and four guests on. |
| Evidence strength | adequate | The problem is backed by the code and by real records from three sessions (over 5,000 lines on the host). Demand is first-hand but from one group, with no usage data by design. The numbers the solution depends on (point delay, battery, how many connections iOS allows) are unmeasured. That is why research rates them low overall, and why Option A measures before it raises the limit. |
| Value vs. inaction | strong | Doing nothing leaves two people out at every two-court evening and links dropping every minute at any group size. Option A's first two steps pay off even if the limit cannot be raised. |
| Feasibility / appetite | adequate | Medium appetite. The limit is an adjustable constant, and spec 001 planned the skipped field test this builds on. Nothing yet shows that one host phone can carry 9 guests within 1 s, and why the second link drops may not be findable; both are bounded by the timebox and the circuit breaker. |
| Strategic fit | strong | Option A stays inside the constitution as it stands: nothing leaves the devices (V), the merge is untouched (II), and it is test-first with the simulation (III). It also finishes spec 001's skipped real-device test (T078). The requester's openness to a server is kept for later, not needed now. |
| Risk posture | adequate | The main risks are named, each with a fallback or a known limit: a capacity ceiling below 9 guests (circuit breaker); an iOS connection cap (circuit breaker); an unfindable cause for the drops (timebox, then "stop it hurting"); Bluetooth restarting by itself (recorded and reported); and gathering 10 people for a test (needs planning outside the app). The last two cannot be fixed from inside the app. |

## Verdict & Rationale

**Go**, for Option A only, with its circuit breaker.

- **The problem is real and certain** (problem validity strong). The limit refuses the ninth
  person, and the records show the links dropping all evening even with few guests.
- **The evidence is adequate for specifying, though not for promising the targets.** What hurts
  is shown by code and field records. What is still unknown is whether the targets are reachable:
  10 people within 1 s, and a watch that lasts the day. Option A is shaped around exactly that
  gap. It makes delay and the radio visible, steadies the links, and measures before it raises
  the limit. If the measurements say the host cannot carry 9 guests in time, it stops and takes
  the numbers to a fresh choice between Options B and C.
- **Why not "needs clarification"?** Sending this back to research would not help. The missing
  numbers can only come from a real-device test and from records that show delay, which is
  Option A's own first step.
- **What this does not approve.** Reworking the radios (Option B), or an off-device path
  (Option C), which would need a constitutional change.

## If needs-clarification

Not applicable.

## If go — Handoff to `/speckit-specify`

- **Problem**: At padel evenings of more than eight people, not everyone can follow the shared
  match on their own devices. Those who can see the score arrive late, even with four or five
  guests on in a busy hall. Nobody knows what sharing costs in battery.
- **Chosen approach**: Option A, in three steps with a stop after the third:
  1. **See what is happening.** The sharing record, in the builds people use, also shows each
     point's delay and which radio each link was on. Nothing leaves the device unless the owner
     shares it, as today.
  2. **Steady the links.** A guest's second link no longer drops every minute, or no longer
     costs anyone time when it does. Finding the cause is timeboxed.
  3. **Measure, then raise the limit.**
     - Run a real-device test at small size (a host and three guests).
     - Set the simulation's speeds from it, and check 9 guests in the simulation.
     - Raise the limit to at least 9 guests, then confirm it at a two-court evening, measuring
       watch and phone battery.
     - **Circuit breaker**: if the measurements show the host cannot carry 9 guests within the
       delay target, or iOS caps the connections, ship steps 1–2 and return to a decision
       between Options B and C with the numbers.
- **In scope**:
  - delay and radio in the sharing record;
  - the second-link drops;
  - the real-device test spec 001 skipped (T078), and calibrating the simulation from it;
  - raising the limit to at least 9 guests on two side-by-side courts;
  - measuring battery on the watch and the phone;
  - the "no room" and who-is-on wording as the limit changes.
- **Out of scope**:
  - a server, account or internet relay;
  - per-guest channels and Wi-Fi Aware;
  - guests passing the score on to each other, or a guest taking over as host;
  - more than two courts;
  - a guarantee that older versions can join;
  - changes to scoring or match formats;
  - fixing the system's own Bluetooth restarts.
- **Success metrics** (from problem.md):
  - At least 10 people including the host on one match, with nobody told "no room" at a
    two-court evening. Baseline: 8.
  - Points within 1 s on every device when nothing is wrong, and within 2 s otherwise, in a busy
    hall too. Baseline: unknown, not recorded today.
  - Link drops per guest per hour in a hall, as a stand-in for delay. Baseline: 56–70/h for
    two-link guests on 9 November, 0/h with one link.
  - A watch still lasts a full day with a 2-hour shared session. Baseline: never measured.
  - One recorded two-court session with a host and 9 guests that agrees with the simulation's
    prediction. Baseline: no real-device test at any size.
- **Carried-forward open questions**:
  - *To settle during `/speckit-clarify`*:
    - What share of points must arrive within 1 s?
    - What drop rate counts as healthy?
    - How much extra watch battery is acceptable, and is there a bar for phones, the host's in
      particular?
    - What is the worst acceptable delay when things go wrong?
    - Is 10 people the target or a floor?
  - *To be answered by Option A's own measurements*:
    - Is the dropping link the local network?
    - Does it slow the steady link?
    - How many Bluetooth connections does one iPhone hold?
    - Does a small run calibrate the simulation for 9 guests?
    - Why did the host's Bluetooth restart?
  - *For a later decision, only if the circuit breaker trips*:
    - How much better would an off-device path need to be to justify the constitutional change?
    - Do the halls have reliable mobile data?
  - *Practical*: when can about 10 people with devices be gathered for the two-court test?
