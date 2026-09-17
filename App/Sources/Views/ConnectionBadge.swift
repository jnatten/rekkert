import RekkertCore
import RekkertSync
import SwiftUI

/// Whether this phone's own watch is keeping up.
struct ConnectionBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Image(systemName: model.store.isReachable
              ? "applewatch.radiowaves.left.and.right"
              : "applewatch.slash")
            .foregroundStyle(model.store.isReachable ? .green : .secondary)
            .accessibilityLabel(model.store.isReachable ? "Watch connected" : "Watch not reachable")
    }
}

/// Whether this phone's own watch is on a workout. Nothing at all when it is not: playing
/// without one is the ordinary case, and there is no "no workout" worth reporting.
///
/// A glyph rather than a control. The trailing side of this toolbar is already full, and a
/// heart within thumb's reach of the score is a mis-tap waiting to happen — stopping lives in
/// the options menu.
struct WorkoutBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.workout.isTracking {
            Image(systemName: "heart.fill")
                .foregroundStyle(.pink)
                .symbolEffect(.pulse)
                .accessibilityLabel("Workout running")
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
            Button {
                model.showingShareCode = true
            } label: {
                // Icon only: the scoreboard toolbar is already full, and a count here pushes
                // the rest into an overflow menu. Colour says whether anybody is on, and the
                // sheet behind it says how many.
                Label("\(model.sharing.reachablePeers)", systemImage: symbol)
                    .labelStyle(.iconOnly)
                    .symbolEffect(.pulse, isActive: model.sharing.isReconnecting)
            }
            .tint(tint)
            .accessibilityLabel(description)
        }
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
        switch model.sharing.reachablePeers {
        case 0: return "Sharing, nobody has joined yet"
        case 1: return "Sharing with 1 phone"
        case let count: return "Sharing with \(count) phones"
        }
    }
}
