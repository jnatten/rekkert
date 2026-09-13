import RekkertCore
import SwiftUI
import UIKit

/// The phone propped at the side of the court: the score as large as the screen allows, at
/// full brightness, and the display kept awake.
struct FullscreenScoreView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var round: Int?
    var court = 0
    var mirrored = false

    private var layout: ScoreboardLayout { ScoreboardLayout(isMirrored: mirrored) }

    @State private var display = DisplayOverride()
    @State private var showingControls = true
    @State private var hideControlsAt = Date()
    private let controlsLinger: TimeInterval = 4

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if let snapshot {
                    HStack(spacing: 3) {
                        ForEach(layout.order, id: \.self) { side in
                            half(side, snapshot: snapshot, in: geometry.size, insets: geometry.safeAreaInsets)
                        }
                    }
                    .ignoresSafeArea()

                    overlay(snapshot)
                } else {
                    ContentUnavailableView("Nothing to show", systemImage: "sportscourt")
                        .preferredColorScheme(.dark)
                }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear { display.engage() }
        .onDisappear { display.restore() }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app at full brightness would be rude; take it back and reapply
            // when it returns.
            phase == .active ? display.engage() : display.restore()
        }
    }

    private var snapshot: ScoreboardSnapshot? {
        model.store.state.flatMap { ScoreboardSnapshot.make(from: $0, round: round, court: court) }
    }

    private func half(
        _ side: TeamSide,
        snapshot: ScoreboardSnapshot,
        in size: CGSize,
        insets: EdgeInsets
    ) -> some View {
        ZStack {
            Color.team(side)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.white.opacity(snapshot.serving == side ? 0.9 : 0))
                        .frame(width: 12, height: 12)
                    Text(snapshot.teamNames[side])
                        .font(.system(size: min(size.height * 0.06, 34), weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(.white.opacity(0.9))
                // The colour bleeds under the island; the writing must not.
                .padding(.top, insets.top + size.height * 0.02)

                Spacer(minLength: 0)

                // Above the number for them, below it for us, matching the court in front
                // of you: their end is the far one.
                serveSlot(snapshot, side: side, showing: side == .b, in: size)

                Text(snapshot.primary[side])
                    .font(.system(size: numberSize(in: size), weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)
                    .contentTransition(.numericText())

                serveSlot(snapshot, side: side, showing: side == .a, in: size)

                Spacer(minLength: 0)

                // Leaves room for the controls, which sit along the bottom.
                Color.clear.frame(height: insets.bottom + 44)
            }
            .padding(.horizontal, 8)
        }
        .contentShape(.rect)
        .onTapGesture {
            guard !snapshot.isLocked else { return }
            model.store.tap(round: round ?? 0, court: court, team: side)
            revealControls()
        }
        .animation(.snappy, value: snapshot.primary[side])
    }

    private func serveSlot(
        _ snapshot: ScoreboardSnapshot,
        side: TeamSide,
        showing isThisEnd: Bool,
        in size: CGSize
    ) -> some View {
        ServeSideSlot(
            court: snapshot.serving == side && isThisEnd ? snapshot.servingCourt : nil,
            fromAcrossTheNet: side == .b,
            height: min(size.height * 0.028, 17)
        )
        .foregroundStyle(.white.opacity(0.9))
        .padding(.vertical, 4)
    }

    private func numberSize(in size: CGSize) -> CGFloat {
        min(size.width * 0.42, size.height * 0.78)
    }

    /// Fades out so the score is unobstructed once the phone is set down, and comes back on
    /// a tap anywhere.
    @ViewBuilder
    private func overlay(_ snapshot: ScoreboardSnapshot) -> some View {
        VStack {
            Spacer()

            HStack(alignment: .center, spacing: 10) {
                controlButton("xmark", label: "Leave full screen") { dismiss() }
                    .opacity(showingControls ? 1 : 0.4)

                Spacer(minLength: 0)

                Text(detail(snapshot))
                    .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.45), in: .capsule)

                Spacer(minLength: 0)

                controlButton("arrow.uturn.backward", label: "Undo") {
                    model.store.undoLast()
                    revealControls()
                }
                .opacity(showingControls ? 1 : 0.4)
                .disabled(!model.store.canUndo)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .animation(.easeInOut(duration: 0.35), value: showingControls)
        .onAppear { revealControls() }
    }

    private func controlButton(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.45), in: .circle)
        }
        .accessibilityLabel(label)
    }

    private func detail(_ snapshot: ScoreboardSnapshot) -> String {
        guard let games = snapshot.games else { return snapshot.detail }
        let previous = snapshot.completedSets.map {
            let shown = layout.asShown($0.games)
            return "\(shown.left)-\(shown.right)"
        }
        let current = layout.asShown(games)
        return (previous + ["\(current.left)-\(current.right)"]).joined(separator: "  ")
            + "   ·   " + snapshot.detail
    }

    /// Dims the controls again after a while so the score is clean, but never all the way
    /// — they have to stay findable without scoring a point to go looking for them.
    private func revealControls() {
        showingControls = true
        let deadline = Date().addingTimeInterval(controlsLinger)
        hideControlsAt = deadline
        Task {
            try? await Task.sleep(for: .seconds(controlsLinger))
            if hideControlsAt <= deadline { showingControls = false }
        }
    }
}

/// Full brightness and no auto-lock while the score is on show, both put back afterwards.
@MainActor
@Observable
final class DisplayOverride {
    private var previousBrightness: CGFloat?

    func engage() {
        guard previousBrightness == nil, let screen else { return }
        previousBrightness = screen.brightness
        screen.brightness = 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func restore() {
        if let previousBrightness, let screen {
            screen.brightness = previousBrightness
        }
        previousBrightness = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .screen
    }
}
