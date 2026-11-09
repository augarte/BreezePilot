import Foundation
import Security

struct XiaomiLocalSetup: XiaomiSetup {
    func check(address: LocalAddress, token: XiaomiToken) async throws -> XiaomiProfile {
        try await XiaomiClient.checkConnection(address: address, token: token)
    }

    func save(_ token: XiaomiToken, for id: UUID) throws {
        try XiaomiTokenStore.save(token, for: id)
    }

    func removeToken(for id: UUID) throws {
        try XiaomiTokenStore.remove(for: id)
    }
}

enum XiaomiTokenStore {
    static func read(for id: UUID) throws -> XiaomiToken {
        if ACWidgetStore.container != nil, let token = read(for: id, shared: true) {
            return token
        }
        guard let token = read(for: id, shared: false) else { throw XiaomiError.missingToken }
        return token
    }

    static func shareLegacyToken(for id: UUID) {
        guard let legacy = read(for: id, shared: false) else { return }
        do {
            if read(for: id, shared: true) == nil {
                try save(legacy, for: id, shared: true)
            }
            try remove(for: id, shared: false)
        } catch {
            // Keep the existing token when migration cannot complete.
        }
    }

    private static func read(for id: UUID, shared: Bool) -> XiaomiToken? {
        var query = query(for: id, shared: shared)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return XiaomiToken(bytes: data)
    }

    static func save(_ token: XiaomiToken, for id: UUID) throws {
        let shared = ACWidgetStore.container != nil
        try save(token, for: id, shared: shared)
        if shared { try? remove(for: id, shared: false) }
    }

    private static func save(_ token: XiaomiToken, for id: UUID, shared: Bool) throws {
        let query = query(for: id, shared: shared)
        let values = [
            kSecValueData as String: token.bytes,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ] as [String: Any]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(values) { _, new in new }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw XiaomiError.keychain }
        } else if status != errSecSuccess {
            throw XiaomiError.keychain
        }
    }

    static func remove(for id: UUID) throws {
        try remove(for: id, shared: false)
        if ACWidgetStore.container != nil { try remove(for: id, shared: true) }
    }

    private static func remove(for id: UUID, shared: Bool) throws {
        let status = SecItemDelete(query(for: id, shared: shared) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw XiaomiError.keychain }
    }

    private static func query(for id: UUID, shared: Bool) -> [String: Any] {
        var attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: shared ? "local.daikin.directcontrol.xiaomi.shared" : "local.daikin.directcontrol.xiaomi",
            kSecAttrAccount as String: id.uuidString
        ]
        if shared { attributes[kSecAttrAccessGroup as String] = ACWidgetStore.group }
        return attributes
    }
}

enum XiaomiError: LocalizedError {
    case missingToken
    case noReply
    case authentication
    case incompatible
    case catalogUnavailable
    case keychain

    var errorDescription: String? {
        switch self {
        case .missingToken: "Enter the AC’s Xiaomi device token in Edit AC."
        case .noReply: ACDeviceError.unreachable.localizedDescription
        case .authentication: "The AC’s reply couldn’t be verified. Check the device token and address."
        case .incompatible: "This AC didn’t provide a compatible Xiaomi local status."
        case .catalogUnavailable: "Couldn’t load Xiaomi’s public model specifications. Check your internet connection and try again."
        case .keychain: "Couldn’t update the device token in Keychain."
        }
    }
}
