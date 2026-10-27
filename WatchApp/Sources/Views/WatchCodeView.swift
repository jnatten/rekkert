import RekkertCore
import RekkertSync
import SwiftUI

/// The code the host's phone is sharing, to read out or to scan (FR-017, FR-018).
struct WatchCodeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let status = model.standIn.hosting, status.isSharing, let code = status.code {
                    Text(code.readOut)
                        .font(.system(size: 80, weight: .semibold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.2)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(code.digitByDigit)
                    if let qr = status.qr, let image = UIImage(data: qr) {
                        // Dark on white whatever the face, and the digits above are its text alternative.
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                            .background(.white, in: .rect(cornerRadius: 6))
                            .accessibilityHidden(true)
                    }
                    Text("Scan with the Camera to join")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                } else if model.standIn.hostingTrouble == .cannotReachPhone {
                    WatchHostingTrouble(text: "Can't reach your iPhone")
                } else if model.standIn.hostingTrouble == .nothingToShare {
                    WatchHostingTrouble(text: "Nothing on your iPhone to share")
                } else {
                    ProgressView()
                    Text("Sharing…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Code")
    }
}

struct WatchHostingTrouble: View {
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone.slash")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }
}

private extension SessionCode {
    /// `482 915`: two groups, as it is read out.
    var readOut: String { description.replacingOccurrences(of: "-", with: " ") }

    /// One digit at a time, for VoiceOver (FR-031).
    var digitByDigit: String {
        description.filter(\.isNumber).map(String.init).joined(separator: " ")
    }
}
