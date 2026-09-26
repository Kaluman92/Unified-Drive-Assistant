//
//  KeychainHelper.swift
//  Unified Drive Assistant
//
//  ============================================================
//  AI ASSISTANT BLOCK — SECURE KEY STORAGE
//  ------------------------------------------------------------
//  Minimal wrapper around the iOS Keychain for storing each
//  user's own AI provider API keys. Used instead of UserDefaults
//  because this is now the permanent design (every user supplies
//  their own personal key — see AIAssistantService.swift's file
//  header), not a temporary testing measure, so it deserves
//  better-than-plaintext storage.
//  ============================================================

import Foundation
import Security

enum KeychainHelper {
    static let defaultService = "com.silcore.unifieddriveassistant.aikeys"

    /// Separate service for sign-in session data (Auth/AuthManager.swift),
    /// so it never mixes with the AI keys above.
    static let authService = "com.silcore.unifieddriveassistant.auth"

    static func set(_ value: String, forKey key: String, service: String = defaultService) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)   // remove any existing value first

        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func get(forKey key: String, service: String = defaultService) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(forKey key: String, service: String = defaultService) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
