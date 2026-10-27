import UIKit

/// The join link as a small PNG, one pixel to a module, for the host's watch to draw (D-14).
/// Drawn here because watchOS has no Core Image.
enum JoinQRImage {
    static func png(for link: URL) -> Data? {
        JoinQRCode.render(link).flatMap { UIImage(cgImage: $0).pngData() }
    }
}
