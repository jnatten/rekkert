# Contract: Messages Between Devices (changes for 004)

**Feature**: [../spec.md](../spec.md) · **Data model**: [../data-model.md](../data-model.md) ·
**Builds on**: [spec 001's contract](../../001-fix-session-sharing/contracts/wire-protocol.md)

Devices on one shared evening may run different builds, so every change here is additive:
optional values on existing messages, and new pair-only signals. No message changes how a
match merges.

## Shared-session scope (phone ↔ phone, and a standing-in watch ↔ host)

| Message | Direction | Status | Contents / rule |
|---|---|---|---|
| `sharingStopped(sessionID, reason?)` | host → guests | **Extended, and accepted more widely** | `reason` (optional): `host` or `idle`. A guest now acts on it when it holds the named match, as before, **or** when it is a guest with an empty log, not joining, and the notice came on a non-pair link, whatever session it names (D-7). Either way it files nothing new (the last match is already filed), forgets the code, and shows the stop notice with the reason. |
| `access(ShareAccessTable)`, `snapshot(…, access?)` | host → guests, guest phone → its watch | **Extended** | The table carries `keptSharingAfter` (optional): the session after which the host answered Keep sharing. It travels with a revision bump, and arrives and is replayed the way the table already is (D-5). |
| `snapshot(log)` of the host's next match | host → guests | **Unchanged on the wire** | A guest that adopts it at MS:1853 now also opens a new-match notice (D-6). |
| A host with no match on answering a joining guest | host → guest | **Unchanged on the wire** | The host's answer to the guest's hello is its empty match, with the access list. The guest now completes its join on that answer, and becomes a waiting guest with the host's name, rather than waiting for a match to arrive (D-9). |
| `guestCard(device, name, pairedTo?, leaving?)` | guest → host | **Extended** | `leaving` (optional): `true` on the goodbye a guest sends on each host link before it cuts them, waiting up to 2 s. The host drops that guest, and its paired watch, from its list (D-16, FR-009). |

No new `Wire` case is added, so `Scope.sharedSession` and `keepsOverDelay` (FO:49-63,
256-264) only see the extended ones.

## Pair scope (`.sharing` channel, phone ↔ its own watch)

| Message | Direction | Status | Contents / rule |
|---|---|---|---|
| `sharing.answered(session, choice)` | either way | **New** | The end-of-match question or the new-match notice for `session` was answered on the other half, with `keepSharing`, `stopSharing`, `stay`, `leave` or `ok`. Sent durably: queued, and live when reachable. The receiver closes its own question or notice for that session within 10 s of hearing it (FR-005, FR-011, FR-013). It carries out nothing itself: Stop and Leave travel as they do today, as `stopHosting` and the leave path. |
| `sharing.newMatch(NewMatchNotice)` | guest phone → its watch | **New** | The host's next match arrived on the phone. The watch opens its own notice, with a tap on the wrist (FR-013), unless an `answered(session, …)` for it has already been heard. Sent durably. |
| `sharing.hostStoppedSharing(host?, reason?)` | phone → watch | **Extended** | `reason` (optional), so the watch can say "after 30 minutes without a match" |
| `sharing.hostingStatus(HostingStatus)` | phone → watch | **Extended** | `canShare` no longer needs a match on. `endedBy` (optional): `idle` when sharing stopped by itself, so the host's watch can tell its wearer. |
| `sharing.startHosting` | watch → phone | **Changed rule** | Honoured with no match on. Still refused on a guest's phone. |

The two new cases are added to `SharingSignal`. In `MatchStore.keepToSayAgain` they say
nothing again on reconnect, since the durable queue already carries them.

## Compatibility rules

1. **An older guest** ignores `reason` and `keptSharingAfter`, the way unknown keys are
   ignored today. It is not asked anything and keeps today's behaviour (FR-025). It still
   ignores a Stop between matches, as it does today.
2. **An older host** never sets `keptSharingAfter`, so a new guest asks only "stay or
   leave". An older host's Stop between matches names an empty log of its own. A new guest
   now accepts it under rule D-7, so the fix reaches mixed evenings too.
3. **An older watch or phone of the same pair** fails to decode `answered` and `newMatch`,
   and answers with a hello, as with any unknown kind (MS:1539-1543). Each half then asks on
   its own. The answers still take effect, since Stop and Leave travel as before. Watch and
   phone ship together, so this lasts only until both update.
4. **Decoding an older `hostStoppedSharing` or `sharingStopped`** gives a nil `reason`,
   which reads as `host`.
5. **The event format, the merge and the reducer are unchanged** (Principle II).
6. **An older host** ignores `leaving` on a guest card. The card reads as an ordinary one,
   so the leaver shows as out of reach after 15 s, as it does today.
7. **An older guest** sends no goodbye, so a new host shows it as out of reach when it
   leaves, as it does today.
