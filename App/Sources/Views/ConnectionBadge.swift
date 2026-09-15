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
                Label("\(model.sharing.peers)", systemImage: "person.2.fill")
                    .labelStyle(.iconOnly)
            }
            .tint(model.sharing.peers > 0 ? Color.accentColor : .secondary)
            .accessibilityLabel(description)
        }
    }

    private var description: String {
        switch model.sharing.peers {
        case 0: "Sharing, nobody has joined yet"
        case 1: "Sharing with 1 phone"
        case let count: "Sharing with \(count) phones"
        }
    }
}
