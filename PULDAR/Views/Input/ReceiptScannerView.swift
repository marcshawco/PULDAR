import SwiftUI
import UIKit
import Vision
import VisionKit
import CoreGraphics

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
    let currencyCode: String
    let onComplete: (Result<String, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(currencyCode: currencyCode, onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private struct RecognizedLine {
            let text: String
            let boundingBox: CGRect
        }

        private struct AmountCandidate {
            let value: Double
            let line: RecognizedLine
            let label: String?
            let score: Int
        }

        private let onComplete: (Result<String, Error>) -> Void
        private let currencyCode: String

        init(currencyCode: String, onComplete: @escaping (Result<String, Error>) -> Void) {
            self.currencyCode = currencyCode
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
                    let text = try await Self.extractText(from: scan, currencyCode: currencyCode)
                    onComplete(.success(text))
                } catch {
                    onComplete(.failure(error))
                }
            }
        }

        nonisolated private static func extractText(
            from scan: VNDocumentCameraScan,
            currencyCode: String
        ) async throws -> String {
            var pages: [[RecognizedLine]] = []

            for pageIndex in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: pageIndex)
                let pageLines = try await recognizeText(in: image)
                pages.append(pageLines)
            }

            let allLines = pages
                .flatMap { $0 }
                .map { line in
                    RecognizedLine(
                        text: line.text.trimmingCharacters(in: .whitespacesAndNewlines),
                        boundingBox: line.boundingBox
                    )
                }
                .filter { !$0.text.isEmpty }

            guard !allLines.isEmpty else {
                throw ReceiptScannerError.emptyScan
            }

            let merchantHint = pages.compactMap(inferMerchantName(from:)).first
            let totalHint = pages.compactMap(inferTotal(from:)).max(by: { $0.value < $1.value })
            let merchantCandidates = uniqueStrings(pages.flatMap(merchantCandidates(from:)))
            let bottomAmountCandidates = pages
                .flatMap(bottomAmountCandidates(from:))
                .prefix(5)
                .map { candidate in
                    let amount = candidate.value.formatted(.currency(code: currencyCode))
                    if let label = candidate.label, !label.isEmpty {
                        return "\(amount) from '\(label)'"
                    }
                    return amount
                }

            let rawLines = allLines
                .map(\.text)
                .joined(separator: "\n")

            var sections: [String] = ["Receipt scan"]
            if let merchantHint {
                sections.append("Likely merchant: \(merchantHint)")
            }
            if let totalHint {
                sections.append("Likely total: \(totalHint.value.formatted(.currency(code: currencyCode)))")
            }
            if !merchantCandidates.isEmpty {
                sections.append("Merchant candidates: \(merchantCandidates.prefix(4).joined(separator: " | "))")
            }
            if !bottomAmountCandidates.isEmpty {
                sections.append("Bottom amount candidates: \(bottomAmountCandidates.joined(separator: " | "))")
            }
            sections.append("OCR lines:\n\(rawLines)")

            return sections.joined(separator: "\n")
        }

        nonisolated private static func recognizeText(in image: UIImage) async throws -> [RecognizedLine] {
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
                    let lines = observations.compactMap { observation -> RecognizedLine? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        return RecognizedLine(
                            text: candidate.string,
                            boundingBox: observation.boundingBox
                        )
                    }
                    .sorted(by: receiptReadingOrder)
                    continuation.resume(returning: lines)
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["en-US"]

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        nonisolated private static func receiptReadingOrder(lhs: RecognizedLine, rhs: RecognizedLine) -> Bool {
            let yDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
            if yDelta > 0.025 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        nonisolated private static func inferMerchantName(from lines: [RecognizedLine]) -> String? {
            merchantCandidates(from: lines).first
        }

        nonisolated private static func merchantCandidates(from lines: [RecognizedLine]) -> [String] {
            let topLines = lines
                .filter { $0.boundingBox.midY > 0.62 }
                .prefix(8)

            var candidates: [String] = []
            for line in lines {
                if let canonical = String.canonicalMerchantName(from: line.text) {
                    candidates.append(canonical)
                }
            }

            for line in topLines {
                let cleaned = sanitizeMerchantCandidate(line.text)
                guard isPlausibleMerchant(cleaned) else { continue }
                candidates.append(cleaned)
            }

            if candidates.isEmpty {
                for line in lines.prefix(5) {
                    let cleaned = sanitizeMerchantCandidate(line.text)
                    guard isPlausibleMerchant(cleaned) else { continue }
                    candidates.append(cleaned)
                }
            }

            return uniqueStrings(candidates)
        }

        nonisolated private static func inferTotal(from lines: [RecognizedLine]) -> AmountCandidate? {
            let candidates = bottomAmountCandidates(from: lines)
            return candidates.max { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score < rhs.score
                }
                if abs(lhs.line.boundingBox.midY - rhs.line.boundingBox.midY) > 0.02 {
                    return lhs.line.boundingBox.midY > rhs.line.boundingBox.midY
                }
                return lhs.value < rhs.value
            }
        }

        nonisolated private static func bottomAmountCandidates(from lines: [RecognizedLine]) -> [AmountCandidate] {
            let bottomLines = lines.filter { $0.boundingBox.midY < 0.45 }
            var candidates: [AmountCandidate] = []

            for (index, line) in bottomLines.enumerated() {
                for amount in extractAmounts(from: line.text) {
                    let contextLines = neighboringLines(around: index, in: bottomLines)
                    let labelText = ([line.text] + contextLines.map(\.text)).joined(separator: " ")
                    let uppercaseLabel = labelText.uppercased()
                    let score = scoreAmountCandidate(amount, labelText: uppercaseLabel, y: line.boundingBox.midY)
                    guard score > 0 else { continue }
                    candidates.append(
                        AmountCandidate(
                            value: amount,
                            line: line,
                            label: labelText,
                            score: score
                        )
                    )
                }
            }

            return candidates.sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.line.boundingBox.midY < rhs.line.boundingBox.midY
            }
        }

        nonisolated private static func neighboringLines(around index: Int, in lines: [RecognizedLine]) -> [RecognizedLine] {
            let lower = max(index - 1, 0)
            let upper = min(index + 1, lines.count - 1)
            guard lower <= upper else { return [] }
            return Array(lines[lower...upper]).filter { $0.text != lines[index].text }
        }

        nonisolated private static func scoreAmountCandidate(_ amount: Double, labelText: String, y: CGFloat) -> Int {
            guard amount > 0 else { return 0 }
            var score = 0

            if labelText.contains("TOTAL") { score += 12 }
            if labelText.contains("GRAND TOTAL") { score += 14 }
            if labelText.contains("AMOUNT DUE") || labelText.contains("BALANCE DUE") { score += 14 }
            if labelText.contains("ORDER TOTAL") { score += 12 }
            if labelText.contains("PAY THIS AMOUNT") { score += 12 }

            if labelText.contains("SUBTOTAL") { score -= 8 }
            if labelText.contains("TAX") { score -= 6 }
            if labelText.contains("TIP") { score -= 4 }
            if labelText.contains("CHANGE") { score -= 8 }
            if labelText.contains("CASH") { score -= 2 }
            if labelText.contains("VISA") || labelText.contains("MASTERCARD") || labelText.contains("AMEX") { score -= 3 }

            if y < 0.22 { score += 5 }
            else if y < 0.32 { score += 3 }

            if amount >= 1 { score += 1 }

            return score
        }

        nonisolated private static func extractAmounts(from text: String) -> [Double] {
            let pattern = #"(?:USD\s*)?\$?\s*(\d{1,4}(?:[.,]\d{3})*(?:[.,]\d{2})|\d+\.\d{2})"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return []
            }

            let range = NSRange(text.startIndex..., in: text)
            return regex.matches(in: text, options: [], range: range).compactMap { match in
                guard match.numberOfRanges > 1,
                      let matchRange = Range(match.range(at: 1), in: text) else {
                    return nil
                }

                let raw = String(text[matchRange])
                    .replacingOccurrences(of: ",", with: "")
                return Double(raw)
            }
        }

        nonisolated private static func sanitizeMerchantCandidate(_ text: String) -> String {
            text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"[^A-Za-z0-9&' .-]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }

        nonisolated private static func isPlausibleMerchant(_ text: String) -> Bool {
            guard text.count >= 3, text.count <= 40 else { return false }
            guard text.rangeOfCharacter(from: .letters) != nil else { return false }
            guard text.rangeOfCharacter(from: .decimalDigits) == nil else { return false }

            let upper = text.uppercased()
            let blockedTerms = [
                "RECEIPT", "THANK YOU", "MERCHANT COPY", "CUSTOMER COPY",
                "APPROVED", "DECLINED", "STORE", "TEL", "PHONE", "WWW",
                "DATE", "TIME", "ORDER", "INVOICE", "TRANSACTION", "TOTAL",
                "SUBTOTAL", "TAX", "TIP", "CHANGE", "VISA", "MASTERCARD", "AMEX"
            ]

            return !blockedTerms.contains { upper.contains($0) }
        }

        nonisolated private static func uniqueStrings(_ values: [String]) -> [String] {
            var seen = Set<String>()
            var result: [String] = []

            for value in values where seen.insert(value).inserted {
                result.append(value)
            }

            return result
        }
    }
}
