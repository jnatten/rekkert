import RekkertCore
import SwiftUI

struct HelpPageView: View {
    let page: HelpPage
    @State private var open: String?

    private var items: [HelpItem] {
        AppModel.canPairWatch ? page.items : page.items.filter { !$0.needsWatch }
    }

    var body: some View {
        ScrollViewReader { reader in
            List {
                switch page.picture {
                case .board(let mode):
                    pictureSection { ModeBoardPicture(mode: mode) }
                    modeSection(mode)
                case .watchScore:
                    pictureSection { WatchScorePicture(items: items, selected: $open) }
                    controls(numbered: true)
                case .phoneScore:
                    pictureSection { PhoneScorePicture(items: items, selected: $open) }
                    controls(numbered: true)
                case .watchButtons, .phoneButtons:
                    controls(numbered: false)
                }
            }
            .listSectionSpacing(.compact)
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: open) { _, id in
                guard let id else { return }
                withAnimation { reader.scrollTo(id) }
            }
        }
    }

    private func pictureSection(@ViewBuilder _ picture: () -> some View) -> some View {
        Section {
            picture()
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        } header: {
            Text(page.whereToFind)
        }
    }

    private func modeSection(_ mode: GameMode) -> some View {
        Section {
            Text(mode.help.pickItWhen).font(.headline)
            ForEach(mode.help.points, id: \.self) { point in
                Text(point).font(.subheadline)
            }
        }
    }

    private func controls(numbered: Bool) -> some View {
        Section {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    withAnimation(.snappy) { open = open == item.id ? nil : item.id }
                } label: {
                    row(item, number: numbered ? index + 1 : nil)
                }
                .buttonStyle(.plain)
                .id(item.id)
            }
        } header: {
            if !numbered { Text(page.whereToFind) }
        } footer: {
            Text("Tap one for an example.")
        }
    }

    private func row(_ item: HelpItem, number: Int?) -> some View {
        let isOpen = open == item.id
        return HStack(alignment: .top, spacing: 12) {
            if let number {
                HelpDot(number: number, isSelected: isOpen)
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
                    Text("e.g. \(item.example)")
                        .font(.footnote)
                        .italic()
                        .padding(.top, 4)
                    if let only = item.only {
                        Text(only)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                            .padding(.top, 2)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .padding(.top, 4)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
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
