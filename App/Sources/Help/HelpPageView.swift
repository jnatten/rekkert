import RekkertCore
import SwiftUI

/// Drawn as a list, but laid out in a plain stack: a `List` resizes a row in one jump and only
/// then animates what is inside it, so a row opening shows its lines on top of each other first.
struct HelpPageView: View {
    let page: HelpPage
    @State private var open: String?

    private var items: [HelpItem] {
        AppModel.canPairWatch ? page.items : page.items.filter { !$0.needsWatch }
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(page.whereToFind)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                    switch page.picture {
                    case .board(let mode):
                        picture { ModeBoardPicture(mode: mode) }
                        modeCard(mode)
                    case .watchScore:
                        picture {
                            WatchScorePicture(items: items, selected: open) { pick($0, reader: reader) }
                        }
                        controls(numbered: true)
                    case .phoneScore:
                        picture {
                            PhoneScorePicture(items: items, selected: open) { pick($0, reader: reader) }
                        }
                        controls(numbered: true)
                    case .watchButtons, .phoneButtons:
                        controls(numbered: false)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func toggle(_ id: String) {
        withAnimation(.snappy) { open = open == id ? nil : id }
    }

    private func pick(_ id: String, reader: ScrollViewProxy) {
        withAnimation(.snappy) {
            open = open == id ? nil : id
            if open != nil { reader.scrollTo(id, anchor: .center) }
        }
    }

    private func picture(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    private func modeCard(_ mode: GameMode) -> some View {
        card {
            Text(mode.help.pickItWhen)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            ForEach(mode.help.points, id: \.self) { point in
                Divider().padding(.leading, 16)
                Text(point)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
    }

    private func controls(numbered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            card {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading, 58) }
                    Button { toggle(item.id) } label: {
                        row(item, number: numbered ? index + 1 : nil)
                    }
                    .buttonStyle(HelpRowStyle())
                    .id(item.id)
                }
            }
            Text("Tap one for an example.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 24))
    }

    private func row(_ item: HelpItem, number: Int?) -> some View {
        let isOpen = open == item.id
        return HStack(alignment: .top, spacing: 12) {
            if let number {
                HelpDot(number: number, isSelected: isOpen)
                    .frame(width: 30, height: 30)
            } else {
                ControlIcon(symbol: item.symbol, onWatch: page.chapter == .watch)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if number != nil, let symbol = item.symbol {
                        Image(systemName: symbol).foregroundStyle(.secondary)
                    }
                    Text(item.label).fontWeight(.semibold)
                }
                Text(item.what)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if isOpen {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("e.g. \(item.example)")
                            .font(.footnote)
                            .italic()
                        if let only = item.only {
                            Text(only)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: .capsule)
                        }
                    }
                    .padding(.top, 4)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(.rect)
        .clipped()
        .accessibilityElement(children: .combine)
    }
}

private struct HelpRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(.systemFill) : .clear)
    }
}

/// The control's glyph on a tile: dark like the watch's screen for a watch button, light for
/// the phone's.
private struct ControlIcon: View {
    let symbol: String?
    let onWatch: Bool

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium))
            } else {
                Image(systemName: "circle.fill").font(.system(size: 6))
            }
        }
        .foregroundStyle(onWatch ? Color.white : .accentColor)
        .frame(width: 30, height: 30)
        .background(onWatch ? Color.black : Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
    }
}

struct HelpDot: View {
    let number: Int
    var isSelected = false

    var body: some View {
        Text("\(number)")
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(isSelected ? Color.orange : Color.accentColor, in: .circle)
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .scaleEffect(isSelected ? 1.25 : 1)
    }
}
