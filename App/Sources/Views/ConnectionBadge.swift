import RekkertCore
import RekkertSync
import SwiftUI

/// Whether this phone's own watch is keeping up.
struct ConnectionBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // The pair's link alone: any link at all is also every other phone on a shared match.
        Image(systemName: model.store.isPairReachable
              ? "applewatch.radiowaves.left.and.right"
              : "applewatch.slash")
            .foregroundStyle(model.store.isPairReachable ? .green : .secondary)
            .accessibilityLabel(model.store.isPairReachable ? "Watch connected" : "Watch not reachable")
    }
}

/// Whether this phone's own watch is on a workout, and whether it is counting. Nothing at
/// all when there is none: playing without one is the ordinary case, and there is no "no
/// workout" worth reporting.
///
/// A glyph rather than a control. The trailing side of this toolbar is already full, and a
/// heart within thumb's reach of the score is a mis-tap waiting to happen — holding and
/// stopping both live in the options menu.
struct WorkoutBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.workout.isTracking {
            Image(systemName: model.workout.isPaused ? "pause.fill" : "heart.fill")
                .foregroundStyle(model.workout.isPaused ? Color.secondary : .pink)
                .symbolEffect(.pulse, isActive: !model.workout.isPaused)
                .accessibilityLabel(model.workout.isPaused ? "Workout paused" : "Workout running")
        }
    }
}

/// How many other phones are on this match, and a way back to the code — somebody always
/// turns up late. Its own toolbar item rather than sitting beside the watch glyph, because a
/// toolbar item renders one control and quietly drops the rest of a stack.
struct SharingBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.sharing.isSharing {
            if isHosting || model.sharing.isReconnecting {
                Button {
                    // A guest has no code to read out. Lost, it may have a new one to type in.
                    if isHosting { model.showingShareCode = true } else { model.showingJoin = true }
                } label: {
                    glyph
                }
                .tint(tint)
                .accessibilityLabel(description)
            } else {
                glyph
                    .foregroundStyle(tint)
                    .accessibilityLabel(description)
            }
        } else if isCutOff {
            Button {
                model.showingJoin = true
            } label: {
                Label("Rejoin", systemImage: "person.2.slash")
                    .labelStyle(.iconOnly)
            }
            .tint(.secondary)
            .accessibilityLabel("Not connected to the shared match. Rejoin")
        }
    }

    private var isHosting: Bool { model.sharing.code != nil }

    // Icon only: the scoreboard toolbar is already full, and a count here pushes the rest into
    // an overflow menu. Colour says whether anybody is on, and the sheet behind it says how many.
    private var glyph: some View {
        Label("\(model.sharing.reachablePeers)", systemImage: symbol)
            .labelStyle(.iconOnly)
            .symbolEffect(.pulse, isActive: model.sharing.isReconnecting)
    }

    /// Somebody else's match with no link to it. The code goes with the app, so a guest back from a
    /// relaunch went on showing the match with no sign that none of it was getting through.
    private var isCutOff: Bool {
        guard model.store.role == .guest, model.store.state != nil, case .off = model.sharing.phase else { return false }
        return true
    }

    /// A match that has gone quiet is not the same as one nobody has joined, and the grey of
    /// the second would have read as the first.
    private var symbol: String {
        model.sharing.isReconnecting ? "person.2.slash" : "person.2.fill"
    }

    private var tint: Color {
        if model.sharing.isReconnecting { return .secondary }
        return model.sharing.reachablePeers > 0 ? Color.accentColor : .secondary
    }

    private var description: String {
        if model.sharing.isReconnecting { return "Reconnecting to the shared match" }
        guard isHosting else {
            return model.sharing.reachablePeers > 0 ? "Connected to the shared match" : "Looking for the shared match"
        }
        switch model.sharing.reachablePeers {
        case 0: return "Sharing, nobody has joined yet"
        case 1: return "Sharing with 1 phone"
        case let count: return "Sharing with \(count) phones"
        }
    }
}
