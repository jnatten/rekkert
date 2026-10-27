import RekkertCore
import SwiftUI

struct AppleHealthView: View {
    var body: some View {
        List {
            Section {
                AppleHealthMark(size: 48)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
            Section("Saved to Apple Health") { rows(saved) }
            Section("Read from Apple Health") { rows(read) }
            Section("When") { Text(HealthDisclosure.when) }
            Section("Where it goes") { Text(HealthDisclosure.whereItGoes) }
            Section("Change access") {
                ForEach(HealthDisclosure.changeAccess, id: \.self) { Text($0) }
            }
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var saved: [HealthData] {
        let kinds = HealthDisclosure.saved(on: .phone) + HealthDisclosure.saved(on: .watch)
        return HealthData.allCases.filter(kinds.contains)
    }

    private var read: [HealthData] {
        HealthData.allCases.filter(HealthDisclosure.read(on: .watch).contains)
    }

    private func rows(_ kinds: [HealthData]) -> some View {
        ForEach(kinds, id: \.self) { kind in
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                Text(kind.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
