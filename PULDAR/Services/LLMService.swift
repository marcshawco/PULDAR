import Foundation
import QuartzCore
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

/// On-device LLM service for natural-language expense parsing.
///
/// Downloads a quantised Qwen 2.5 0.5B model the first time,
/// then runs entirely offline.  The model's **only** job is text extraction —
/// it returns a strict JSON dict that Swift code then maps to the data model.
///
/// ## Memory Budget
/// - GPU cache capped at 20 MB via `MLX.Memory.cacheLimit`.
/// - Model weights ≈ 400 MB in 4-bit quantisation.
/// - The "Increased Memory Limit" entitlement raises the process ceiling
///   to ~3-4 GB, well within the A17 Pro's 8 GB unified memory.
@Observable
@MainActor
final class LLMService {
    private struct ReceiptHints {
        let likelyMerchant: String?
        let likelyTotal: Double?
        let merchantCandidates: [String]
    }

    // MARK: - Load State

    enum LoadState: Equatable {
        case idle
        case downloading(progress: Double)
        case loading
        case ready
        case error(String)

        static func == (lhs: LoadState, rhs: LoadState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading), (.ready, .ready):
                return true
            case let (.downloading(a), .downloading(b)):
                return a == b
            case let (.error(a), .error(b)):
                return a == b
            default:
                return false
            }
        }
    }

    private(set) var loadState: LoadState = .idle
    private var hasDownloadedModel: Bool {
        let defaults = UserDefaults.standard
        return modelContainer != nil
            || defaults.bool(forKey: "didDownloadLocalModel")
            || defaults.bool(forKey: "didCompleteModelOnboarding")
    }

    // MARK: - Internals

    private var modelContainer: ModelContainer?
    private var parseCache: [String: LLMExpenseResult] = [:]
    private let parseCacheKey = "llmParseCache.v2"
    private var lastLoadProgressUpdate: CFTimeInterval = 0
    private var lastReportedProgressBucket: Int = -1

    private let defaultCategories = ExpenseCategory.allCases.map(\.rawValue)

    init() {
        restoreParseCache()
    }

    // MARK: - Model Lifecycle

    /// Download (if needed) and load the quantised model into memory.
    func loadModel() async {
        guard modelContainer == nil else {
            loadState = .ready
            return
        }

        // If we've already downloaded once, skip the noisy "downloading" state.
        loadState = hasDownloadedModel ? .loading : .downloading(progress: 0)

        // Cap Metal working set to keep background footprint lean.
        MLX.Memory.cacheLimit = AppConstants.gpuCacheLimitBytes

        do {
            let config = ModelConfiguration(id: AppConstants.modelID)

            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { progress in
                Task { @MainActor in
                    let rawFraction = progress.fractionCompleted
                    let fraction = rawFraction.isFinite ? min(max(rawFraction, 0), 1) : 0
                    self.updateLoadProgress(fraction)
                }
            }

            self.modelContainer = container
            UserDefaults.standard.set(true, forKey: "didDownloadLocalModel")
            self.loadState = .ready
        } catch {
            self.loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - Inference

    /// Parse a natural-language expense string into structured data.
    ///
    /// - Parameter input: e.g. `"I just spent $54.83 on sushi"`
    /// - Parameter allowedCategories: optional user-customized category labels.
    /// - Returns: `LLMExpenseResult` with merchant, amount, category, and transaction type.
    func parseExpense(from input: String, allowedCategories: [String]? = nil) async throws -> LLMExpenseResult {
        if modelContainer == nil {
            await loadModel()
        }
        guard let container = modelContainer else { throw LLMError.modelNotLoaded }

        let categories = (allowedCategories?.isEmpty == false)
            ? (allowedCategories ?? defaultCategories)
            : defaultCategories
        let isReceiptScan = input.localizedCaseInsensitiveContains("Receipt scan")
        let cacheKey = makeParseCacheKey(input: input, categories: categories)
        if !isReceiptScan, let cached = parseCache[cacheKey] {
            return cached
        }
        let systemPrompt = makeSystemPrompt(categories: categories)

        // Build chat messages for template formatting.
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user",   "content": input]
        ]

        // Format the prompt using the model's chat template,
        // then generate and decode — all inside `perform` for
        // correct Sendable isolation.
        let responseText: String = try await container.perform { context in
            // applyChatTemplate returns [Int] token IDs — decode back to
            // String so the processor can re-tokenize with its own pipeline.
            let tokenIds = try context.tokenizer.applyChatTemplate(messages: messages)
            let promptString = context.tokenizer.decode(tokens: tokenIds)

            let generateParams = GenerateParameters(temperature: 0.1)

            let processedInput = try await context.processor.prepare(
                input: .init(prompt: promptString)
            )

            // Generate tokens asynchronously and collect decoded text.
            var collected = ""
            var generatedTokenCount = 0
            let stream = try MLXLMCommon.generateTokens(
                input: processedInput,
                parameters: generateParams,
                context: context
            )

            for await generation in stream {
                if case let .token(token) = generation {
                    collected += context.tokenizer.decode(tokens: [token])
                    generatedTokenCount += 1
                    // Hard cap at 200 tokens — valid JSON is always short.
                    if generatedTokenCount >= 200 {
                        break
                    }
                }
            }
            return collected
        }

        let parsed = try extractJSON(from: responseText)
        let refined = refineParsedExpense(parsed, originalInput: input)
        cacheParsedExpense(refined, for: cacheKey)
        return refined
    }

    private func makeSystemPrompt(categories: [String]) -> String {
        """
        You are an expense parser. Given a natural language expense description, \
        extract the merchant name, dollar amount, and spending category.

        If the input is a receipt scan:
        - Prefer the establishment name near the top of the receipt.
        - Prefer a provided "Likely merchant" hint over raw OCR lines.
        - Prefer a provided "Likely total" hint over individual line items.
        - The final amount should usually be the receipt total near the bottom, not subtotal, tax, tip alone, item prices, or card digits.
        - Ignore payment network names, processor text, terminal text, and generic words like RECEIPT or THANK YOU when choosing the merchant.

        Respond ONLY with a single JSON object — no markdown, no commentary:
        {"merchant": "Store Name", "amount": 12.50, "category": "groceries", "transactionType": "expense"}

        transactionType must be exactly one of:
        expense, credit
        - Use "expense" for spending money.
        - Use "credit" for money received, refunds, reimbursements, gifts, or balance increases.
        - Terms like "bitcoin", "btc", "crypto", "S&P 500", "stock", "ETF", and "index fund"
          are investments and should be categorized as investments (never fun/entertainment).
        - "comic books", "disneyland/theme park", and "snacks/treats" are fun spending,
          not groceries or other essentials.

        Category must be exactly one of:
        \(categories.joined(separator: ", "))
        """
    }

    // MARK: - JSON Extraction

    /// Find and decode JSON from potentially noisy LLM output.
    ///
    /// Small models sometimes wrap the JSON in markdown fences or add
    /// commentary; this method isolates the `{ … }` substring first.
    private func extractJSON(from text: String) throws -> LLMExpenseResult {
        // 1. Try to locate the first { ... } pair.
        guard let openBrace = text.firstIndex(of: "{"),
              let closeBrace = text[openBrace...].lastIndex(of: "}") else {
            // 2. Fallback: try regex-based extraction for edge cases.
            return try regexFallback(from: text)
        }

        let jsonSlice = String(text[openBrace...closeBrace])

        guard let data = jsonSlice.data(using: .utf8) else {
            throw LLMError.invalidJSON(jsonSlice)
        }

        do {
            return try JSONDecoder().decode(LLMExpenseResult.self, from: data)
        } catch {
            // If JSON decode fails, try the regex fallback.
            return try regexFallback(from: text)
        }
    }

    private func refineParsedExpense(_ parsed: LLMExpenseResult, originalInput: String) -> LLMExpenseResult {
        guard let hints = receiptHints(from: originalInput) else {
            return parsed
        }

        let refinedMerchant = refinedMerchantName(
            parsedMerchant: parsed.merchant,
            hints: hints
        )
        let refinedAmount = refinedAmountValue(
            parsedAmount: parsed.amount,
            hints: hints
        )

        return LLMExpenseResult(
            merchant: refinedMerchant,
            amount: refinedAmount,
            category: parsed.category,
            transactionType: parsed.transactionType
        )
    }

    private func receiptHints(from input: String) -> ReceiptHints? {
        guard input.localizedCaseInsensitiveContains("Receipt scan") else {
            return nil
        }

        let likelyMerchant = captureLineValue(prefix: "Likely merchant:", in: input)
        let likelyTotal = captureAmount(prefix: "Likely total:", in: input)
        let merchantCandidates = captureLineValue(prefix: "Merchant candidates:", in: input)?
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        return ReceiptHints(
            likelyMerchant: likelyMerchant,
            likelyTotal: likelyTotal,
            merchantCandidates: merchantCandidates
        )
    }

    private func captureLineValue(prefix: String, in input: String) -> String? {
        guard let line = input
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }

        let value = line
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return value.isEmpty ? nil : value
    }

    private func captureAmount(prefix: String, in input: String) -> Double? {
        guard let lineValue = captureLineValue(prefix: prefix, in: input) else {
            return nil
        }

        let cleaned = lineValue
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

    private func refinedMerchantName(parsedMerchant: String, hints: ReceiptHints) -> String {
        let normalizedParsed = parsedMerchant.normalizedMerchantName()
        let normalizedHint = hints.likelyMerchant?.normalizedMerchantName()
        let normalizedCandidates = hints.merchantCandidates.map { $0.normalizedMerchantName() }

        if isWeakReceiptMerchant(normalizedParsed),
           let normalizedHint,
           !normalizedHint.isEmpty {
            return normalizedHint
        }

        if let normalizedHint,
           !normalizedHint.isEmpty,
           !normalizedParsed.isEmpty {
            if merchantNamesAppearEquivalent(normalizedParsed, normalizedHint) {
                return normalizedHint
            }

            if !normalizedCandidates.isEmpty,
               !normalizedCandidates.contains(where: { merchantNamesAppearEquivalent(normalizedParsed, $0) }) {
                return normalizedHint
            }
        }

        return normalizedParsed
    }

    private func refinedAmountValue(parsedAmount: Double, hints: ReceiptHints) -> Double {
        guard let likelyTotal = hints.likelyTotal, likelyTotal > 0 else {
            return parsedAmount
        }

        let unsignedParsed = abs(parsedAmount)
        let tolerance = max(0.05, likelyTotal * 0.015)
        guard abs(unsignedParsed - likelyTotal) > tolerance else {
            return parsedAmount
        }

        return parsedAmount < 0 ? -likelyTotal : likelyTotal
    }

    private func isWeakReceiptMerchant(_ merchant: String) -> Bool {
        let normalized = merchant
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.isEmpty || normalized == "unknown" {
            return true
        }

        let weakTerms = [
            "receipt", "customer copy", "merchant copy", "approved", "declined",
            "visa", "mastercard", "amex", "terminal", "transaction"
        ]
        return weakTerms.contains { normalized.contains($0) }
    }

    private func merchantNamesAppearEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        let normalizedLHS = canonicalMerchantKey(lhs)
        let normalizedRHS = canonicalMerchantKey(rhs)
        return !normalizedLHS.isEmpty && normalizedLHS == normalizedRHS
    }

    private func canonicalMerchantKey(_ merchant: String) -> String {
        merchant
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    /// Last-resort parser using regex to extract merchant, amount, category,
    /// from semi-structured but malformed LLM output.
    private func regexFallback(from text: String) throws -> LLMExpenseResult {
        // Try to find an amount like $12.50 or 12.50
        let amountPattern = /\$?\s*(\d+\.?\d*)/
        guard let amountMatch = text.firstMatch(of: amountPattern),
              let amount = Double(amountMatch.1) else {
            throw LLMError.noJSONFound(text)
        }

        // Try to find a quoted merchant name
        let merchantPattern = /"merchant"\s*:\s*"([^"]+)"/
        let merchant: String
        if let m = text.firstMatch(of: merchantPattern) {
            merchant = String(m.1)
        } else {
            merchant = "Unknown"
        }

        // Try to find a quoted category
        let categoryPattern = /"category"\s*:\s*"([^"]+)"/
        let category: String
        if let c = text.firstMatch(of: categoryPattern) {
            category = String(c.1)
        } else {
            category = "other"
        }

        let transactionTypePattern = /"transactionType"\s*:\s*"([^"]+)"/
        let transactionType: LLMTransactionType?
        if let t = text.firstMatch(of: transactionTypePattern) {
            transactionType = LLMTransactionType(rawValue: String(t.1).lowercased())
        } else {
            transactionType = nil
        }

        return LLMExpenseResult(
            merchant: merchant,
            amount: amount,
            category: category,
            transactionType: transactionType
        )
    }

    // MARK: - Errors

    enum LLMError: LocalizedError {
        case modelNotLoaded
        case noJSONFound(String)
        case invalidJSON(String)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "The AI model is still loading. Please wait a moment."
            case .noJSONFound(let raw):
                return "Couldn't understand that input. Raw: \(raw.prefix(120))"
            case .invalidJSON(let raw):
                return "Failed to parse expense data. Raw: \(raw.prefix(120))"
            }
        }
    }

    // MARK: - Parse Cache

    private func makeParseCacheKey(input: String, categories: [String]) -> String {
        let normalizedInput = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedCategories = categories
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
            .sorted()
            .joined(separator: "|")
        return "\(normalizedInput)||\(normalizedCategories)"
    }

    private func cacheParsedExpense(_ parsed: LLMExpenseResult, for key: String) {
        parseCache[key] = parsed
        trimParseCacheIfNeeded()
        persistParseCache()
    }

    private func trimParseCacheIfNeeded() {
        let maxCacheEntries = 500
        guard parseCache.count > maxCacheEntries else { return }
        // Keep a bounded cache size. Sorted drop is deterministic.
        let overflowCount = parseCache.count - maxCacheEntries
        let keysToRemove = parseCache.keys.sorted().prefix(overflowCount)
        for key in keysToRemove {
            parseCache.removeValue(forKey: key)
        }
    }

    private func restoreParseCache() {
        guard let data = UserDefaults.standard.data(forKey: parseCacheKey) else { return }
        guard let decoded = try? JSONDecoder().decode([String: LLMExpenseResult].self, from: data) else {
            return
        }
        parseCache = decoded
        trimParseCacheIfNeeded()
    }

    private func persistParseCache() {
        guard let data = try? JSONEncoder().encode(parseCache) else { return }
        UserDefaults.standard.set(data, forKey: parseCacheKey)
    }

    private func updateLoadProgress(_ fraction: Double) {
        // Only show explicit download progress during first install
        // and avoid flickering 0%/100% on warm starts.
        guard !hasDownloadedModel else {
            if loadState != .loading {
                loadState = .loading
            }
            return
        }

        guard fraction > 0, fraction < 0.995 else {
            if loadState != .loading {
                loadState = .loading
            }
            return
        }

        // Throttle UI state churn to keep first-touch interactions responsive.
        let progressBucket = Int((fraction * 100).rounded(.down) / 2) // 2% steps
        let now = CACurrentMediaTime()
        let enoughTimeElapsed = (now - lastLoadProgressUpdate) > 0.12
        let progressed = progressBucket != lastReportedProgressBucket
        guard enoughTimeElapsed || progressed else { return }

        lastLoadProgressUpdate = now
        lastReportedProgressBucket = progressBucket
        loadState = .downloading(progress: fraction)
    }
}
