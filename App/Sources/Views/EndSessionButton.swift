import RekkertCore
import SwiftUI

/// Ends the session — or steps off it, when the match belongs to whoever started it.
///
/// A guest scores, corrects and undoes like anyone else. Ending is the one thing that is not
/// theirs to do, so the button says what they can do instead rather than sitting there
/// disabled with no explanation.
struct EndSessionButton: View {
    @Environment(AppModel.self) private var model
    var title = "End"
    var symbol = "flag.checkered"
    let onEnd: () -> Void

    var body: some View {
        if model.store.canEndSession {
            Button(title, systemImage: symbol, action: onEnd)
        } else {
            // Through the coordinator, which cuts the links as well: a store that steps off
            // while still connected is handed the match straight back by the next snapshot.
            Button("Leave", systemImage: "rectangle.portrait.and.arrow.right") {
                model.sharing.stop()
            }
        }
    }
}
