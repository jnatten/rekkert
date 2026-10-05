import CoreImage.CIFilterBuiltins
import RekkertCore
import SwiftUI

/// The code as a link, for a camera at the court to open Rekkert with.
struct JoinQRCode: View {
    let code: SessionCode

    var body: some View {
        if let image = Self.render(code.joinLink) {
            // Dark on white whatever the appearance: not every scanner reads a code inverted.
            Image(image, scale: 1, label: Text("QR code for joining this match"))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .padding(16)
                .background(.white, in: .rect(cornerRadius: 16))
        }
    }

    private static let context = CIContext()

    private static func render(_ link: URL) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: output.extent)
    }
}
