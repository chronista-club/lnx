#if os(iOS)
import SwiftUI
import Vision
import VisionKit

/// カメラで QR を読む（VisionKit）。読めた文字列を渡す。実機でしか動かない（シミュレータは isSupported が false）
struct QRScannerView: UIViewControllerRepresentable {
    let onFound: @MainActor (String) -> Void

    static var isSupported: Bool { DataScannerViewController.isSupported }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            // ペアリングの URL は約 535 バイトで、version 18 前後の密な QR になる
            qualityLevel: .accurate,
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
            do {
                try scanner.startScanning()
                LinkLog.note("QR: 読み取りを始めた（isAvailable=\(DataScannerViewController.isAvailable)）")
            } catch {
                LinkLog.note("QR: 読み取りを始められない: \(error)（isAvailable=\(DataScannerViewController.isAvailable)）")
            }
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
            take(addedItems, from: "didAdd")
        }

        /// 最初のフレームで中身が取れなかったものも、更新で取れることがある
        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            take(updatedItems, from: "didUpdate")
        }

        private func take(_ items: [RecognizedItem], from event: String) {
            for item in items {
                guard case .barcode(let barcode) = item else { continue }
                guard let payload = barcode.payloadStringValue else {
                    LinkLog.note("QR: \(event) で認識したが payload が無い（\(barcode.observation.symbology.rawValue)）")
                    continue
                }
                if payload == lastPayload { return }
                lastPayload = payload
                LinkLog.note("QR: \(event) で読めた（\(payload.utf8.count) バイト）")
                onFound(payload)
                return
            }
        }

        /// 同じ QR を毎フレーム渡さない
        private var lastPayload: String?
    }
}
#endif
