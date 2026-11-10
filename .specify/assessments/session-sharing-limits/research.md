# Idea Research: More than seven guests in a shared match

- **Slug**: session-sharing-limits
- **Created**: 2026-11-10
- **Evidence confidence (overall)**: low

  The code and past specs are well documented, so what the app does today is known with high
  confidence. What it can do on real devices is not: no real-device test of sharing has been run
  for any number of guests, nobody has measured battery use, and the demand comes from one
  requester's account. The numbers that matter (how many guests, how fast, how much battery)
  rest on a simulation that has never been checked against real devices. The host's and a
  guest's sharing records from 4, 8 and 9 November now give real data on how stable the links
  are, but not on point delay or battery (see "Sharing records from 4, 8 and 9 November").

## Users & Demand

- Groups of more than eight people on court hit the limit. Developers and users raised it. —
  [source: intake.md, requester's answers] (confidence: medium; stated, one source)
- That a ninth person is refused is certain: the host takes seven guests and refuses the next
  with `noRoom`. — [source: `Packages/RekkertKit/Sources/RekkertCore/Sync/ParticipantState.swift:34,75`;
  `Tests/RekkertSyncTests/CapacityTests.swift:53`] (confidence: high)
- The requester's floor is 10 people including the host: two full courts plus two sitting out.
  — [source: intake.md] (confidence: medium; stated)
- The app already scores formats far bigger than sharing allows: a test holds an eight-court
  americano in a Live Activity. Tournaments of 10 or more players are a supported use; sharing
  them is not. — [source: `README.md:316-317`] (confidence: high)
- On 2026-11-09, sharing got very slow when people who were not on the match came into the
  hall. The requester suspects Bluetooth interference. — [source: intake.md] (confidence: low;
  one report, cause unverified). The sharing records confirm the links dropped constantly that
  evening, with no more than five guest devices on. They do not show that the newcomers caused
  it, and they point at the local-network link more than at Bluetooth (see "Sharing records
  from 4, 8 and 9 November").
- No usage data exists, by design. There is no telemetry and no server (Principle V), so the
  only field record is the sharing record on each person's own phone, which keeps 7 days. —
  [source: `.specify/memory/constitution.md:68-76`; `RekkertCore/Sync/LinkRecord.swift:152`]
  (confidence: high)
- No GitHub issues on the repository mention sharing, guests, slowness or battery. —
  [source: `gh issue list --state all --search "sharing OR guests OR slow OR battery"`, 0 results]
  (confidence: high that none are filed; says little about demand)
- How many of the 10 players would join with a device, rather than follow someone else's
  screen, is unknown. — [ASSUMPTION] (confidence: low)

## Prior Art

**Inside Rekkert**

- **Seven is a placeholder that was never measured.** Spec 001 chose it so the host refuses
  honestly instead of slowly starving everyone. It says: "How many connections iOS really
  allows is checked in the field test. The limit is a constant that can be adjusted." —
  [source: `specs/001-fix-session-sharing/research.md:276-284` (D-8)] (confidence: high)
- **That field test never ran.** T078 (four iPhones, four watches, Wi-Fi off) is marked
  "Deferred: skipped for now, and blocks nothing". The simulated radio's speed was to be set
  from its measurements (T081, SC-009), and the battery readings (SC-012) were to come from it.
  None of the three exists. — [source: `specs/001-fix-session-sharing/tasks.md:469,582`;
  `spec.md:417-428`] (confidence: high)
- **Spec 001 left the real ceiling as an open question.** Two of its three "only real devices
  can settle" items are this idea's core: how many central connections one iPhone holds, and
  whether one shared transmit queue carries seven guests in time. — [source:
  `specs/001-fix-session-sharing/research.md:432-438`] (confidence: high)
- **Adding guests has broken sharing before.** Before spec 001 there was no limit (RC-7). The
  host served guests in a fixed order (RC-3), and its all-or-nothing acknowledgement fed on
  itself (RC-4), which gave "lag that grows with every guest and every point" in the
  2026-10-26 incident. Fair turns (D-4) and per-guest delivery (D-5) fixed those. —
  [source: `specs/001-fix-session-sharing/research.md:63-116, 215-245`] (confidence: high)
- **Spec 001 considered and deferred one alternative.** A Bluetooth L2CAP channel per guest
  "gives stream flow control per guest and more throughput, but it is a much larger change.
  Deferred, unless the field test shows the shared queue cannot carry seven guests." —
  [source: `specs/001-fix-session-sharing/research.md:226-229`] (confidence: high that it was
  considered; its effect is unmeasured)
- **Seven guests pass only in the simulation.** `CapacityTests`, `IncidentTests` and the
  two-court, seven-guest americano (T081) pass on `SimulatedRadio`. Its defaults are a guess
  that was never checked against a device: 4,000 bytes/s shared by everything one host sends,
  8 queue slots, 182-byte chunks and 30 ms latency. — [source:
  `Tests/RekkertSyncTests/SimulatedRadio.swift:10-24`; `tasks.md:582`] (confidence: high that
  they pass; low that they predict real devices)
- **No other real-device sharing record exists either.** Spec 004 was checked on simulators
  with two phones. Spec 003's real-device sheet for the Apple Watch SE is still blank. —
  [source: `specs/004-match-end-sharing-prompt/validation.md:5-10`;
  `specs/003-apple-watch-se-support/validation.md`] (confidence: high)

**Outside Rekkert**

- **Multipeer Connectivity** was Apple's peer-to-peer session framework. It is deprecated in
  the current SDK ("Use Network Framework instead"). It capped a session at a fixed number of
  peers; that number is commonly given as 8. Whether spec 001's agent took seven guests plus
  the host from it is unknown. — [source: `MultipeerConnectivity.framework/Headers/MCSession.h:33-36`
  in the installed iOS SDK for the deprecation; the value 8 is an ASSUMPTION from memory, not
  checked here] (confidence: medium)
- **Wi-Fi Aware** is new in iOS 26, which is Rekkert's minimum iOS. It is unavailable on
  watchOS. It reports a runtime `maximumConnectableDevices`, and has a `noPairedDevices` error,
  meaning devices must be paired first. Search results say pairing is one-time, with a
  six-digit PIN. — [source: `WiFiAware.swiftmodule/arm64e-apple-ios.swiftinterface:12-18, 54,
  127` in the installed iOS SDK; pairing details from web search results, not fetched]
  (confidence: medium for the interface, low for the pairing details)
- **Other padel scoring apps**, as described in their store listings, mostly sync the watches
  of the 2–4 players on one court, or let others follow through a web page, which needs a
  server. None states a cap above that. — [source: web search results (store listings), not
  fetched] (confidence: low)

## Market & Context

- **What people do today past seven guests**: the refused person is told "no room" on phone
  and watch (FR-008). They can presumably follow on someone else's screen or keep their own
  unshared score. — [ASSUMPTION; the refusal from FR-001/FR-008 in `specs/001-fix-session-sharing/spec.md:244-249`]
  (confidence: low)
- **Cost of doing nothing**: at a two-court evening with 10 people, at least two people cannot
  follow on their own devices. Formats the app is built for (americano over several courts)
  regularly exceed eight players. — [source: intake.md; `README.md:316-317`] (confidence:
  medium)
- **Constraint on alternatives**: there is no account, no server and no cloud relay, and adding
  one is "a constitutional change, not a feature". The published privacy policy promises the
  same. The runtime uses Apple frameworks only. The requester is open to a server, an account or
  an internet relay if it makes the experience better. — [source:
  `.specify/memory/constitution.md:68-76, 95-96`; `docs/privacy/index.html:7,98,128`; requester,
  2026-11-10] (confidence: high)

## Data & Constraints

**How sharing is built today**

- **A star.** Guests hold one link, to the host. The host holds all of them and passes each
  guest's points on to the others. — [source: `RekkertSync/LocalNetworkTransport.swift:17`;
  `specs/001-fix-session-sharing/research.md:231-245`] (confidence: high)
- **Host cost grows with every guest.** Each guest has its own encryption, so every frame is
  sealed, split into chunks and queued separately for each guest, through one transmit queue
  shared by all of them. Each point therefore takes N times the host's airtime for N guests. —
  [source: `RekkertSync/Radio/HubScheduler.swift:3-7`; `RekkertSync/BluetoothTransport.swift:215`
  (`updateValue … onSubscribedCentrals: [target]`); `specs/001-fix-session-sharing/research.md:144-146`]
  (confidence: high)
- **Guests write to the host with acknowledgement** (`.withResponse`). — [source:
  `RekkertSync/BluetoothTransport.swift:359`] (confidence: high; what this costs in delay is
  unmeasured)
- **The connection latency is never set.** Apple's header says that without it, the latency the
  central picked when it connected is used. — [source: no `setDesiredConnectionLatency` call in
  `BluetoothTransport.swift`; `CoreBluetooth.framework/Headers/CBPeripheralManager.h:205-217`]
  (confidence: high)
- **Both radios run at once on the phone.** The local network (with peer-to-peer Wi-Fi, which
  "works with no network at all") and Bluetooth are both attached, and "a peer on both hears
  everything twice". With Wi-Fi switched on but no venue network, phones may already be
  sharing over peer-to-peer Wi-Fi as well as Bluetooth. Spec 001's planned field test had Wi-Fi
  switched off. — [source: `Shared/AppModel.swift:66-76`;
  `RekkertSync/LocalNetworkTransport.swift:467-469`; `specs/001-fix-session-sharing/quickstart.md:82`]
  (confidence: high)
- **The guest's watch.** It follows through its own phone. Only when that phone has been out of
  touch for 15 s does the watch open a link of its own to the host, and watchOS allows that only
  while the app is in front or a workout is running. While joining, the phone and watch both
  dial the host at once. — [source: `README.md:365-378`] (confidence: high)
- **Timers.** A guest says hello after 10 s of silence, and the host probes every 15 s. The
  fan-out's per-link timeout is 4 s, and the store retries every 4 s. — [source:
  `RekkertSync/Radio/LinkLiveness.swift:9-10`; `RekkertSync/FanOutTransport.swift:97`;
  `RekkertSync/MatchStore.swift:192-196`] (confidence: high)
- **Older versions.** The radio handshake is versioned (`version = 3`), and older builds already
  count one each toward the limit. The requester accepts breaking changes. — [source:
  `RekkertSync/Radio/RadioCore.swift:17`; `CapacityTests.swift:70`; intake.md] (confidence: high)

**Targets compared with what exists**

| | Today (spec 001) | Requested (intake) |
|---|---|---|
| People on a match | host + 7 | host + 9 at least |
| Delay | 95% of points ≤ 5 s, all ≤ 30 s (FR-002) | ≤ 1 s when nothing is wrong, 1–2 s now and then |
| Battery | no limit, to be measured (never done) | a watch still lasts a full day with a 2-hour session |
| Measured on real devices | nothing | — |

**Platform limits**

- **How many centrals one iPhone serves as a peripheral is undocumented.** The CoreBluetooth
  headers state no limit. Old reports on Apple's mailing list and Stack Overflow mention about
  10, and Bluetooth misbehaving system-wide under many connections. — [source: installed
  `CoreBluetooth.framework/Headers`; web search results from lists.apple.com and a Stack
  Overflow mirror, 2013–2015, not fetched] (confidence: low)
- **A watchOS app can connect to two BLE peripherals at once.** This limits the watch only as a
  central, and a standing-in watch needs one link. — [source: Apple Developer Forums thread
  738861, web search result, not fetched] (confidence: low)
- **Crowded 2.4 GHz.** In lab studies, BLE throughput drops as more BLE devices work at the same
  time, and Wi-Fi activity cut it by about 30%. Loss shows up as retransmissions and higher
  latency, and apps get no feedback from the controller about either. No study of a hall full
  of phones was found. — [source: Ancans et al. 2019 (edi.lv) and Spörk et al., EWSN 2019 (via
  search summaries, not fetched)] (confidence: low–medium)
- **Platform floors**: iOS 26, watchOS 10 (SE 1st generation, Series 4 and 5 included). —
  [source: `.specify/memory/constitution.md:86-89`; `Packages/RekkertKit/Package.swift`]
  (confidence: high)

**Sharing records from 4, 8 and 9 November**

These were exported on 2026-11-10 from the host's phone (57FA) and one guest's phone (255B),
both on Rekkert 1.1 (75) and iOS 27.0.1. The requester supplied them, and they are not stored in
the repository. Devices are named by the first four characters of their ID.

| | 4 Nov | 8 Nov | 9 Nov |
|---|---|---|---|
| Sharing on (host) | 18:00–19:35 | 15:58–18:15 (last guest entry) | 18:00–20:00 |
| Guest devices seen | 255B, 7729, B701, 17CF, FE77, 5208, BE08 | B701 only | B701, 255B, 7729, 17CF; 1D55 for the first 7 min |
| Link drops on the host: B701 | 35 | 247 | 141 |
| Link drops on the host: 255B | 7 | — | 103 |
| Link drops on the host: 7729 | 10 | — | 29 |
| Times a guest went unheard for 15 s | 102 | 89 | 61 |

- **The slowdown happened below the cap.** On 9 November, at most five guest devices were on,
  and only four after 18:07. — [source: host record, 9 Nov] (confidence: high)
- **The links dropped about once a minute.** Guest 255B's link lasted a median of 43 s
  (90th percentile 127 s) before dropping, 103 times in 111 minutes. On 4 November it dropped
  7 times. A drop took a median of 4.1 s to come back (90th percentile 10.9 s), and twice nearly
  3 minutes (18:13 and 18:28). In all, that link was down about 14 of the 111 minutes. —
  [source: guest record, 4 and 9 Nov] (confidence: high)
- **It is always a guest's second link that drops.** On 9 November, every drop for B701, 255B
  and 7729 (273 in all) took a guest from two links to one. None of them was ever left with no
  link at all, which is why the guest never lost the host for 15 s. On 8 November, 232 of
  B701's 247 drops did the same. — [source: host record, links counted up and down per guest]
  (confidence: high)
- **Guests with a single link hardly dropped.** 17CF held one link from 18:09 until the host's
  Bluetooth restart at 19:54, with no drop. On 4 November, 255B and 7729 had one link for
  95–98% of the evening and dropped 7 and 10 times, mostly in the few minutes they had two. —
  [source: host record, 4 and 9 Nov] (confidence: high)
- **The steady single link was Bluetooth, so the dropping one is most likely the local
  network.** 17CF's only link went down with the host's Bluetooth at 19:54. Only the Bluetooth
  core records a drop as `radioOff`, so that link was Bluetooth. A guest's second link can only
  come from the local network (peer-to-peer Wi-Fi), which the phone runs alongside Bluetooth.
  The record does not name the radio, so this is an inference. It also cuts against the
  requester's guess that Bluetooth interference was the cause. — [source: host record;
  `RekkertSync/Radio/RadioCore.swift:750`; `Shared/AppModel.swift:66-76`] (confidence: medium)
- **On 9 November most guests had Wi-Fi on.** Three of four guests held a second link, which
  needs the local network. This matches the requester's impression that most had Wi-Fi
  switched on. — [source: host record; requester, 2026-11-10] (confidence: medium)
- **Neither app hung up; the link failed underneath them.** 88 of the guest's 104 drops have a
  matching drop on the host within 2 s. Both ends record them as "closed by the other side", and
  neither logged hanging up, writing the other off or redialling during the match. The app
  records "closed by the other side" for any Bluetooth disconnect, and for any local-network
  link that closes after it was up. The local network gives up on a link after about 8 s of
  unanswered keepalives. — [source: both records; `RekkertSync/Radio/RadioCore.swift:797,907`;
  `RekkertSync/LocalNetworkTransport.swift:462-465,623`] (confidence: medium-high)
- **About a third of the drops hit two guests at once.** 42 of B701's 141 drops fell within
  1 s of one of 255B's. Moving 255B's times by 37 s to 10 minutes gives only 3–5 such
  coincidences, so these are not chance: something shared (the host, or the air around it)
  caused at least these drops. — [source: host record, 9 Nov] (confidence: high for the count;
  the cause is unknown)
- **The drops do not grow with the number of guests.** On 8 November, a single guest dropped
  247 times in about 2¼ hours, more often than any guest on 9 November with four on.
  4 November had the most devices and the fewest drops. The 8 November session was in a hall,
  with the host and B701 always partners and close together, so distance was not the cause. —
  [source: host record, 4, 8 and 9 Nov; requester, 2026-11-10] (confidence: high for the
  counts)
- **B701 drops the most on every day.** It is a friend's iPhone 18 Pro, believed to be on the
  latest iOS and paired with an Apple Watch Ultra 2. — [source: requester, 2026-11-10]
  (confidence: medium)
- **The drops did not jump at any point in the evening.** Counted in 10-minute steps, B701 and
  255B dropped steadily, about once a minute each, from 18:00 to 19:50. The requester puts the
  other people's arrival at roughly 19:45, but neither drops nor 15-second silences rose after
  that. — [source: host record, 9 Nov; requester, 2026-11-10] (confidence: high for the counts;
  low for the arrival time)
- **No gap reached 15 s from the host, and gaps from guests were no worse than on 4 November.**
  The guest never logged the host as out of reach on either day. The host logged guests as
  unheard for 15 s fewer times on 9 November (61) than on 4 November (102), each lasting a
  median of 2 s beyond the 15 s. Whatever felt slow was shorter than 15 s, and the release build
  cannot show it, because it records each point's delay only in debug builds. — [source: both
  records; `RekkertSync/SharedSession.swift:667-682`; `RekkertSync/MatchStore.swift:2143-2147`]
  (confidence: high)
- **The host's Bluetooth went off for 2 s at 19:54:20, and nobody switched it off.** All four
  guests dropped with `radioOff` and were back within 7 s. The system turned Bluetooth off and
  on by itself, which fits old developer reports of Bluetooth restarting under load. The
  requester thinks sharing got really slow around then, but the record shows no other change
  in that period. — [source: host record, 9 Nov; requester, 2026-11-10] (confidence: high that
  it happened; why is unknown)

**Battery**

- Nobody has measured battery use while sharing on either device. — [source:
  `specs/001-fix-session-sharing/tasks.md:469` (T078 deferred); `spec.md:428` (SC-012)]
  (confidence: high)
- Spec 001 rejected keeping the app alive in the background, in part because of battery. —
  [source: `specs/001-fix-session-sharing/research.md:197-198`] (confidence: high)
- The requester's bar today: the watch lasts a full day with a 2-hour padel session. —
  [source: intake.md] (confidence: medium; one person's experience, no numbers)

## Evidence Against the Idea

- **The real ceiling may be below nine guests on today's design.** Seven was never measured,
  and nothing shows the host's single shared queue can carry even seven within FR-002 on real
  devices. Raising the number without measuring risks repeating the 2026-10-26 incident, where
  an uncapped host starved its guests. — [source: `specs/001-fix-session-sharing/research.md:63-116,
  276-284, 432-438`] (confidence: medium)
- **More guests and faster updates pull against each other in a star.** Host airtime per point
  grows linearly with guests. The requested ≤1 s is five times tighter than today's 95% target,
  on a radio that already slowed down in a crowded hall with eight or fewer people. —
  [source: code above; intake.md] (confidence: medium; the slowdown's cause is unverified)
- **The demand signal is thin.** It comes from one requester, with no usage data to show how
  often groups of more than eight happen, or how many people in such a group actually join. —
  [source: intake.md; constitution V] (confidence: medium)
- **The battery goal cannot be checked yet.** There is no baseline. Spec 001 chose to not limit
  battery, and the measurement it planned was skipped. — [source: as above] (confidence: high)
- **The slowdown looks like a separate problem from the cap.** The links dropped about once a
  minute with four guests on, and even more often with one guest on 8 November. The link that
  dropped was most likely the local network, not Bluetooth. Raising the limit does nothing about
  that. More guests also means more reconnections on the host, all
  through its one shared queue (that this adds delay is an ASSUMPTION). — [source: sharing
  records above] (confidence: medium)
- **Some likely paths cost a lot.** Spec 001 itself called L2CAP "a much larger change". Wi-Fi
  Aware needs per-device pairing with a PIN and does not run on watchOS. A server or internet
  relay needs a constitutional amendment, a new privacy policy and mobile data at court, though
  the requester is willing to pay that if it helps. — [source: research.md:226-229; WiFiAware
  swiftinterface; constitution; `docs/privacy/index.html`]
  (confidence: medium) *(recorded as cost evidence, not as options to pick from)*

## Gaps & Open Questions

- [NEEDS CLARIFICATION: How many centrals does one iPhone hold as a peripheral in practice, and
  at what point does delivery start to slip? Only a real-device test answers this; spec 001's
  T078 is the closest plan.]
- [NEEDS CLARIFICATION: Is the dropping link really the local network? The records point that
  way, but the sharing record names the device on each link, not the radio.]
- [NEEDS CLARIFICATION: Does a second link that keeps dropping slow down points on the steady
  one? The guest never lost the host entirely, yet sharing felt slow.]
- [NEEDS CLARIFICATION: Why did the host's Bluetooth restart by itself at 19:54 on 9 November?]
- [NEEDS CLARIFICATION: How long did points take to arrive? Release builds do not record it;
  only debug builds log each point's delay.]
- [NEEDS CLARIFICATION: Partly answered: most guests seem to have had Wi-Fi switched on (no
  network joined), so "no Wi-Fi" in the intake means "no venue network", not "Wi-Fi off". Which
  guests had it on is only inferred from the records.]
- [NEEDS CLARIFICATION: How fast is sharing today on real devices? No measured delay exists,
  only FR-002's targets and the simulation.]
- [NEEDS CLARIFICATION: How much battery does sharing use today, on the phone and the watch?
  No baseline exists to hold the new bar against.]
- [NEEDS CLARIFICATION: Of 10 people at a two-court evening, how many join with a phone, and how
  many with a watch standing in?]
- [NEEDS CLARIFICATION: Can the simulation be calibrated from a smaller real-device run (for
  example a host and three guests) before anyone tries 9 guests on court?]
- Carried over from intake: is 10 a floor or the target; does the battery bar cover phones;
  what delay is acceptable when things go wrong.

## Sources

**Repository (read directly)**

- `specs/001-fix-session-sharing/research.md`, `spec.md`, `tasks.md`, `quickstart.md`
- `specs/003-apple-watch-se-support/validation.md`, `specs/004-match-end-sharing-prompt/validation.md`
- `.specify/memory/constitution.md`
- `README.md`
- `Shared/AppModel.swift`
- `Packages/RekkertKit/Sources/RekkertCore/Sync/ParticipantState.swift`, `LinkRecord.swift`
- `Packages/RekkertKit/Sources/RekkertSync/BluetoothTransport.swift`, `LocalNetworkTransport.swift`,
  `FanOutTransport.swift`, `MatchStore.swift`, `Radio/HubScheduler.swift`, `Radio/LinkLiveness.swift`,
  `Radio/RadioCore.swift`
- `Packages/RekkertKit/Tests/RekkertSyncTests/SimulatedRadio.swift`, `CapacityTests.swift`
- GitHub issues on the repository, via `gh issue list` (host: github.com, policy: allowlisted)
- `RekkertSync/Radio/RadioCore.swift`, `RekkertSync/SharedSession.swift` (where drops and reach are recorded)

**Sharing records (supplied by the requester, read locally, not stored in the repository)**

- `rekkert-sharing-2026-11-10_host.txt`: host phone 57FA, 2026-11-03 to 2026-11-10, 5,137 lines
- `rekkert-sharing-2026-11-10_guest.txt`: guest phone 255B, 2026-11-03 to 2026-11-10, 340 lines

**Installed Xcode SDK (read locally)**

- `iPhoneOS.sdk/.../MultipeerConnectivity.framework/Headers/MCSession.h`
- `iPhoneOS.sdk/.../CoreBluetooth.framework/Headers/CBPeripheralManager.h`
- `iPhoneOS.sdk/.../WiFiAware.framework/Modules/WiFiAware.swiftmodule/arm64e-apple-ios.swiftinterface`

**Web (seen as search results only; no page was fetched)**

- https://lists.apple.com/archives/bluetooth-dev/2013/Mar/msg00001.html (host: lists.apple.com, policy: not fetched — search result)
- https://lists.apple.com/archives/bluetooth-dev/2013/Jul/msg00026.html (host: lists.apple.com, policy: not fetched — search result)
- https://developer.apple.com/forums/thread/738861 (host: developer.apple.com, policy: not fetched — search result)
- https://kaweah.freedombox.rocks/kiwix/content/stackoverflow.com_en_all_2023-11/questions/32663357/cannot-connect-third-device-to-appletv-via-bluetooth (host: kaweah.freedombox.rocks, a Stack Overflow mirror, policy: not fetched — search result)
- https://www.edi.lv/wp-content/uploads/2019/08/4578-18845-2-RV_AA_JO_AE2.pdf (host: www.edi.lv, policy: not fetched — search result)
- https://www.ewsn.org/file-repository/ewsn2019/023_034_spork.pdf (host: www.ewsn.org, policy: not fetched — search result)
- https://devzone.nordicsemi.com/f/nordic-q-a/18921/2-4-ghz-bandwidth-utilization-in-crowded-environments/73119 (host: devzone.nordicsemi.com, policy: not fetched — search result)
- https://developer.apple.com/documentation/wifiaware (host: developer.apple.com, policy: not fetched — search result)
- https://developer.apple.com/videos/play/wwdc2025/228 (host: developer.apple.com, policy: not fetched — search result)
- https://developer.espressif.com/blog/2026/08/wifi-aware-esp-to-iphone/ (host: developer.espressif.com, policy: not fetched — search result)
- https://mwm.ai/apps/padelgod/6775103879 (host: mwm.ai, policy: not fetched — search result)
- https://apps.apple.com/app/id6742737363 (host: apps.apple.com, policy: not fetched — search result)
- https://apps.apple.com/app/id6761060281 (host: apps.apple.com, policy: not fetched — search result)
