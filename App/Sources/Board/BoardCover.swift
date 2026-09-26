import SwiftUI

/// The TV's board on this device's own screen. Read-only: the only thing a tap does is
/// bring the way out back.
struct BoardCover: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingControls = true
    @State private var hideControlsAt = Date()
    private let controlsLinger: TimeInterval = 4

    var body: some View {
        BoardRoot()
            .contentShape(.rect)
            .onTapGesture { revealControls() }
            .overlay(alignment: .bottomLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.white.opacity(0.16), in: .circle)
                }
                .accessibilityLabel("Close the board")
                .opacity(showingControls ? 1 : 0.4)
                .padding(14)
                .animation(.easeInOut(duration: 0.35), value: showingControls)
            }
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .onAppear {
                ScreenSleep.hold("board")
                revealControls()
            }
            .onDisappear { ScreenSleep.release("board") }
    }

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

struct BoardButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Board", systemImage: "tv") { model.showingBoard = true }
    }
}
