import SwiftUI
import UIKit
import Vision
import VisionKit

enum ReceiptScannerError: LocalizedError {
    case unavailable
    case emptyScan

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Receipt scanning isn’t available on this device."
        case .emptyScan:
            return "No readable text was found on the receipt."
        }
    }
}

struct ReceiptScannerView: UIViewControllerRepresentable {
    let onComplete: (Result<String, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onComplete: (Result<String, Error>) -> Void

        init(onComplete: @escaping (Result<String, Error>) -> Void) {
            self.onComplete = onComplete
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onComplete(.failure(CancellationError()))
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onComplete(.failure(error))
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            Task {
                do {
                    let text = try await Self.extractText(from: scan)
                    onComplete(.success(text))
                } catch {
                    onComplete(.failure(error))
                }
            }
        }

        private static func extractText(from scan: VNDocumentCameraScan) async throws -> String {
            var allLines: [String] = []

            for pageIndex in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: pageIndex)
                let pageLines = try await recognizeText(in: image)
                allLines.append(contentsOf: pageLines)
            }

            let cleaned = allLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            guard !cleaned.isEmpty else {
                throw ReceiptScannerError.emptyScan
            }

            return "Receipt scan\n\(cleaned)"
        }

        private static func recognizeText(in image: UIImage) async throws -> [String] {
            guard let cgImage = image.cgImage else {
                throw ReceiptScannerError.emptyScan
            }

            return try await withCheckedThrowingContinuation { continuation in
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: lines)
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
