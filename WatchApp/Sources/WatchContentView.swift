import RekkertCore
import SwiftUI

struct WatchContentView: View {
    var body: some View {
        VStack {
            Text("Rekkert").font(.headline)
            Text(Rekkert.version).foregroundStyle(.secondary)
        }
    }
}
