import SwiftUI

struct WatchHealthExplainer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                AppleHealthMark()
                    .font(.footnote)
                Text("Rekkert works with Apple Health")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Workouts you start are saved to Apple Health. While one runs, Rekkert reads your heart rate and energy. Nothing leaves your watch and iPhone.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                Button("Continue") { model.workout.answerExplainer(true) }
                    .buttonStyle(.borderedProminent)
                Button("Not now") { model.workout.answerExplainer(false) }
                    .buttonStyle(.bordered)
            }
        }
    }
}
