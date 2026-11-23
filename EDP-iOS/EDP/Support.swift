import Foundation
import Security
import UIKit

/// Erreur lisible renvoyée au site.
struct BridgeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Config {
    /// Adresse du serveur EDP, réglée dans project.yml (EDP_SERVER_URL).
    static let serverURL: URL = {
        if let s = Bundle.main.object(forInfoDictionaryKey: "EDPServerURL") as? String,
           !s.isEmpty, !s.contains("$("), let u = URL(string: s) {
            return u
        }
        return URL(string: "https://cartable.bizzarirobin66.workers.dev")!
    }()
}

/// Petit coffre-fort (trousseau iOS) pour le jeton de session EDP.
enum Keychain {
    private static let service = "edp.session"

    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value = value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        // lisible en arrière-plan (mise à jour de position) une fois le téléphone déverrouillé après démarrage
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Session EDP partagée par le site (jeton).
enum Session {
    static func save(token: String?, server: String?) {
        Keychain.set(token, for: "token")
        if let server = server, URL(string: server) != nil {
            UserDefaults.standard.set(server, forKey: "server")
        }
    }

    static var token: String? { Keychain.get("token") }

    static var server: URL {
        if let s = UserDefaults.standard.string(forKey: "server"), let u = URL(string: s) { return u }
        return Config.serverURL
    }
}
