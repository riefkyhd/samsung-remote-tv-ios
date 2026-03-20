import Foundation
import Security

struct TVSecureStorage: Sendable {
    private enum Prefix {
        static let token = "token_"
        static let spc = "spc_"
        static let spcVariant = "spc_variant_"
    }

    private let service: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(service: String = Bundle.main.bundleIdentifier ?? "SamsungRemoteTV") {
        self.service = service
    }

    func saveToken(_ token: String, identifier: String) throws {
        guard !identifier.isEmpty else { return }
        try upsert(data: Data(token.utf8), account: Prefix.token + identifier)
    }

    func loadToken(identifier: String) -> String? {
        guard !identifier.isEmpty,
              let data = read(account: Prefix.token + identifier) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteToken(identifier: String) {
        guard !identifier.isEmpty else { return }
        delete(account: Prefix.token + identifier)
    }

    func saveSpcCredentials(_ credentials: TVUserDefaultsStorage.SpcCredentials, identifier: String) throws {
        guard !identifier.isEmpty else { return }
        let data = try encoder.encode(credentials)
        try upsert(data: data, account: Prefix.spc + identifier)
    }

    func loadSpcCredentials(identifier: String) -> TVUserDefaultsStorage.SpcCredentials? {
        guard !identifier.isEmpty,
              let data = read(account: Prefix.spc + identifier) else { return nil }
        return try? decoder.decode(TVUserDefaultsStorage.SpcCredentials.self, from: data)
    }

    func deleteSpcCredentials(identifier: String) {
        guard !identifier.isEmpty else { return }
        delete(account: Prefix.spc + identifier)
    }

    func saveSpcVariants(_ variants: TVUserDefaultsStorage.SpcVariants, identifier: String) throws {
        guard !identifier.isEmpty else { return }
        let data = try encoder.encode(variants)
        try upsert(data: data, account: Prefix.spcVariant + identifier)
    }

    func loadSpcVariants(identifier: String) -> TVUserDefaultsStorage.SpcVariants? {
        guard !identifier.isEmpty,
              let data = read(account: Prefix.spcVariant + identifier) else { return nil }
        return try? decoder.decode(TVUserDefaultsStorage.SpcVariants.self, from: data)
    }

    func deleteSpcVariants(identifier: String) {
        guard !identifier.isEmpty else { return }
        delete(account: Prefix.spcVariant + identifier)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func upsert(data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw TVSecureStorageError.keychainStatus(addStatus)
            }
        default:
            throw TVSecureStorageError.keychainStatus(updateStatus)
        }
    }

    private func read(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func delete(account: String) {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
    }
}

enum TVSecureStorageError: Error {
    case keychainStatus(OSStatus)
}
