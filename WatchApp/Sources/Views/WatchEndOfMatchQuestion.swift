import RekkertCore
import RekkertSync
import SwiftUI

struct WatchEndOfMatchQuestion: View {
    @Environment(AppModel.self) private var model
    let ask: EndOfMatchAsk

    var body: some View {
        VStack(spacing: 6) {
            Text(ask.watchTitle)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
            if let line = ask.watchLine {
                Text(line)
                    .scaledFont(size: 11)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            switch ask.side {
            case .host:
                Button("Keep sharing") { model.standIn.answer(.keepSharing) }
                    .buttonStyle(.borderedProminent)
                Button("Stop sharing", role: .destructive) { model.standIn.answer(.stopSharing) }
                    .buttonStyle(.bordered)
                if model.standIn.hostingTrouble == .cannotReachPhone {
                    Text("Can't reach your iPhone")
                        .scaledFont(size: 11)
                        .foregroundStyle(.orange)
                }
            case .guest:
                Button("Stay") { model.standIn.answer(.stay) }
                    .buttonStyle(.borderedProminent)
                Button("Leave", role: .destructive) { model.standIn.answer(.leave) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }
}

extension EndOfMatchAsk {
    var watchTitle: String {
        switch side {
        case .host: "Keep sharing?"
        case .guest(let host, _): host.map { "Stay for \($0)'s next match?" } ?? "Stay for the host's next match?"
        }
    }

    var watchLine: String? {
        switch side {
        case .host(let guestsOn): guestsOn == 0 ? "Nobody on yet" : "\(guestsOn) on"
        case .guest(let host, let keeps): keeps ? "\(host ?? "The host") is keeping it shared." : nil
        }
    }
}
