import SwiftUI

struct HealthExplainer: View {
    let onAnswer: (Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AppleHealthMark(size: 60)
                    .font(.headline)
                Text("Rekkert works with Apple Health")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Your Apple Watch records the workout and saves it to Apple Health as tennis. While it runs, Rekkert reads your heart rate and energy to show them with the score. Nothing it reads leaves your iPhone and Apple Watch.")
                Text("Apple Health asks next what Rekkert may save and read. You can change it later in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    onAnswer(true)
                } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Not now") { onAnswer(false) }
            }
            .padding(24)
        }
        .presentationDetents([.medium, .large])
    }
}
