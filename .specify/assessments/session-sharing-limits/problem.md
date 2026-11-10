# Problem Definition: Everyone at a two-court evening following one shared match

- **Slug**: session-sharing-limits
- **Created**: 2026-11-10
- **Inputs used**: intake.md, research.md (including the host's and a guest's sharing records
  from 4, 8 and 9 November)

## Problem Statement

When a group of more than eight plays padel together, such as two full courts with two people
sitting out, not everyone can follow the shared match on their own phone and watch. Those who
can follow see the score arrive slowly, even with only four or five guests on in a hall with
other people around. Nobody knows what sharing costs in battery, so nobody can say whether it
will still last an evening of play.

## Affected Users & Stakeholders

- **Users**
  - **Guests beyond the seventh**: turned away with "no room" and left to follow on someone
    else's screen. This happens at any evening of more than eight people. — [research: Users &
    Demand; `ParticipantState.limit = 7`]
  - **Guests already on**: see the score late. On 9 November each guest's link dropped about
    once a minute all evening, and the session felt "really slow". — [research: Sharing records
    from 4, 8 and 9 November]
  - **The host**: their phone carries every guest, and each extra guest adds to its radio load.
    On 9 November its Bluetooth restarted by itself mid-session. — [research: Data & Constraints]
  - **Guests who follow on the watch**: count the same as phone users (one person, one guest).
    They feel any battery cost most, because the watch must last the day. — [intake answers]
  - **People on older app versions**: should still be able to join, but the requester accepts
    breaking changes if needed. — [intake answers]
- **Stakeholders**
  - **The requester and the developers**: decide and build. They report hitting the limit
    themselves. — [intake]
  - **Regular players in the requester's group** (for example the friend on B701, who is
    usually a guest): affected every session. How many such groups use Rekkert is unknown, since
    the app collects no usage data. — [research: Users & Demand]
  - **Anyone relying on Rekkert's privacy promise**: the constitution (Principle V) and the
    published privacy policy both say there is no account and no server, and that the score
    travels only between the devices at court. The requester is open to a server, an account or
    an internet relay if it makes the experience better. Adopting one means amending the
    constitution and changing the privacy policy first. — [`.specify/memory/constitution.md:68-79`;
    `docs/privacy/index.html:7,98,128`; requester, 2026-11-10]

## Goals

- **Everyone at a two-court evening can follow on their own devices.** That is at least
  10 people including the host, on two side-by-side courts, usually with no venue Wi-Fi.
- **The score feels instant.** A point shows on every device within about a second when
  nothing is wrong. A second or two now and then is acceptable.
- **Sharing stays fast in a busy hall.** Other people and their devices nearby do not make it
  noticeably slower.
- **Sharing does not change how people charge their devices.** A watch that lasts a full day
  with a 2-hour session in it today still does with sharing on.
- **The team can tell before a club night whether sharing will hold up**, rather than finding
  out on court, and can then confirm it with real devices on a real court.

## Non-Goals

- **More than two neighbouring courts, or a whole venue**, for now. 10 people is the stated
  floor; anything beyond is unconfirmed (see Open Questions).
- **Guests passing the score on to each other, or a guest taking over as host.** Spec 001 left
  these out of scope, and nothing here brings them back.
- **Keeping older app versions able to join whatever the cost.** That is wanted, but not if it
  stands in the way of the goals.
- **Changing scoring rules, match formats or what the screens show**, beyond saying who is on
  and why someone cannot get on.

## Success Metrics

- **People on one shared match**: at least 10 including the host, with nobody told "no room" at
  a two-court evening. (baseline: 8 including the host; the ninth is always refused)
- **Point delay on every device, when nothing is wrong**: within 1 s for
  [NEEDS CLARIFICATION: what share of points, for example 95%?], and within 2 s otherwise.
  (baseline: unknown, because release builds do not record delay. Spec 001's targets are 95%
  within 5 s and all within 30 s.)
- **Point delay in a hall with other people around**: same as above. (baseline: unknown; felt
  "really slow" on 9 November)
- **Link drops per guest per hour, in a hall** *(a stand-in for delay, not a goal in itself)*.
  Target: [NEEDS CLARIFICATION: what rate counts as healthy?]. (baseline: on 9 November, 56/h
  for guest 255B and 70/h for B701, both with two links; 0/h for 17CF with one link. On
  8 November, about 109/h with a single guest.)
- **Watch battery over a 2-hour shared session**: no more than without sharing, by
  [NEEDS CLARIFICATION: what margin, in percentage points?]. Qualitative check: nobody needs to
  charge their watch before or after a session. (baseline: never measured)
- **Phone battery over a 2-hour shared session**: [NEEDS CLARIFICATION: is there a bar for
  phones, including the host's?] (baseline: never measured)
- **Real-device evidence**: at least one recorded session on court with a host and 9 guests on
  two side-by-side courts, whose results agree with what was predicted beforehand. (baseline: no
  real-device test of sharing at any size; spec 001's field test was skipped)

## Cost of Inaction

- Every evening with more than eight people, at least one person cannot follow on their own
  devices. At the requester's usual two-court format, two people miss out every time.
- The links keep dropping about once a minute in a hall, even with four guests. That happened
  on 8 November too, with one guest standing next to the host. Sharing will keep feeling slow
  whether or not the limit moves.
- The seven-guest limit, the simulated speeds and any battery claim stay guesses. Spec 001's
  field test was skipped, so every later change to sharing builds on numbers nobody has checked.
- [ASSUMPTION] Players who are turned away or see a stale score fall back to keeping their own
  score, or stop using sharing, which undoes what spec 001 fixed.

## Open Questions

- [NEEDS CLARIFICATION: Is 10 people including the host the target, or a floor with a larger
  goal behind it, such as three courts or a whole club night?]
- [NEEDS CLARIFICATION: How much would an off-device path have to improve the experience to be
  worth the constitutional change and a new privacy policy? It is neither a goal nor ruled out.]
- [NEEDS CLARIFICATION: Do the halls have reliable mobile data? Anything that goes through the
  internet needs it, and the halls usually have no Wi-Fi to offer.]
- [NEEDS CLARIFICATION: What share of points must arrive within 1 s, and what is the worst
  acceptable delay when things go wrong (a busy hall, a device at the edge of range, a locked
  phone)?]
- [NEEDS CLARIFICATION: Does the battery bar cover phones too, the host's in particular, or
  only watches? And how much extra use is acceptable?]
- [NEEDS CLARIFICATION: Should the slowdown below the limit (the dropping links) be solved here,
  or split into a problem of its own? It hurts today regardless of the limit.]
- [NEEDS CLARIFICATION: Is the dropping link really the local network over peer-to-peer Wi-Fi?
  The records point that way but do not name the radio.]
- [NEEDS CLARIFICATION: Does a second link that keeps dropping slow down points on the steady
  one?]
- [NEEDS CLARIFICATION: Why did the host's Bluetooth restart by itself at 19:54 on
  9 November, and does load on the host make it more likely?]
- [NEEDS CLARIFICATION: How many central connections does one iPhone hold in practice before
  delivery slips? Only a real-device test can answer this.]
- [NEEDS CLARIFICATION: Of 10 people at a two-court evening, how many actually join with a
  device rather than following someone else's screen?]
- [NEEDS CLARIFICATION: Can the simulation be calibrated from a smaller real-device run, for
  example a host and three guests, before anyone tries 9 guests on court?]
