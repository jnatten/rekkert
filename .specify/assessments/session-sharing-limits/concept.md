# Concept: Everyone at a two-court evening following one shared match

- **Slug**: session-sharing-limits
- **Created**: 2026-11-10
- **Recommended option**: A — Steady the links, measure, then raise the limit

## Options

### Option A — Steady the links, measure, then raise the limit

- **Sketch**: Keep sharing as it is today: the host's phone carries every guest over the radios
  at court. Make it trustworthy in three steps, each feeding the next.
  1. **See what is happening.** The sharing record also shows how late each point arrived and
     which radio each link was on, in the builds people actually use.
  2. **Stop the dropping link from hurting.** Every guest's second link dropped about once a
     minute on 8 and 9 November. Either find out why and stop it, or stop it from costing anyone
     time. Guests then see the score as quickly on a busy evening as on a quiet one.
  3. **Measure, then raise the limit.** Run the real-device test spec 001 skipped, at a small
     size (a host and three guests). Set the simulation's speeds from it, and check 9 guests in
     the simulation. Then raise the limit to at least 9 guests and confirm it at a two-court
     evening, measuring watch and phone battery as part of it.

  To players, today's slowness goes away first, and then the two people sitting out can join.
- **Appetite**: medium (weeks), with a circuit breaker after step 3's measurements.
- **Trade-offs**:
  - *Wins*: smallest change to the most fragile part of the app, which spec 001 has only just
    made stable. It goes after the pain that is already there at any group size. It fills in
    the numbers every later decision needs (delay, link drops, connection count, battery). It
    keeps the privacy promise as it stands.
  - *Sacrifices*: it may not reach the goals. The host's phone still sends everything once per
    guest through one shared Bluetooth queue, so there is a ceiling. Nothing shows whether 9
    guests within 1 s is under it.
  - *Risks*: the measurements may show the ceiling is below 9 guests, or above 1 s, so that A
    ends with evidence and a decision rather than a bigger limit. iOS may cap the number of
    connections below what is needed.
- **Rabbit holes**:
  - Chasing *why* the second link drops. Peer-to-peer Wi-Fi is a black box, and the answer may
    not be findable. Timebox the "why" and fall back to "stop it hurting".
  - The host's Bluetooth restarting by itself (19:54 on 9 November). Load may cause it, and it
    cannot be fixed from inside the app.
  - Real-device tests need people and devices together. A two-court test needs 10 phones, and a
    week of waiting for a club night can stretch the timeline.
  - Making the simulation match real devices well enough to predict a club night.

### Option B — A faster network at court

- **Sketch**: Rework how the devices at court carry the match, so the host's phone is no longer
  the bottleneck. Each guest gets its own faster channel from the host, instead of every guest
  sharing one queue. The phones lean on whichever radio is holding up in the hall, with the
  other as backup. Candidates are the faster per-guest Bluetooth channel spec 001 already named
  as its fallback, and Apple's newer Wi-Fi Aware for the phones. To players: more room on a
  match, and faster points, with the same join-by-code flow where the platform allows it.
- **Appetite**: large (months).
- **Trade-offs**:
  - *Wins*: real headroom on size and speed, still with nothing leaving the court and no
    privacy change.
  - *Sacrifices*: rewrites the part of the app that just took a whole spec to make reliable.
    Phones in bags, relaunches and restoration all have to be proven again.
  - *Risks*:
    - Wi-Fi Aware needs a PIN pairing between devices and does not run on watchOS, which clashes
      with join-by-code and with the watch.
    - Older versions probably cannot join. The requester accepts that.
    - Without A's measurements, there is no telling how much faster it would be.
- **Rabbit holes**:
  - New channels behaving differently with the phone locked or the app suspended.
  - Bluetooth state restoration for the new channels.
  - The watch's path, which watchOS limits most.
  - Running two generations of sharing side by side during the move.

### Option C — Share through the internet

- **Sketch**: Phones with mobile data pass the match through a relay on the internet, keyed by
  the same session code, so the host's radio is no longer the limit. The radios at court stay as
  the fallback for when there is no signal. Watches follow through their phones as today. To
  players: no practical limit on numbers, and points as fast as the mobile network allows.
  Possibly friends could also follow from elsewhere.
- **Appetite**: large (months), plus work outside the code:
  - amending Principle V of the constitution;
  - a new privacy policy and App Store privacy label;
  - running a service indefinitely.
- **Trade-offs**:
  - *Wins*: removes the host bottleneck and the device-count question. It scales past two courts.
  - *Sacrifices*: Rekkert's "no account, no server" promise. It also takes on running a service
    for good.
  - *Risks*:
    - Indoor mobile coverage in the halls is unknown, and the halls usually have no Wi-Fi.
    - The radios at court have to stay, so there are two systems to keep converging, not one.
    - Mobile radios cost phone battery.
    - Delay depends on the network, not on the app.
- **Rabbit holes**:
  - Abuse and access control without accounts.
  - Data protection and retention for match data held on a server.
  - Keeping offline-first convergence (Principle II) intact with a second path.
  - The cost and upkeep of the service.

## Recommendation

**Option A**, with a circuit breaker after its measurements.

- **It goes after the pain that is already there.** On 9 November, guests' links dropped about
  once a minute with only four on, and on 8 November with one. That costs players today at any
  group size. Neither B nor C promises to fix it, and both would carry it with them, because the
  radios at court stay in both.
- **It is the only option that produces the evidence the problem asks for.** Delay, connection
  count and battery have never been measured. Without them, B and C would be bets placed blind,
  and so would the "≤1 s", "10 people" and "watch lasts the day" metrics.
- **It may meet the goals by itself.** Raising the limit is a small change once the
  measurements say it holds. Spec 001 made the limit an adjustable constant on purpose.
- **The circuit breaker.** If the step 3 measurements show the host cannot carry 9 guests
  within the delay target, or that iOS caps the connections, stop A after step 2 (steady links,
  better records) and bring the numbers to a new decision between B and C. Steps 1 and 2 are
  worth keeping either way.
- **Doing nothing** keeps today's cost: two people out at every two-court evening, links
  dropping every minute, and a limit nobody has checked (problem.md, Cost of Inaction).

This also answers the define stage's question about splitting the slowdown off. Keep it in this
effort as A's first half, because the limit cannot be raised safely until it is solved.

## Out of Scope (for the recommended option)

- A server, account or internet relay (Option C). Not ruled out for later, but not part of A.
- Reworking the radios: per-guest channels, Wi-Fi Aware (Option B). These come in only through
  the circuit breaker.
- Guests passing the score on to each other, or a guest taking over as host.
- More than two neighbouring courts, or a whole venue.
- A guarantee that older versions can join a raised limit.
- Changes to scoring, match formats or screens, beyond saying who is on and why someone cannot
  get on.
- Fixing the system restarting Bluetooth by itself, beyond recording and reporting it.

## Assumptions to Validate

- **The dropping second link is the local network (peer-to-peer Wi-Fi), and its drops are what
  made sharing feel slow.** If the slowness has another cause, such as the host's shared queue,
  step 2 will not remove it. — research: Sharing records
- **Once the second link is steady, the host's Bluetooth queue has room for 9 guests within
  about 1 s.** Today only the uncalibrated simulation says 7 guests fit within 5 s.
- **iOS lets one host phone hold Bluetooth links to 9 or more guests.** A guest's phone and its
  watch both dial while joining, so briefly more. Apple documents no limit, and old reports
  mention about 10.
- **A small real-device run (a host and three guests) calibrates the simulation well enough to
  predict 9 guests on court.**
- **Sharing costs the watch little battery, because a guest's watch follows through its phone
  and only holds its own link while standing in.** Never measured.
- **The host's Bluetooth restarting is rare, or at least not made worse by more guests.**
- **About 10 players with devices can be gathered for a two-court test within the appetite.**
- **The point delay can be measured in release builds without breaking the privacy promise.**
  It would stay in the on-device sharing record, as everything else there does.
