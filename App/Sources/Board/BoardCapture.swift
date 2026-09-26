#if DEBUG
import UIKit

/// `simctl` can switch a TV on but photographs it as black, so `-rekkert-demo-tv-shot` has
/// the app draw the TV's window into `tmp/tv.png` in its container every couple of seconds.
enum BoardCapture {
    static func start() {
        Task {
            while true {
                try? await Task.sleep(for: .seconds(2))
                guard let window = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.session.role == .windowExternalDisplayNonInteractive })?
                    .windows.first
                else { continue }
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                try? image.pngData()?.write(to: .temporaryDirectory.appending(path: "tv.png"))
            }
        }
    }
}
#endif
