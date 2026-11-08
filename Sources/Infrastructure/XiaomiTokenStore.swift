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
        var query = query(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let token = XiaomiToken(bytes: data) else {
            throw XiaomiError.missingToken
        }
        return token
    }

    static func save(_ token: XiaomiToken, for id: UUID) throws {
        let query = query(for: id)
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
        let status = SecItemDelete(query(for: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw XiaomiError.keychain }
    }

    private static func query(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "local.daikin.directcontrol.xiaomi",
            kSecAttrAccount as String: id.uuidString
        ]
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
        case .noReply: "The AC didn’t answer over Wi‑Fi. Check its address, device token, and Local Network access."
        case .authentication: "The AC’s reply couldn’t be verified. Check the device token and address."
        case .incompatible: "This AC didn’t provide a compatible Xiaomi local status."
        case .catalogUnavailable: "Couldn’t load Xiaomi’s public model specifications. Check your internet connection and try again."
        case .keychain: "Couldn’t update the device token in Keychain."
        }
    }
}
