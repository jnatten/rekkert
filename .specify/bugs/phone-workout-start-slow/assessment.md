# Bug Assessment: Starting a workout from the iPhone is slow and sometimes never starts

- **Slug**: phone-workout-start-slow
- **Created**: 2026-11-01
- **Source**: pasted text
- **Verdict**: valid
- **Severity**: high

## Report (verbatim or summarized)

> There seems to be a problem when starting a workout on the phone.
> Its slow. Maybe because it needs to communicate with the watch before starting?
> I feel sometimes it doesnt start?

## Symptom

Pressing **Start a workout** on the iPhone (Home screen workout section, or the match options menu) takes a long time to show the workout as running, and sometimes it never does. The phone shows nothing while it waits and no reason when it fails. Expected: the button shows that a start is under way, the workout is running on the watch within a few seconds, and if it cannot start, the phone says why.

The reporter's guess is right. The phone cannot hold a workout. It asks the watch to start one, and the phone's button changes only when the watch's `.running` signal comes back.

## Reproduction

Path A: the start never happens (regression since `b08f8c2`, 2026-10-27)

1. On the watch, make Rekkert's watch-side Health request status anything other than "already asked". This happens on a fresh install where only the iPhone has been through Health's sheet, or after an update adds a Health type to `HealthDisclosure.read(on: .watch)` / `saved(on: .watch)`. It also happens whenever `statusForAuthorizationRequest` throws, which `askStatus` turns into `.unknown`.
2. Make sure the watch app is not on screen (wrist down, or another app in front).
3. On the iPhone, tap **Start a workout**.
4. Observed: the phone keeps showing "Start a workout" with no message. The watch app was launched in the background and is sitting on its Health explainer. When the watch app is next opened, the explainer appears, and tapping through it starts a workout, possibly long after the phone press.

Path B: the start fails on the watch and the phone says nothing

1. Start a workout in Apple's Workout app on the watch (or revoke Rekkert's Workouts sharing permission).
2. On the iPhone, tap **Start a workout**.
3. Observed: the watch sets its own `failure` ("Another workout is running") and publishes `.idle`. The phone hears `.idle` and still shows "Start a workout" with no reason.

Path C: slow start with nothing on screen

1. With the watch app not running, tap **Start a workout** on the iPhone.
2. Observed: several seconds with no change on the phone, then the button flips to "Stop the workout".

[NEEDS CLARIFICATION: When it "doesn't start", did a Rekkert explainer ("Rekkert uses Apple Health…") show up the next time the watch app was opened? That would confirm Path A. Did the watch show "Another workout is running" or "Couldn't start"? That would confirm Path B.]

[NEEDS CLARIFICATION: Roughly how long is "slow": 2–3 s, around 10 s, or longer? Can you tell whether the watch had started (workout page showing on the wrist) before the phone caught up?]

The sharing record (`LinkRecorder`, reached from Settings on the phone, which receives the watch's days too) notes `launched(background)` and the pair being `proven`. It can show how long the watch took to launch and reach the phone around a failed press.

## Suspected Code Paths

- `WatchApp/Sources/WorkoutController.swift:224` `handle(_:)`: the entry point for a phone-started workout. It calls `start()`, so the background launch goes through the same explainer gate as a press on the wrist.
- `WatchApp/Sources/WorkoutController.swift:146` `ask(_:)`: added in `b08f8c2`. If `HealthAsk.explainFirst(await health.askStatus(on: .watch))` is true, it sets `explaining = .start` and returns. Nothing is published, and the watch app is in the background where nobody can see the explainer. Before `b08f8c2`, `start()` went straight to `requestAuthorization` + `begin()`.
- `Shared/HealthTypes.swift:42` `askStatus(on:)` and `Packages/RekkertKit/Sources/RekkertCore/Health/HealthAsk.swift` `explainFirst`: any status other than `.alreadyAsked`, including `.unknown` from a thrown status query, means "explain first".
- `Packages/RekkertKit/Sources/RekkertCore/Health/HealthDisclosure.swift`: the phone asks for `[.workout]` share and nothing to read. The watch asks for four shared and seven read types. Going through the phone's explainer and sheet does not cover the watch's set, so a watch that has never shown Health's sheet itself returns `.wouldAsk`.
- `WatchApp/Sources/WorkoutController.swift:627` `stopped(with:)`: a failed `begin()` sets the reason on the watch only and publishes `.idle`, so the phone never learns why.
- `App/Sources/WorkoutController.swift:70` `start()` → `:106` `launch()`: three Health round trips in a row: `askStatus`, then `requestAuthorization` (redundant once `askStatus` said `.alreadyAsked`), then `startWatchApp(toHandle:)`. It sets `failure` only if `startWatchApp` throws. It has no "starting" state, and `isTracking` flips only in `heard(.running)` (`:149`).
- `App/Sources/Views/HomeView.swift:122` and `App/Sources/Views/MatchOptionsMenu.swift:57`: the button's title and icon follow only `isTracking`, so between press and `.running` the phone looks as though nothing happened, which invites a second tap. The comment in `MatchOptionsMenu.swift` accepts "a button that takes its time", but nothing shows that it is taking it.
- `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift:2136` `send(_ signal: WorkoutSignal)`: `.running` is sent live only, by design.
- `Packages/RekkertKit/Sources/RekkertSync/WatchConnectivityTransport.swift:213` `isReachable` / `:227` `sendLive`: `sendLive` returns `nil` immediately unless `WCSession` is `.activated` and reachable. On a cold background launch, `transport.activate()` has only just been called from `MatchStore.run()` (`:1110`), so a `.running` published right after `begin()` can be dropped.
- `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift:2213` `shareWorkoutOnReconnect()`: the only retry for a dropped `.running`. It is called only when a `.hello` from the paired device reaches the watch (`:1575`), which waits on the phone noticing the watch is reachable and starting its own sync round.

## Root Cause Hypothesis

**Sometimes doesn't start (high confidence the path exists; medium that it is the one the reporter hit).** Commit `b08f8c2` ("explain before asking") put an explainer in front of Health's permission sheet on the watch. Because `handle(_:)` reuses `start()`, a workout started from the phone now also waits on that explainer. When the watch's own request status is not `.alreadyAsked`, the start is parked in `explaining = .start` on an app that the system launched in the background. Nobody sees the explainer, nothing is published, and the phone keeps offering "Start a workout". The start goes ahead only when someone opens the watch app and taps through. That fits "sometimes": once the watch has shown Health's sheet, later starts go through, until an update adds a Health type or the status query fails. Separately, every failure inside `begin()` is reported only on the wrist (Path B), so a refused start looks the same on the phone as a lost one.

**Slow (medium confidence).** Some of the delay is inherent: `startWatchApp(toHandle:)` has to cold-launch the watch app over Bluetooth, which Rekkert cannot speed up. The app adds to it. The steps run strictly one after another across two devices: two Health round trips on the phone, a full `AppModel` init and start on the watch, two more Health round trips there, then `begin()`. The `.running` that comes back is live-only. On a cold launch, `WatchConnectivityTransport.isReachable` is often still false, so the first `.running` can be dropped and arrive only after the phone's next hello triggers `shareWorkoutOnReconnect()`. Through all of this the phone shows no "starting" state, so even a normal delay looks like a failure.

## Proposed Remediation

**Preferred**:

1. **Watch: don't wait on the explainer for a phone-started workout.** In `handle(_:)`, skip `ask(.start)`. If `authorizationStatus(for: .workoutType()) == .sharingAuthorized`, call `begin()` directly, as `start()` did before `b08f8c2`. No sheet can appear in the background anyway, and a read that hasn't been granted only leaves the heart-rate glyph empty. If sharing isn't authorized, keep `explaining = .start` for the next time the app is opened, and also tell the phone (step 2) instead of staying silent. Put the decision in `RekkertCore` next to `HealthAsk` (for example, a rule that takes the status and whether the start came from the phone) so it can be unit-tested. The app targets have no test target.
2. **Phone: show the start in progress and time it out.** Add an `isStarting` state to `App/Sources/WorkoutController.swift`. Set it before `startWatchApp`, clear it on `.running`, `.paused` or `.idle`, and show it in `HomeView` and `MatchOptionsMenu` (for example "Starting on your Apple Watch…", with the button disabled). If no `.running` arrives within a deadline after `startWatchApp` succeeds (around 15 s), clear it and set `failure` to something like "Check your Apple Watch". Also skip the phone's `requestAuthorization` when `askStatus` has just returned `.alreadyAsked`. This needs no wire change and also covers Path B and a dropped `.running`.
3. **Watch → phone: say `.running` again as soon as the pair is reachable.** In `MatchStore`, when pair reachability goes from false to true (`consumeReachability`), re-send `announcedWorkout` itself instead of waiting for a hello from the phone. This shortens the gap after a cold launch without queuing anything, so the live-only rule in `send(_:)` stays as it is.

**Alternatives** (optional):

- Add a wire signal, for example `WorkoutSignal.couldNotStart(reason)` or `.waitingOnWatch`, so the phone can show the watch's actual reason (another workout running, Health access off, waiting on the explainer). This gives more precise messages than a timeout, but it changes `Wire` and needs `WireCompatibilityTests` and a decision about what older phones and watches do with an unknown case. It is worth doing after step 2, not instead of it.
- Revert the explainer gate on the watch entirely. This is the simplest change, but it undoes App Review-driven work from `002-healthkit-ui-disclosure`. Rejected.
- Pre-warm the watch app, or keep WCSession activation from blocking. `startWatchApp` latency is Apple's, and there is little to gain there beyond step 3.

**Files likely to change**:

- `WatchApp/Sources/WorkoutController.swift`
- `App/Sources/WorkoutController.swift`
- `App/Sources/Views/HomeView.swift`
- `App/Sources/Views/MatchOptionsMenu.swift`
- `Packages/RekkertKit/Sources/RekkertCore/Health/HealthAsk.swift`
- `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift`
- `Packages/RekkertKit/Tests/RekkertCoreTests/HealthAskTests.swift`
- `Packages/RekkertKit/Tests/RekkertSyncTests/WorkoutSyncTests.swift`

**Tests to add or update**:

- `HealthAskTests`: a start that arrives from the phone with sharing authorized goes straight on whatever the request status is (`.wouldAsk`, `.unknown`). One without sharing authorization still waits on the explainer.
- `WorkoutSyncTests`: a `.running` published while the pair is unreachable reaches the phone once the pair becomes reachable, without the phone having to send a hello first. Follow the pattern of `aReconnectIsToldTheLastThingSaidRatherThanTheFirst`.
- `WorkoutSyncTests` (keep green): `aRatingIsNotRepeatedOnReconnect` and the live-only rule for `.stop` / `.running` still hold, so nothing stale is queued.
- On a device: phone press with the watch app closed and its Health status not yet asked, checking that the workout starts on the wrist and the phone flips to running. Also a phone press while Apple's Workout app holds the session, checking that the phone shows a reason within the deadline.

## Risks & Considerations

- **App Review / Health disclosure**: the explainer exists because a review turned down a request with no lead-in. Step 1 must never let Health's sheet appear without the explainer. Calling `begin()` without `requestAuthorization` when sharing is already granted shows no sheet, but it should be checked against `specs/002-healthkit-ui-disclosure/contracts/identification-points.md`.
- **Read types added later**: if the watch never runs `requestAuthorization` on a phone-started workout, read types added in an update aren't asked for until the watch app is opened. `becameActive()` only calls `prepare()` when `workoutOnMatchStart != .off`. Consider calling it whenever the watch status isn't `.alreadyAsked`.
- **Timeout on the phone**: too short, and it reports a failure for a start that is about to land. The watch's later `.running` must clear `failure`, which `heard(.running)` already does. Too long, and the phone is still slow to say anything.
- **A second press while starting**: the phone's `start()` guard (`!isTracking, explaining == nil`) lets a second tap fire another `startWatchApp`. The watch's `isStarting` makes that harmless there, but `isStarting` on the phone should block it.
- **Re-announcing on reachability**: it must say the latest state (`announcedWorkout`) and never a request (`.stop`, `.pause`), as `send(_:)` already guarantees. That guarantee needs to stay true.
- **WorkoutFollower**: an automatic start on match start (`WorkoutFollower.perform(.start)`) goes through the same phone `start()`, so it benefits from the same fixes and shows the same "starting" state.

## Open Questions

- [NEEDS CLARIFICATION: On the occasions it didn't start, did the watch show Rekkert's Apple Health explainer when next opened, or an error such as "Another workout is running"?]
- [NEEDS CLARIFICATION: Was the build that showed this from on or after `b08f8c2` (2026-10-27)? If "doesn't start" was also seen before then, Path A cannot be the whole story.]
- [NEEDS CLARIFICATION: Roughly how many seconds is "slow", and was it slow even when the watch app was already open on the wrist?]
- [NEEDS CLARIFICATION: Should a phone-started workout with no sharing permission on the watch show the explainer on the wrist (if the app is in front) or only on the phone? This is a product choice for step 1.]
