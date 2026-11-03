#if os(iOS)
import SwiftUI
import VisionKit

/// カメラで QR を読む（VisionKit）。読めた文字列を渡す。実機でしか動かない（シミュレータは isSupported が false）
struct QRScannerView: UIViewControllerRepresentable {
    let onFound: @MainActor (String) -> Void

    static var isSupported: Bool { DataScannerViewController.isSupported }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        // 待つサーバが変わると onFound も変わる。coordinator は作り直されないので差し替える
        context.coordinator.onFound = onFound
        // 画面に載ってから始める（載る前の startScanning は失敗する）。初回はここでカメラの許可を求められる
        if !scanner.isScanning {
            do { try scanner.startScanning() } catch { LinkLog.note("QR の読み取りを始められない: \(error)") }
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onFound: @MainActor (String) -> Void

        init(onFound: @escaping @MainActor (String) -> Void) {
            self.onFound = onFound
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    onFound(payload)
                    return
                }
            }
        }
    }
}
#endif
