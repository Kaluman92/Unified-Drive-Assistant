//
//  AIAssistantService.swift
//  Unified Drive Assistant
//
//  ============================================================
//  AI ASSISTANT BLOCK — BRING YOUR OWN KEY (BYOK)
//  ------------------------------------------------------------
//  Every user supplies their own personal API key for whichever
//  provider they pick (Claude / ChatGPT / Gemini). This is the
//  INTENDED, PERMANENT design — not a temporary testing measure.
//  There is no shared backend, no developer-provided key, and no
//  central account footing everyone's API bill. Each person's
//  usage is billed to their own account with their own provider,
//  under their own rate limits.
//
//  This means the app calls each provider's API directly from the
//  device, using whichever key that specific user entered in
//  Settings. Keys are stored in the iOS Keychain (KeychainHelper.swift),
//  not UserDefaults, since this is real per-user secret storage now,
//  not a throwaway testing shortcut. A key never leaves the device
//  it was entered on, and this app has no visibility into it beyond
//  using it to make requests on that user's behalf.
//
//  Feature is fully gated by `isEnabled` (user-controlled in
//  Settings). When off, no network call is ever made — the static
//  Cause/Remedy fields are always shown regardless of this setting.
//  ============================================================

import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case claude = "claude"
    case chatgpt = "chatgpt"
    case gemini = "gemini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        }
    }

    /// Where to get a personal API key for this provider — shown in
    /// Settings so the person can go get their own key.
    var keySourceDescription: String {
        switch self {
        case .claude: return "console.anthropic.com"
        case .chatgpt: return "platform.openai.com"
        case .gemini: return "aistudio.google.com"
        }
    }

    fileprivate var keychainKey: String {
        "ai_api_key_\(rawValue)"
    }
}

@MainActor
final class AIAssistantService: ObservableObject {

    static let shared = AIAssistantService()

    /// User-controlled on/off switch for the whole AI feature.
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "ai_assistant_enabled")
            if let uid = AuthManager.shared.currentUser?.uid {
                AnalyticsService.shared.logAIAssistToggled(uid: uid, enabled: isEnabled)
            }
        }
    }

    /// Which provider this user wants to use. Persisted locally — this is
    /// just a preference, not a security boundary; the actual key for
    /// whichever provider is selected is looked up from the Keychain.
    @Published var selectedProvider: AIProvider {
        didSet {
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: "ai_assistant_provider")
        }
    }

    /// The current provider's own API key, as entered by this user. Reads
    /// from and writes to the Keychain — see KeychainHelper.swift. Bound
    /// directly to the SecureField in Settings.
    var apiKey: String {
        get { KeychainHelper.get(forKey: selectedProvider.keychainKey) ?? "" }
        set {
            objectWillChange.send()
            if newValue.isEmpty {
                KeychainHelper.delete(forKey: selectedProvider.keychainKey)
            } else {
                KeychainHelper.set(newValue, forKey: selectedProvider.keychainKey)
            }
        }
    }

    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    // Model used per provider. These change over time — if a request
    // starts failing, check the provider's current docs and update here.
    private let claudeModel = "claude-sonnet-5"
    private let chatGPTModel = "gpt-4o-mini"
    private let geminiModel = "gemini-2.0-flash"

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "ai_assistant_enabled") as? Bool ?? true
        let savedProvider = UserDefaults.standard.string(forKey: "ai_assistant_provider") ?? ""
        self.selectedProvider = AIProvider(rawValue: savedProvider) ?? .claude
    }

    /// Requests plain-language, step-by-step guidance for a looked-up
    /// fault, using the current user's own key for the currently selected
    /// provider. Returns nil if the assistant is off, no key is set, or
    /// the call fails — in which case `lastError` is set and the UI
    /// should fall back to the static Cause/Remedy fields.
    func guidance(for fault: FaultCode) async -> String? {
        guard isEnabled else { return nil }

        let key = apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            lastError = "Add your own \(selectedProvider.displayName) API key in Settings — each user provides their own."
            return nil
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let prompt = Self.buildPrompt(for: fault)

        do {
            let result: String
            switch selectedProvider {
            case .claude:
                result = try await requestClaude(prompt: prompt, key: key)
            case .chatgpt:
                result = try await requestChatGPT(prompt: prompt, key: key)
            case .gemini:
                result = try await requestGemini(prompt: prompt, key: key)
            }

            if let uid = AuthManager.shared.currentUser?.uid {
                AnalyticsService.shared.logAIAssistUsed(uid: uid, vendor: Vendor(rawValue: fault.brand) ?? .siemens, code: fault.code)
            }
            return result
        } catch {
            lastError = "Couldn't reach \(selectedProvider.displayName). Check your API key and connection — showing the standard remedy instead."
            return nil
        }
    }

    private static func buildPrompt(for fault: FaultCode) -> String {
        """
        You are helping a field engineer troubleshoot a variable-frequency \
        drive fault. Give a short, practical, step-by-step checklist a \
        technician could follow on-site. Do not invent facts about the \
        specific drive beyond what's given below — if you're not sure, say so.

        Brand: \(fault.brand)
        Drive family: \(fault.familyLabel)
        Fault code: \(fault.code)
        Fault name: \(fault.title)
        Known cause: \(fault.cause)
        Known remedy: \(fault.remedy)

        Expand this into clear, numbered troubleshooting steps a technician \
        can follow in the field. Keep it under 150 words.
        """
    }

    // MARK: - Anthropic (Claude)

    private func requestClaude(prompt: String, key: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": claudeModel,
            "max_tokens": 500,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkAuthFailure(response, provider: "Claude", setError: { self.lastError = $0 })

        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        return decoded.content.first(where: { $0.type == "text" })?.text ?? "No guidance returned."
    }

    // MARK: - OpenAI (ChatGPT)

    private func requestChatGPT(prompt: String, key: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": chatGPTModel,
            "max_tokens": 500,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkAuthFailure(response, provider: "ChatGPT", setError: { self.lastError = $0 })

        let decoded = try JSONDecoder().decode(ChatGPTResponse.self, from: data)
        return decoded.choices.first?.message.content ?? "No guidance returned."
    }

    // MARK: - Google (Gemini)

    private func requestGemini(prompt: String, key: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(geminiModel):generateContent?key=\(key)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["maxOutputTokens": 500]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkAuthFailure(response, provider: "Gemini", setError: { self.lastError = $0 })

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        return decoded.candidates.first?.content.parts.first?.text ?? "No guidance returned."
    }

    // MARK: - Shared helpers

    private static func checkAuthFailure(_ response: URLResponse, provider: String, setError: (String) -> Void) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                setError("Your \(provider) API key was rejected — check it in Settings.")
            }
            throw URLError(.badServerResponse)
        }
    }
}

// MARK: - Response shapes (one per provider — each has its own format)

private struct ClaudeResponse: Decodable {
    let content: [ContentBlock]
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}

private struct ChatGPTResponse: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let message: Message
    }
    struct Message: Decodable {
        let content: String
    }
}

private struct GeminiResponse: Decodable {
    let candidates: [Candidate]
    struct Candidate: Decodable {
        let content: Content
    }
    struct Content: Decodable {
        let parts: [Part]
    }
    struct Part: Decodable {
        let text: String?
    }
}
