import RekkertCore
import SwiftUI

/// Which half the serve is struck from, drawn as the two halves of a court seen from
/// behind the server — so the lit half is on the same hand they will be standing on.
struct ServeSideBadge: View {
    let court: ServeCourt
    /// True when the server is at the far end. You face each other, so their right is your
    /// left: the court has to be drawn the way you see it, not the way they do.
    var fromAcrossTheNet = false
    var height: CGFloat = 12
    var showsLabel = true

    var body: some View {
        HStack(spacing: height * 0.45) {
            HStack(spacing: 1.5) {
                half(lit: asYouSeeIt == .ad)
                half(lit: asYouSeeIt == .deuce)
            }
            if showsLabel {
                Text(court.displayName)
                    .font(.system(size: height * 0.95, weight: .semibold, design: .rounded))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(spokenDescription)
    }

    /// The half of the screen the serve happens on from where you stand. For your own
    /// serve that is simply the court you are in; for theirs it is the opposite hand,
    /// though it is still their deuce or ad court.
    private var asYouSeeIt: ServeCourt {
        fromAcrossTheNet ? court.seenFromTheOtherEnd : court
    }

    private var spokenDescription: String {
        fromAcrossTheNet
            ? "Serving from their \(court.spokenName) court, on your \(asYouSeeIt.sideName.lowercased())"
            : "Serving from the \(court.spokenName) court, on your \(asYouSeeIt.sideName.lowercased())"
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
    var fromAcrossTheNet = false
    var height: CGFloat = 12
    var showsLabel = true

    var body: some View {
        Group {
            if let court {
                ServeSideBadge(
                    court: court,
                    fromAcrossTheNet: fromAcrossTheNet,
                    height: height,
                    showsLabel: showsLabel
                )
            } else {
                Color.clear
            }
        }
        .frame(height: height * 1.45)
    }
}

#Preview {
    VStack(spacing: 16) {
        // Your own serve, then the same serve seen from your side of the net.
        ServeSideBadge(court: .deuce, height: 16)
        ServeSideBadge(court: .deuce, fromAcrossTheNet: true, height: 16)
    }
    .foregroundStyle(.white)
    .padding()
    .background(Color.teamA)
}
