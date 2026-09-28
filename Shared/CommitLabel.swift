import SwiftUI

/// The commit this build came from, small enough to be found only by someone looking for it.
struct CommitLabel: View {
    var body: some View {
        if let commit = Self.commit {
            Text(commit)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
    }

    static let commit = (Bundle.main.object(forInfoDictionaryKey: "RekkertCommit") as? String)
        .flatMap { $0.isEmpty ? nil : $0 }
}
