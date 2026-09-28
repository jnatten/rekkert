import RekkertCore
import SwiftUI

struct PlayerStatsView: View {
    @Environment(AppModel.self) private var model
    @State private var current: PersonID

    init(person: PersonID) {
        _current = State(initialValue: person)
    }

    var body: some View {
        Group {
            if let stats = model.playerStats, let person = stats.person(current) {
                PlayerDetail(person: person, stats: stats, current: $current)
            } else if model.playerStats == nil {
                ProgressView()
            } else {
                ContentUnavailableView(
                    "Nobody here",
                    systemImage: "person.2",
                    description: Text("This player no longer has any matches in History.")
                )
            }
        }
        .task(id: model.revision) { await model.refreshPlayerStats(onlyIfStale: true) }
    }
}

private struct PlayerDetail: View {
    @Environment(AppModel.self) private var model
    let person: PersonStats
    let stats: PlayerStats
    @Binding var current: PersonID

    @State private var merging = false
    @State private var separating: Set<Seat>?
    @State private var editingNote = false
    @State private var noteText = ""

    var body: some View {
        List {
            Section { summary }

            if !person.clashes.isEmpty {
                clashSection
            }

            if person.modes.count > 1 {
                Section("By mode") {
                    ForEach(person.modes) { mode in
                        HStack {
                            Label(mode.name, systemImage: mode.symbol)
                            Spacer()
                            TallyValue(tally: mode.tally)
                        }
                    }
                }
            }

            if !person.partners.isEmpty {
                partnersSection
            }

            if !person.opponents.isEmpty {
                Section {
                    ForEach(person.opponents) { pairing in
                        NavigationLink(value: HomeRoute.player(pairing.person)) {
                            PairingRow(pairing: pairing)
                        }
                    }
                } header: {
                    Text("Head to head")
                } footer: {
                    Text("Every game with them on the other side of the net. Winner court is left out: whoever you played changed at every whistle.")
                }
            }

            ForEach(TournamentFormat.allCases, id: \.self) { format in
                if let points = person.points[format] {
                    pointsSection(format, points)
                }
            }

            if !person.merged.isEmpty {
                Section {
                    ForEach(person.merged) { merged in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(merged.name)
                                if let note = merged.note {
                                    Text(note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Unmerge") { model.unmerge(merged.id) }
                                .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Merged in")
                } footer: {
                    Text("A merged name keeps counting here, the next time it is typed in too.")
                }
            }

            Section("Matches") {
                ForEach(person.appearances) { appearance in
                    NavigationLink(value: HomeRoute.record(appearance.record)) {
                        AppearanceRow(appearance: appearance)
                    }
                }
            }
        }
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Edit", systemImage: "ellipsis.circle") {
                    Button("Merge with…", systemImage: "arrow.triangle.merge") { merging = true }
                    Button("Separate matches…", systemImage: "arrow.triangle.branch") { separating = [] }
                    Button(person.note == nil ? "Add a note…" : "Edit note…", systemImage: "note.text") {
                        noteText = person.note ?? ""
                        editingNote = true
                    }
                }
            }
        }
        .task {
            #if DEBUG
            switch DemoLaunch.playerSheet {
            case "merge": merging = true
            case "separate": separating = clashPreselection
            default: break
            }
            #endif
        }
        .sheet(isPresented: $merging) {
            MergePlayerView(person: person, stats: stats) { other in
                current = model.merge(other, into: person.id)
            }
        }
        .sheet(item: Binding(
            get: { separating.map(Preselection.init) },
            set: { separating = $0?.seats }
        )) { preselection in
            SeparatePlayerView(person: person, stats: stats, chosen: preselection.seats)
        }
        .alert("Note", isPresented: $editingNote) {
            TextField("e.g. from work", text: $noteText)
                .textInputAutocapitalization(.sentences)
            Button("Cancel", role: .cancel) {}
            Button("Save") { model.setNote(noteText, for: person.id) }
        } message: {
            Text("Shown beside \(person.name) in the list, to tell apart people with the same name.")
        }
    }

    private var summary: some View {
        VStack(spacing: 6) {
            Text("Win rate")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(person.overall.rate ?? "–")
                .font(.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.tint)
            Text(person.overall.played == 0 ? "No finished games yet" : person.overall.line)
                .font(.headline.monospacedDigit())
            if let note = person.note {
                Text(note).font(.subheadline).foregroundStyle(.secondary)
            }
            Text("\(person.overall.played) played · last \(person.lastPlayed.formatted(.dateTime.day().month().year()))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var clashSection: some View {
        Section {
            Label(
                person.clashes.count == 1
                    ? "Two people counted as \(person.name) played in the same session."
                    : "Two people counted as \(person.name) played in the same session, \(person.clashes.count) times.",
                systemImage: "exclamationmark.triangle"
            )
            Button("Tell them apart…") { separating = clashPreselection }
        } footer: {
            Text("Until they are, games they played against each other count for neither of them.")
        }
    }

    private var clashPreselection: Set<Seat> {
        let clashing = Set(person.clashes)
        let byRecord = Dictionary(grouping: person.appearances.filter { clashing.contains($0.record) }, by: \.record)
        return Set(byRecord.values.compactMap { $0.last?.seat })
    }

    private var partnersSection: some View {
        let best = person.bestPartner
        let rest = person.partners.filter { $0.id != best?.id }
        return Section {
            if let best {
                NavigationLink(value: HomeRoute.player(best.person)) {
                    PairingRow(pairing: best, isBest: true)
                }
            }
            ForEach(rest) { pairing in
                NavigationLink(value: HomeRoute.player(pairing.person)) {
                    PairingRow(pairing: pairing)
                }
            }
        } header: {
            Text("Partners")
        } footer: {
            Text("The best partner is the best win rate over at least \(PersonStats.bestPartnerMinimum) games together.")
        }
    }

    private func pointsSection(_ format: TournamentFormat, _ points: PointTally) -> some View {
        Section {
            if let average = points.average {
                LabeledContent("Average a round", value: average.formatted(.number.precision(.fractionLength(1))))
            }
            if let share = points.share {
                LabeledContent("Share of the points", value: share.formatted(.percent.precision(.fractionLength(0))))
            }
            LabeledContent("Rounds played", value: "\(points.rounds)")
        } header: {
            Text(format.displayName)
        } footer: {
            Text("Rounds on the bench are left out, and so is what they were worth.")
        }
    }
}

private struct Preselection: Identifiable {
    let seats: Set<Seat>
    var id: Set<Seat> { seats }
}

private struct TallyValue: View {
    let tally: Tally

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(tally.rate ?? "–")
                .font(.callout.bold().monospacedDigit())
            Text(tally.line)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct PairingRow: View {
    let pairing: Pairing
    var isBest = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pairing.name)
                    .fontWeight(isBest ? .semibold : .regular)
                if isBest {
                    Text("\(Image(systemName: "star.fill")) Best partner")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            TallyValue(tally: pairing.tally)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AppearanceRow: View {
    let appearance: Appearance

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appearance.title)
                HStack(spacing: 4) {
                    Image(systemName: appearance.modeSymbol)
                    Text(appearance.modeName)
                    Text("·")
                    Text(appearance.date, format: .dateTime.day().month().year())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let company {
                    Text(company)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if appearance.tally.played > 0 {
                Text(appearance.tally.line)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var company: String? {
        if !appearance.partners.isEmpty {
            return "with \(appearance.partners.formatted(.list(type: .and)))"
        }
        if !appearance.opponents.isEmpty {
            return "against \(appearance.opponents.formatted(.list(type: .and)))"
        }
        return nil
    }
}

private struct MergePlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let person: PersonStats
    let stats: PlayerStats
    let merge: (PersonID) -> Void

    @State private var query = ""
    @State private var chosen: PersonStats?

    private var candidates: [PersonStats] {
        stats.people.filter { $0.id != person.id && $0.matches(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(candidates) { candidate in
                        Button { chosen = candidate } label: {
                            PlayerRow(person: candidate).foregroundStyle(Color.primary)
                        }
                    }
                } footer: {
                    Text("Merged, they count as one player — in every match either name is in, and the next time either is typed in. It can be undone from this page.")
                }
            }
            .searchable(text: $query)
            .overlay {
                if candidates.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .navigationTitle("Merge \(person.name) with")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                chosen.map { "Merge \(person.name) and \($0.name)?" } ?? "",
                isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }),
                titleVisibility: .visible,
                presenting: chosen
            ) { other in
                Button("Merge") {
                    merge(other.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: { other in
                let shared = person.records.intersection(other.records).count
                if shared > 0 {
                    Text("They both played in \(shared == 1 ? "one session" : "\(shared) sessions"). Merged, the games they played against each other count for neither until they are told apart again.")
                } else {
                    Text("Their matches, partners and records are counted together from now on.")
                }
            }
        }
    }
}

private struct SeparatePlayerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let person: PersonStats
    let stats: PlayerStats

    @State private var chosen: Set<Seat>
    @State private var destination: PersonID?
    @State private var note = ""

    init(person: PersonStats, stats: PlayerStats, chosen: Set<Seat>) {
        self.person = person
        self.stats = stats
        _chosen = State(initialValue: chosen)
    }

    private var others: [PersonStats] {
        stats.people.filter { $0.id != person.id }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(person.appearances) { appearance in
                        Button {
                            if chosen.contains(appearance.seat) {
                                chosen.remove(appearance.seat)
                            } else {
                                chosen.insert(appearance.seat)
                            }
                        } label: {
                            HStack {
                                AppearanceRow(appearance: appearance)
                                    .foregroundStyle(Color.primary)
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .opacity(chosen.contains(appearance.seat) ? 1 : 0)
                            }
                            .contentShape(.rect)
                        }
                    }
                } header: {
                    Text("Matches that were somebody else")
                } footer: {
                    Text("Anything left unticked stays with \(person.name), and so does the next match with that name in it.")
                }

                Section {
                    Picker("Move them to", selection: $destination) {
                        Text("A new player").tag(PersonID?.none)
                        ForEach(others) { other in
                            Text(other.note.map { "\(other.name) · \($0)" } ?? other.name)
                                .tag(PersonID?.some(other.id))
                        }
                    }
                    .pickerStyle(.navigationLink)
                    if destination == nil {
                        TextField("Who is this? e.g. from work", text: $note)
                            .textInputAutocapitalization(.sentences)
                    }
                } footer: {
                    if destination == nil {
                        Text("The new player is called \(person.name) too. The note is what tells the two apart in the list.")
                    }
                }
            }
            .navigationTitle("Separate \(person.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move", action: save)
                        .disabled(chosen.isEmpty)
                }
            }
        }
    }

    private func save() {
        let moving = person.appearances.filter { chosen.contains($0.seat) }
        if let destination {
            model.move(moving, to: destination)
        } else {
            model.separate(moving, note: note)
        }
        dismiss()
    }
}
