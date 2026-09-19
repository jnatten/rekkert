import RekkertCore
import SwiftUI
import UIKit

/// The phone propped at the side of the court: the score as large as the screen allows, at
/// full brightness, and the display kept awake.
struct FullscreenScoreView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.teamPalette) private var palette

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
                } else {
                    ContentUnavailableView("Nothing to show", systemImage: "sportscourt")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(.rect)
                        .onTapGesture { revealControls() }
                }

                overlay(snapshot)
            }
        }
        .announcesScore(snapshot)
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
            palette.color(side)
            serveCourt(snapshot, side: side, in: size, insets: insets)

            VStack(spacing: 0) {
                Text(snapshot.teamNames[side])
                    .font(.system(size: min(size.height * 0.06, 34), weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white.opacity(0.9))
                    // The colour bleeds under the island; the writing must not.
                    .padding(.top, insets.top + size.height * 0.02)

                Spacer(minLength: 0)

                Text(snapshot.primary[side])
                    .font(.system(size: numberSize(in: size), weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)
                    .contentTransition(.numericText())

                Spacer(minLength: 0)

                // Leaves room for the controls, which sit along the bottom.
                Color.clear.frame(height: insets.bottom + 44)
            }
            .padding(.horizontal, 8)
        }
        .animation(.snappy, value: snapshot.serving)
        .animation(.snappy, value: snapshot.servingCourt)
        .contentShape(.rect)
        .onTapGesture {
            // Woken before the lock is checked: a round that is over takes no more points,
            // but the way out still has to answer a tap on it.
            revealControls()
            guard !snapshot.isLocked else { return }
            model.store.tap(round: round ?? 0, court: court, team: side)
        }
        .animation(.snappy, value: snapshot.primary[side])
    }

    /// The team's two service boxes, drawn the size of the half itself so the lit one
    /// carries across a court. The phone is propped at the side, so the court runs up and
    /// down the screen rather than across it.
    private func serveCourt(
        _ snapshot: ScoreboardSnapshot,
        side: TeamSide,
        in size: CGSize,
        insets: EdgeInsets
    ) -> some View {
        let court = snapshot.serving == side ? snapshot.servingCourt : nil
        let servingFromTheTop = court.map { servesFromTheTop($0, side: side) }
        let radius = min(size.width * 0.05, 26)
        let frame = max(8, min(size.width, size.height) * 0.022)

        return VStack(spacing: max(5, size.height * 0.014)) {
            cell(state(top: true, serving: servingFromTheTop), radius: radius, frame: frame, rounded: .top)
            cell(state(top: false, serving: servingFromTheTop), radius: radius, frame: frame, rounded: .bottom)
        }
        .padding(.horizontal, max(6, size.width * 0.014))
        .padding(.top, insets.top + size.height * 0.105)
        .padding(.bottom, insets.bottom + 52)
        .accessibilityElement()
        .accessibilityHidden(court == nil)
        .accessibilityLabel(court.map { "Serving from the \($0.displayName.lowercased()) court" } ?? "")
    }

    /// The two teams stand at opposite ends facing each other, so one team's right-hand
    /// court is at the near end of the screen and the other's is at the far end. Which is
    /// which follows where the half is drawn, so flipping the scoreboard flips this too.
    private func servesFromTheTop(_ court: ServeCourt, side: TeamSide) -> Bool {
        layout.order.first == side ? court == .ad : court == .deuce
    }

    /// Lit, its partner sunk behind it, or neither when this team is not serving.
    private enum ServeCell {
        case lit
        case shaded
        case idle
    }

    private func state(top: Bool, serving: Bool?) -> ServeCell {
        guard let serving else { return .idle }
        return serving == top ? .lit : .shaded
    }

    /// A bold frame rather than a brighter wash. An edge carries much further across a
    /// court than a low-contrast fill does, and it leaves the ground under the number
    /// alone — washing the lit box paler is exactly what costs the score its contrast.
    private func cell(_ state: ServeCell, radius: CGFloat, frame: CGFloat, rounded: Edge) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: rounded == .top ? radius : 0,
            bottomLeadingRadius: rounded == .bottom ? radius : 0,
            bottomTrailingRadius: rounded == .bottom ? radius : 0,
            topTrailingRadius: rounded == .top ? radius : 0,
            style: .continuous
        )
        let fill: Color = switch state {
        case .lit, .idle: .clear
        case .shaded: .black.opacity(0.28)
        }
        let edge: Color = switch state {
        case .lit: .white.opacity(0.95)
        case .shaded: .white.opacity(0.12)
        case .idle: .white.opacity(0.3)
        }
        return shape
            .fill(fill)
            .overlay(shape.strokeBorder(edge, lineWidth: state == .lit ? frame : 1.5))
    }

    private func numberSize(in size: CGSize) -> CGFloat {
        min(size.width * 0.42, size.height * 0.78)
    }

    /// Fades out so the score is unobstructed once the phone is set down, and comes back on
    /// a tap anywhere. Drawn whether or not there is a board: the way out lives here.
    @ViewBuilder
    private func overlay(_ snapshot: ScoreboardSnapshot?) -> some View {
        VStack {
            Spacer()

            HStack(alignment: .center, spacing: 10) {
                controlButton("xmark", label: "Leave full screen") { dismiss() }
                    .opacity(showingControls ? 1 : 0.4)

                Spacer(minLength: 0)

                if let snapshot {
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
        ScreenSleep.hold("fullscreen")
    }

    func restore() {
        if let previousBrightness, let screen {
            screen.brightness = previousBrightness
        }
        previousBrightness = nil
        ScreenSleep.release("fullscreen")
    }

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .screen
    }
}
