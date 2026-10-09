import RekkertCore
import SwiftUI

struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var chapter: HelpChapter
    @State private var path: [String] = []

    init() {
        var chapter = Self.chapters.first ?? .modes
        var path: [String] = []
        #if DEBUG
        if let id = DemoLaunch.helpPage, let page = Self.pages.first(where: { $0.id == id }) {
            chapter = page.chapter
            path = [id]
        }
        #endif
        _chapter = State(initialValue: chapter)
        _path = State(initialValue: path)
    }

    private static var pages: [HelpPage] {
        AppModel.canPairWatch ? HelpCatalog.pages : HelpCatalog.pages.filter { !$0.needsWatch }
    }

    private static var chapters: [HelpChapter] {
        HelpChapter.allCases.filter { chapter in pages.contains { $0.chapter == chapter } }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(Self.pages.filter { $0.chapter == chapter }) { page in
                        NavigationLink(value: page.id) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(page.title)
                                    Text(page.whereToFind)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: page.symbol)
                            }
                        }
                    }
                } header: {
                    Picker("Chapter", selection: $chapter) {
                        ForEach(Self.chapters, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .textCase(nil)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("How Rekkert works")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                if let page = Self.pages.first(where: { $0.id == id }) {
                    HelpPageView(page: page)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
