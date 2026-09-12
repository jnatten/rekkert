import RekkertCore
import SwiftUI

/// Which half the serve is struck from, drawn as the two halves of a court seen from
/// behind the server — so the lit half is on the same hand they will be standing on.
struct ServeSideBadge: View {
    let court: ServeCourt
    var height: CGFloat = 12
    var showsLabel = true

    var body: some View {
        HStack(spacing: height * 0.45) {
            HStack(spacing: 1.5) {
                // Left cell first, because that is the server's left: the ad court.
                half(lit: court == .ad)
                half(lit: court == .deuce)
            }
            if showsLabel {
                Text(court.sideName)
                    .font(.system(size: height * 0.95, weight: .semibold, design: .rounded))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Serving from the \(court.sideName.lowercased()), the \(court.displayName.lowercased()) court")
    }

    private func half(lit: Bool) -> some View {
        RoundedRectangle(cornerRadius: height * 0.15)
            .fill(lit ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.22)))
            .frame(width: height * 0.62, height: height)
    }
}

/// A fixed-height place for the badge, filled only when this is where it belongs. Both
/// sides reserve the space above and below the number so the two scores stay on the same
/// line whoever happens to be serving.
struct ServeSideSlot: View {
    let court: ServeCourt?
    var height: CGFloat = 12
    var showsLabel = true

    var body: some View {
        Group {
            if let court {
                ServeSideBadge(court: court, height: height, showsLabel: showsLabel)
            } else {
                Color.clear
            }
        }
        .frame(height: height * 1.45)
    }
}

#Preview {
    HStack(spacing: 20) {
        ServeSideBadge(court: .deuce, height: 16)
        ServeSideBadge(court: .ad, height: 16)
        ServeSideBadge(court: .deuce, height: 12, showsLabel: false)
    }
    .foregroundStyle(.white)
    .padding()
    .background(Color.teamA)
}
