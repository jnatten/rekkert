import RekkertCore
import SwiftUI

/// Which half the serve is struck from, drawn as the two halves of a court seen from
/// behind the server — so the lit half is on the same hand they will be standing on.
struct ServeSideBadge: View {
    let court: ServeCourt
    /// Named when the line-up is known, so the label says who as well as where.
    var playerName: String? = nil
    /// True when the server is at the far end. You face each other, so their right is your
    /// left: the court has to be drawn the way you see it, not the way they do.
    var fromAcrossTheNet = false
    var height: CGFloat = 12

    var body: some View {
        HStack(spacing: 1.5) {
            half(lit: asYouSeeIt == .ad)
            half(lit: asYouSeeIt == .deuce)
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

    var spokenDescription: String {
        let who = playerName.map { "\($0) serving" } ?? "Serving"
        return fromAcrossTheNet
            ? "\(who) from your \(asYouSeeIt.sideName.lowercased()), their \(court.displayName.lowercased()) court"
            : "\(who) from your \(asYouSeeIt.sideName.lowercased()), the \(court.displayName.lowercased()) court"
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
    /// Rides on the badge's own line, so naming the server costs the board no height.
    var playerName: String? = nil
    var fromAcrossTheNet = false
    var height: CGFloat = 12

    var body: some View {
        Group {
            if let court {
                let badge = ServeSideBadge(
                    court: court,
                    playerName: playerName,
                    fromAcrossTheNet: fromAcrossTheNet,
                    height: height
                )
                HStack(spacing: height * 0.5) {
                    badge
                    if let playerName {
                        Text(playerName)
                            .font(.system(size: height, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(badge.spokenDescription)
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
