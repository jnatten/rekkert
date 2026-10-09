import RekkertCore
import SwiftUI

/// The mode's own board, drawn by the component the match screen uses.
struct ModeBoardPicture: View {
    let mode: GameMode

    var body: some View {
        if let snapshot = HelpSample.state(for: mode).flatMap({ ScoreboardSnapshot.make(from: $0) }) {
            ScaledPhoneScreen(height: 480, scale: 0.45) {
                ScoreboardView(
                    snapshot: snapshot,
                    takesTaps: false,
                    onTap: { _ in },
                    onUndo: {},
                    badge: { EmptyView() }
                )
            }
        }
    }
}

struct WatchScorePicture: View {
    @Environment(\.teamPalette) private var palette
    let items: [HelpItem]
    @Binding var selected: String?

    private let snapshot: ScoreboardSnapshot? = {
        var snapshot = HelpSample.goldenPoint.flatMap { ScoreboardSnapshot.make(from: $0) }
        snapshot?.clockStart = .now.addingTimeInterval(-754)
        return snapshot
    }()

    var body: some View {
        if let snapshot {
            VStack(spacing: 4) {
                ScoreboardView(
                    snapshot: snapshot,
                    compact: true,
                    takesTaps: false,
                    onTap: { _ in },
                    onUndo: {},
                    badge: { heart }
                )
                .frame(maxHeight: .infinity)
                .overlay(alignment: .bottomLeading) { undo }
                receiversPick
            }
            .padding(.top, 6)
            .padding(.horizontal, 3)
            .padding(.bottom, 6)
            .background(palette.color(.a).gradient.opacity(0.25))
            .background(.black)
            .overlay(alignment: .topTrailing) { pageDots }
            .frame(width: 190, height: 232)
            .clipShape(.rect(cornerRadius: 36))
            .overlay { Spots(items: items, selected: $selected) }
            .padding(8)
            .background(.black, in: .rect(cornerRadius: 44))
            .overlay(RoundedRectangle(cornerRadius: 44).stroke(Color(white: 0.4), lineWidth: 3))
            .environment(\.colorScheme, .dark)
        }
    }

    private var heart: some View {
        HStack(spacing: 2) {
            Image(systemName: "heart.fill").font(.system(size: 9))
            Text(verbatim: "128").font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(.pink)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(.black.opacity(0.4), in: .capsule)
        .padding(.leading, 3)
    }

    private var undo: some View {
        Image(systemName: "arrow.uturn.backward")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(.black.opacity(0.4), in: .circle)
            .padding(.leading, 3)
            .padding(.bottom, 3)
    }

    private var receiversPick: some View {
        HStack(spacing: 4) {
            Text("Receivers pick")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            ForEach(["Right", "Left"], id: \.self) { side in
                Text(side)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(side == "Left" ? .orange : .white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(white: side == "Left" ? 0.3 : 0.2), in: .capsule)
            }
        }
    }

    private var pageDots: some View {
        VStack(spacing: 3) {
            Circle().fill(.white).frame(width: 4, height: 4)
            Circle().fill(.white.opacity(0.4)).frame(width: 4, height: 4)
        }
        .padding(.top, 10)
        .padding(.trailing, 6)
    }
}

struct PhoneScorePicture: View {
    let items: [HelpItem]
    @Binding var selected: String?

    private let snapshot = HelpSample.goldenPoint.flatMap { ScoreboardSnapshot.make(from: $0) }

    /// The glyphs along the top are the help's own items, so the bar cannot show a button
    /// the legend does not explain.
    private var toolbar: [HelpItem] {
        items.filter { $0.symbol != nil && ($0.spot?.y ?? 1) < 0.15 }
    }

    var body: some View {
        if let snapshot {
            ScaledPhoneScreen(height: 760, scale: 0.5) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 56)
                    ScoreboardView(
                        snapshot: snapshot,
                        takesTaps: false,
                        onTap: { _ in },
                        onUndo: {},
                        badge: { EmptyView() }
                    )
                    banner
                }
            }
            .overlay {
                GeometryReader { geometry in
                    ForEach(toolbar) { item in
                        if let symbol = item.symbol, let spot = item.spot {
                            Image(systemName: symbol)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.accentColor)
                                .position(x: spot.x * geometry.size.width, y: 14)
                        }
                    }
                }
                .padding(6)
            }
            .overlay {
                Spots(items: items, selected: $selected).padding(6)
            }
        }
    }

    private var banner: some View {
        VStack(spacing: 8) {
            Text("Sudden death — receivers choose the side")
                .font(.footnote.weight(.semibold))
            HStack(spacing: 0) {
                ForEach(["Right (deuce)", "Left (ad)"], id: \.self) { side in
                    Text(side)
                        .font(.footnote.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(side.hasPrefix("Right") ? Color(.systemBackground) : .clear, in: .rect(cornerRadius: 7))
                }
            }
            .padding(2)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 9))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 30)
        .background(.orange.opacity(0.2))
    }
}

/// A phone's screen laid out at full size and shrunk, so the board inside it is the one the
/// match screen draws rather than a smaller cousin of it.
private struct ScaledPhoneScreen<Content: View>: View {
    let height: CGFloat
    let scale: CGFloat
    @ViewBuilder let content: Content

    private let width: CGFloat = 390

    var body: some View {
        content
            .frame(width: width, height: height)
            .background(Color(.systemBackground))
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width * scale, height: height * scale, alignment: .topLeading)
            .clipShape(.rect(cornerRadius: 26))
            .padding(6)
            .background(.black, in: .rect(cornerRadius: 32))
    }
}

/// The numbered dots over a picture, one for each item with a spot. Tapping one picks it out
/// in the legend underneath.
private struct Spots: View {
    let items: [HelpItem]
    @Binding var selected: String?

    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if let spot = item.spot {
                    Button {
                        withAnimation(.snappy) { selected = selected == item.id ? nil : item.id }
                    } label: {
                        HelpDot(number: index + 1, isSelected: selected == item.id)
                    }
                    .buttonStyle(.plain)
                    .position(x: spot.x * geometry.size.width, y: spot.y * geometry.size.height)
                    .accessibilityLabel(item.label)
                }
            }
        }
    }
}
