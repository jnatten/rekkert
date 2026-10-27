import RekkertCore
import RekkertSync
import SwiftUI
import WatchKit

/// The page to the right of the scoreboard: everything that ends something, kept off the
/// scoring screen so a stray tap cannot finish a round.
struct WatchMenuView: View {
    @Environment(AppModel.self) private var model
    @State private var confirming: Confirmation?
    @State private var choosingMe = false
    @State private var joiningAgain = false
    @State private var showingCode = false
    @State private var showingGuests = false
    @State private var confirmingStopSharing = false

    private enum Confirmation: String, Identifiable {
        case endRound, nextRound, finish, discard
        var id: String { rawValue }

        var question: String {
            switch self {
            case .endRound: "End this round?"
            case .nextRound: "Finish the round and draw the next?"
            case .finish: "Finish and save?"
            case .discard: "Call this off without saving?"
            }
        }

        var confirmLabel: String {
            switch self {
            case .endRound: "End round"
            case .nextRound: "Next round"
            case .finish: "Finish"
            case .discard: "Discard"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(model.store.state?.title ?? "Rekkert")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if case .tournament(let tournament)? = model.store.state, let plan = tournament.plan {
                    Text(plan.progress)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                status

                sharing

                WatchWorkoutButton()

                if isWinnerCourt, !isWarmingUp, model.store.canRunRounds {
                    action("End round", systemImage: "flag.pattern.checkered", tint: .orange) {
                        confirming = .endRound
                    }
                }
                if case .tournament(let tournament)? = model.store.state {
                    if model.store.canRunRounds, !isWarmingUp, tournament.isLadder, let round = tournament.currentRound,
                       !round.isCancelled, !round.isEnded {
                        if let clock = round.clock {
                            action(clock.isPaused ? "Resume" : "Pause", systemImage: clock.isPaused ? "play.fill" : "pause.fill") {
                                WKInterfaceDevice.current().play(.click)
                                if clock.isPaused { model.store.resumeRound() } else { model.store.pauseRound() }
                            }
                            action("Add 2 min", systemImage: "plus.circle") {
                                WKInterfaceDevice.current().play(.click)
                                model.store.snoozeRound(minutes: 2)
                            }
                        }
                        if !tournament.isDone(round) {
                            action("End round", systemImage: "flag.pattern.checkered", tint: .orange) {
                                confirming = .endRound
                            }
                        }
                    }
                    if finishesFirst {
                        action("Finish & save", systemImage: "stop.circle", tint: .red) {
                            confirming = .finish
                        }
                    }
                    if model.store.canRunRounds, !isWarmingUp {
                        action(
                            tournament.plan?.isReached == true ? "Another round" : "Next round",
                            systemImage: "arrow.right.circle.fill", tint: .blue
                        ) {
                            confirming = .nextRound
                        }
                        .disabled(tournament.isLadder && !tournament.canDrawNextRound)
                    }
                    action(
                        "Me: \(model.store.me.flatMap(tournament.player)?.name ?? "Not set")",
                        systemImage: "person.crop.circle"
                    ) {
                        choosingMe = true
                    }
                    .accessibilityHint("Only your court buzzes, and your team follows you each round")
                    .sheet(isPresented: $choosingMe) {
                        List {
                            Button("Nobody") { choose(nil) }
                            ForEach(tournament.players) { player in
                                Button(player.name) { choose(player.id) }
                            }
                        }
                    }
                }
                if model.store.canRunRounds, !isWarmingUp, let round = friendlyRound {
                    // One button, whichever the round is asking for: draw the next one when
                    // this is over, stop this one where it stands while it is not.
                    if round.isFinished {
                        action("Next round", systemImage: "arrow.right.circle.fill", tint: .blue) {
                            confirming = .nextRound
                        }
                    } else {
                        action("End round", systemImage: "flag.pattern.checkered", tint: .orange) {
                            confirming = .endRound
                        }
                        .disabled(!round.wasPlayed)
                    }
                }

                // This wrist. Cycles rather than opening a picker: the page is a column of
                // buttons rather than a form, and there are only three of them to walk past.
                action("Sides: \(model.sides.mode.title)", systemImage: model.sides.mode.symbol) {
                    WKInterfaceDevice.current().play(.click)
                    model.sides.mode = model.sides.mode.next
                }
                .accessibilityHint(sidesHint)

                // Whatever the mode, this means this watch: it takes it to manual and turns
                // the board from wherever it is now.
                action("Swap sides", systemImage: "rectangle.2.swap") {
                    WKInterfaceDevice.current().play(.click)
                    model.sides.flip(
                        from: layout,
                        display: model.store.display,
                        session: model.store.log.sessionID
                    )
                }

                // This wrist again, though it is set on the phone too. Mode only here: how
                // hard and whose points are set once and belong on the bigger screen.
                action("Buzz: \(model.store.haptics.mode.displayName)", systemImage: "hand.tap") {
                    WKInterfaceDevice.current().play(.click)
                    model.store.setHaptics(mode: model.store.haptics.mode.next)
                }
                .accessibilityHint(model.store.haptics.mode.explanation)

                // Flips the phone, not this watch: it is the phone that is propped up
                // somewhere with a side of the court in front of it.
                action("Swap phone sides", systemImage: "rectangle.2.swap") {
                    WKInterfaceDevice.current().play(.click)
                    model.store.toggleScoreboardMirrored()
                }

                if !isWarmingUp {
                    action("Undo", systemImage: "arrow.uturn.backward") {
                        WKInterfaceDevice.current().play(.retry)
                        model.store.undoLast()
                    }
                    .disabled(!model.store.canUndo)
                }

                if model.store.canEndSession {
                    if hasResults, !finishesFirst {
                        action("Finish & save", systemImage: "stop.circle", tint: .red) {
                            confirming = .finish
                        }
                    }

                    action(hasResults ? "Discard" : "Call it off", systemImage: "trash", tint: .red) {
                        confirming = .discard
                    }
                } else {
                    // The code dies with the app, and without the phone to repeat it the only
                    // way back to the host is typing it again.
                    if model.sharing.standbyCode == nil, !model.sharing.isSharing, !model.store.isPairReachable {
                        action("Join again", systemImage: "arrow.right.circle") {
                            joiningAgain = true
                        }
                    }

                    // Somebody else's match: step off it rather than end it for them.
                    action("Leave", systemImage: "rectangle.portrait.and.arrow.right") {
                        WKInterfaceDevice.current().play(.click)
                        model.sharing.leave()
                    }
                }

                CommitLabel()
                    .padding(.top, 4)
            }
            .padding(.horizontal, 2)
        }
        .sheet(isPresented: $joiningAgain) { WatchJoinView() }
        .sheet(isPresented: $showingCode) { NavigationStack { WatchCodeView() } }
        .sheet(isPresented: $showingGuests) { NavigationStack { WatchGuestsView() } }
        .confirmationDialog("Stop sharing? Everyone else leaves this match.", isPresented: $confirmingStopSharing, titleVisibility: .visible) {
            Button("Stop sharing", role: .destructive) {
                WKInterfaceDevice.current().play(.click)
                model.standIn.stopHosting()
            }
            Button("Cancel", role: .cancel) {}
        }
        // `presenting:` hands the pending action to the builder, so the button closure
        // captures it. Reading `confirming` inside the action instead would race the
        // dialog's own dismissal, which clears it — and the button would do nothing.
        .confirmationDialog(
            confirming.map(question) ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { pending in
            Button(
                pending.confirmLabel,
                role: pending == .finish || pending == .discard ? .destructive : nil
            ) {
                perform(pending)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// A friendly ends a round rather than a set, and draws rather than finishes — so the
    /// questions the dialog asks are its own.
    private func question(_ pending: Confirmation) -> String {
        if pending == .nextRound, case .tournament(let tournament)? = model.store.state,
           tournament.plan?.isReached == true {
            return tournament.length == .fullRotation
                ? "Everyone has partnered everyone. Play another round?"
                : "The planned rounds are played. Play another?"
        }
        if case .tournament(let tournament)? = model.store.state, tournament.isLadder {
            switch pending {
            case .endRound: return "End the round on every court?"
            case .nextRound: return "Draw the next round?"
            case .finish, .discard: return pending.question
            }
        }
        guard friendlyRound != nil else { return pending.question }
        switch pending {
        case .endRound: return "Stop this round where it stands?"
        case .nextRound: return "Draw the next round?"
        case .finish, .discard: return pending.question
        }
    }

    /// Once the planned rounds are played, finishing is what comes next.
    private var finishesFirst: Bool {
        guard case .tournament(let tournament)? = model.store.state else { return false }
        return tournament.plan?.isReached == true && model.store.canEndSession && hasResults
    }

    /// The host's: a match of the wrist's own, which the phone shares or can. None of it shows on
    /// a guest's watch (FR-020).
    @ViewBuilder
    private var sharing: some View {
        if model.store.state != nil, model.store.canEndSession {
            if model.standIn.hosting?.isSharing == true {
                action("Code", systemImage: "qrcode") { showingCode = true }
                action("Who's on", systemImage: "person.2") { showingGuests = true }
                action("Stop sharing", systemImage: "xmark.circle", tint: .red) { confirmingStopSharing = true }
            } else {
                action("Share match", systemImage: "square.and.arrow.up") {
                    WKInterfaceDevice.current().play(.click)
                    model.standIn.startHosting()
                    showingCode = true
                }
            }
        }
    }

    private var status: some View {
        VStack(spacing: 2) {
            // The two links apart (FR-011): its own phone, then the match.
            Label(
                model.store.isPairReachable ? "iPhone connected" : WatchStandIn.Status.phoneOutOfReach.line,
                systemImage: model.store.isPairReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash"
            )
            .foregroundStyle(model.store.isPairReachable ? .green : .secondary)

            ForEach(model.standIn.statuses.filter { $0 != .phoneOutOfReach }, id: \.line) { status in
                Label(status.line, systemImage: "applewatch.radiowaves.left.and.right")
                    .foregroundStyle(status == .onTheHostsPhone ? .green : .orange)
                    .multilineTextAlignment(.center)
            }
        }
        .font(.system(size: 11))
        .padding(.bottom, 2)
    }

    /// A tint paints the label as well as the pill, which on grey reads as a disabled
    /// button — so the plain ones go untinted, the watchOS default the scoreboard uses.
    /// The colours keep theirs: on those the tinted label is the point.
    private func action(
        _ title: String,
        systemImage: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .font(.footnote)
    }

    private func choose(_ player: PlayerID?) {
        WKInterfaceDevice.current().play(.click)
        model.store.setMe(player)
        choosingMe = false
    }

    private func perform(_ action: Confirmation) {
        switch action {
        case .endRound:
            WKInterfaceDevice.current().play(.success)
            model.store.endRound()
        case .nextRound:
            WKInterfaceDevice.current().play(.success)
            if case .tournament(let tournament)? = model.store.state, !tournament.isLadder,
               let round = tournament.currentRound {
                model.store.setRoundConfirmed(round.index, true)
            }
            model.store.nextRound()
        case .finish:
            WKInterfaceDevice.current().play(.success)
            model.finishSession()
        case .discard:
            WKInterfaceDevice.current().play(.success)
            model.discard()
        }
        confirming = nil
    }

    /// What the scoreboard page is drawing now, so "Swap sides" turns the board the wearer
    /// is actually looking at rather than one worked out a second way.
    private var layout: ScoreboardLayout {
        model.sides.layout(
            court: model.store.state
                .flatMap { ScoreboardSnapshot.make(from: $0, round: currentRoundIndex, court: 0) }?
                .endsSwapped ?? false,
            display: model.store.display,
            session: model.store.log.sessionID
        )
    }

    /// Named apart from the `round` a friendly binds above, which is the round itself.
    private var currentRoundIndex: Int {
        guard case .friendly(let session)? = model.store.state else { return 0 }
        return session.currentIndex
    }

    private var sidesHint: String {
        switch model.sides.mode {
        case .fixed: "Blue stays on the left"
        case .followPhone: "Turns over whenever the phone does"
        case .manual: "Turns over only when you say so"
        }
    }

    private var hasResults: Bool { !isWarmingUp && model.store.state?.hasResults ?? false }

    private var isWarmingUp: Bool { model.store.state?.warmingUpSince != nil }

    private var isWinnerCourt: Bool {
        if case .winnerCourt? = model.store.state { return true }
        return false
    }

    private var friendlyRound: FriendlyRound? {
        guard case .friendly(let session)? = model.store.state else { return nil }
        return session.currentRound
    }
}
