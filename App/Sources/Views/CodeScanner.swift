import AVFoundation
import RekkertCore
import SwiftUI
import VisionKit

/// The host's QR code, read through the camera.
struct CodeScannerView: View {
    let found: (SessionCode) -> Void

    @State private var access = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Group {
            switch access {
            case .authorized:
                CodeScanner(found: found)
                    .ignoresSafeArea(edges: .bottom)
            case .notDetermined:
                Color.clear
            default:
                ContentUnavailableView {
                    Label("Rekkert cannot use the camera", systemImage: "camera")
                } description: {
                    Text("Allow camera access in Settings to scan the host's code, or go back and type it in.")
                } actions: {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
        .navigationTitle("Scan the code")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard access == .notDetermined else { return }
            _ = await AVCaptureDevice.requestAccess(for: .video)
            access = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }
}

private struct CodeScanner: UIViewControllerRepresentable {
    let found: (SessionCode) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.found = found
        if !scanner.isScanning, !context.coordinator.hasFound {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var found: (SessionCode) -> Void
        private(set) var hasFound = false

        init(found: @escaping (SessionCode) -> Void) {
            self.found = found
        }

        /// Anything that is not a Rekkert link is passed over, so a menu or a poster in
        /// frame does not end up dialled as a match.
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !hasFound else { return }
            for item in addedItems {
                guard
                    case .barcode(let barcode) = item,
                    let payload = barcode.payloadStringValue,
                    let url = URL(string: payload),
                    let code = SessionCode(joinLink: url)
                else { continue }
                hasFound = true
                dataScanner.stopScanning()
                found(code)
                return
            }
        }
    }
}
