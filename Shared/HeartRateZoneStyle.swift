import RekkertCore
import SwiftUI

/// How a zone is coloured, on both devices.
///
/// Blue through red, the way every heart rate chart has drawn effort since long before any
/// of them were on a wrist. Spread across however many zones there turn out to be, because a
/// set configured by hand in Health Settings need not be five.
enum HeartRateZoneStyle {
    static let ramp: [Color] = [.blue, .teal, .green, .orange, .red]

    static func color(_ number: Int, of count: Int) -> Color {
        guard count > 1 else { return ramp[0] }
        let position = Double(number - 1) / Double(count - 1) * Double(ramp.count - 1)
        return ramp[min(max(Int(position.rounded()), 0), ramp.count - 1)]
    }
}
