import RekkertCore
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Rekkert").font(.largeTitle.bold())
            Text(Rekkert.version).foregroundStyle(.secondary)
        }
    }
}
