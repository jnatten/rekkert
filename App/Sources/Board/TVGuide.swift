import SwiftUI
import UIKit

/// iOS lets only Control Center start Screen Mirroring, so the nearest thing to an AirPlay
/// button is one that says how, and lights up once a TV has the board.
struct TVButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.showingTVGuide = true
        } label: {
            Image(systemName: "airplay.video")
        }
        .tint(model.isBoardOnTV ? Color.accentColor : .primary)
        .accessibilityLabel(model.isBoardOnTV ? "The board is on a TV" : "Show the board on a TV")
    }
}

struct TVGuideSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.isBoardOnTV {
                    Section {
                        Label("The board is on the TV", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.headline)
                    } footer: {
                        Text("This phone goes on scoring as usual and stays awake while the TV is connected. To stop, open Control Center, tap Screen Mirroring and then Stop Mirroring.")
                    }
                } else {
                    Section {
                        step(1, "Open Control Center", detail: controlCenterGesture, symbol: "switch.2")
                        step(2, "Tap Screen Mirroring", symbol: "rectangle.on.rectangle")
                        step(3, "Pick your Apple TV", symbol: "appletv")
                    } footer: {
                        Text("The TV gets a scoreboard of its own, and this phone goes on scoring. An HDMI adapter works too.")
                    }
                }
            }
            .animation(.default, value: model.isBoardOnTV)
            .navigationTitle("Show on a TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func step(_ number: Int, _ title: String, detail: String? = nil, symbol: String) -> some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// A phone with a Home button opens Control Center from the bottom edge; everything else
    /// from the top-right corner.
    private var controlCenterGesture: String {
        let hasHomeButton = UIDevice.current.userInterfaceIdiom == .phone
            && (UIApplication.shared.phoneScene?.keyWindow?.safeAreaInsets.bottom ?? 0) == 0
        return hasHomeButton ? "Swipe up from the bottom edge." : "Swipe down from the top-right corner."
    }
}
