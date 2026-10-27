import SwiftUI

extension View {
    /// A small fixed size, grown with the reader's text size rather than held at it (FR-031).
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(ScaledFont(size: size, weight: weight))
    }
}

private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .caption2)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}
