import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// On-device LLM service for natural-language expense parsing.
///
/// Downloads a quantised Qwen 2.5 0.5B model the first time,
/// then runs entirely offline.  The model's **only** job is text extraction —
/// it returns a strict JSON dict that Swift code then maps to the data model.
///
/// ## Memory Budget
/// - GPU cache capped at 20 MB via `MLX.GPU.set(cacheLimit:)`.
/// - Model weights ≈ 400 MB in 4-bit quantisation.
/// - The "Increased Memory Limit" entitlement raises the process ceiling
///   to ~3-4 GB, well within the A17 Pro's 8 GB unified memory.
@Observable
@MainActor
final class LLMService {

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

    // MARK: - Internals

    private var modelContainer: ModelContainer?

    /// The system prompt constrains the model to pure JSON extraction.
    private let systemPrompt = """
    You are an expense parser. Given a natural language expense description, \
    extract the merchant name, dollar amount, and spending category.

    Respond ONLY with a single JSON object — no markdown, no commentary:
    {"merchant": "Store Name", "amount": 12.50, "category": "groceries"}

    Valid categories (pick the closest match):
    rent, mortgage, utilities, groceries, insurance, healthcare, \
    transportation, gas, phone, internet, dining, entertainment, \
    shopping, clothing, subscriptions, hobbies, travel, coffee, \
    alcohol, gifts, savings, investments, retirement, debt, \
    education, emergency, charity, other
    """

    // MARK: - Model Lifecycle

    /// Download (if needed) and load the quantised model into memory.
    func loadModel() async {
        guard modelContainer == nil else {
            loadState = .ready
            return
        }

        loadState = .downloading(progress: 0)

        // Cap Metal working set to keep background footprint lean.
        MLX.GPU.set(cacheLimit: AppConstants.gpuCacheLimitBytes)

        do {
            let config = ModelConfiguration(id: AppConstants.modelID)

            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { progress in
                Task { @MainActor in
                    self.loadState = .downloading(
                        progress: progress.fractionCompleted
                    )
                }
            }

            self.modelContainer = container
            self.loadState = .ready
        } catch {
            self.loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - Inference

    /// Parse a natural-language expense string into structured data.
    ///
    /// - Parameter input: e.g. `"I just spent $54.83 on sushi"`
    /// - Returns: `LLMExpenseResult` with merchant, amount, category.
    func parseExpense(from input: String) async throws -> LLMExpenseResult {
        guard let container = modelContainer else {
            throw LLMError.modelNotLoaded
        }

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
            let promptString = context.tokenizer.decode(tokens: tokenIds) ?? ""

            let generateParams = GenerateParameters(temperature: 0.1)

            let processedInput = try await context.processor.prepare(
                input: .init(prompt: promptString)
            )

            // Generate tokens, collecting text inside the closure scope
            // so that no mutable state crosses an isolation boundary.
            var collected = ""
            let _ = try MLXLMCommon.generate(
                input: processedInput,
                parameters: generateParams,
                context: context
            ) { tokens in
                // Decode the latest token and append.
                if let piece = context.tokenizer.decode(tokens: [tokens.last!]) {
                    collected += piece
                }
                // Hard cap at 200 tokens — valid JSON is always short.
                return tokens.count >= 200 ? .stop : .more
            }
            return collected
        }

        return try extractJSON(from: responseText)
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

    /// Last-resort parser using regex to extract merchant, amount, category
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

        return LLMExpenseResult(
            merchant: merchant,
            amount: amount,
            category: category
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
}
