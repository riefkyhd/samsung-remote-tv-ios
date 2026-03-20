import Foundation

struct TVUserDefaultsStorage: Sendable {
    struct SpcCredentials: Codable, Sendable {
        let ctxUpperHex: String
        let sessionId: Int
    }

    struct SpcVariants: Codable, Sendable {
        let step0: String?
        let step1: String?
    }

    private enum Keys {
        static let savedTVs = "saved_tvs"
        static let remoteName = "remote_name"
        static let deviceID = "spc_device_id"
    }

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadSavedTVs() throws -> [SamsungTV] {
        guard let data = userDefaults.data(forKey: Keys.savedTVs) else {
            return []
        }
        return try decoder.decode([SamsungTV].self, from: data)
    }

    func saveTVs(_ tvs: [SamsungTV]) throws {
        let data = try encoder.encode(tvs)
        userDefaults.set(data, forKey: Keys.savedTVs)
    }

    func saveToken(_ token: String, macAddress: String) {
        guard !macAddress.isEmpty else { return }
        userDefaults.set(token, forKey: tokenKey(for: macAddress))
    }

    func loadToken(macAddress: String) -> String? {
        guard !macAddress.isEmpty else { return nil }
        return userDefaults.string(forKey: tokenKey(for: macAddress))
    }

    func deleteToken(macAddress: String) {
        guard !macAddress.isEmpty else { return }
        userDefaults.removeObject(forKey: tokenKey(for: macAddress))
    }

    func saveRemoteName(_ name: String) {
        userDefaults.set(name, forKey: Keys.remoteName)
    }

    func loadRemoteName() -> String {
        userDefaults.string(forKey: Keys.remoteName) ?? "SamsungTVRemote"
    }

    func saveSpcCredentials(_ credentials: SpcCredentials, identifier: String) throws {
        guard !identifier.isEmpty else { return }
        let data = try encoder.encode(credentials)
        userDefaults.set(data, forKey: spcKey(for: identifier))
    }

    func saveSpcCredentials(macAddress: String, ctxUpperHex: String, sessionId: Int) {
        guard !macAddress.isEmpty else { return }
        let creds = SpcCredentials(ctxUpperHex: ctxUpperHex, sessionId: sessionId)
        if let data = try? encoder.encode(creds) {
            userDefaults.set(data, forKey: spcKey(for: macAddress))
        }
    }

    func loadSpcCredentials(identifier: String) -> SpcCredentials? {
        guard !identifier.isEmpty,
              let data = userDefaults.data(forKey: spcKey(for: identifier)) else {
            return nil
        }
        return try? decoder.decode(SpcCredentials.self, from: data)
    }

    func deleteSpcCredentials(identifier: String) {
        guard !identifier.isEmpty else { return }
        userDefaults.removeObject(forKey: spcKey(for: identifier))
    }

    func clearSpcCredentials(macAddress: String) {
        guard !macAddress.isEmpty else { return }
        userDefaults.removeObject(forKey: spcKey(for: macAddress))
    }

    func loadOrCreateSpcDeviceID() -> String {
        if let existing = userDefaults.string(forKey: Keys.deviceID), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        userDefaults.set(generated, forKey: Keys.deviceID)
        return generated
    }

    func saveSpcVariants(_ variants: SpcVariants, identifier: String) throws {
        guard !identifier.isEmpty else { return }
        let data = try encoder.encode(variants)
        userDefaults.set(data, forKey: spcVariantKey(for: identifier))
    }

    func loadSpcVariants(identifier: String) -> SpcVariants? {
        guard !identifier.isEmpty,
              let data = userDefaults.data(forKey: spcVariantKey(for: identifier)) else {
            return nil
        }
        return try? decoder.decode(SpcVariants.self, from: data)
    }

    func deleteSpcVariants(identifier: String) {
        guard !identifier.isEmpty else { return }
        userDefaults.removeObject(forKey: spcVariantKey(for: identifier))
    }

    private func tokenKey(for macAddress: String) -> String {
        "token_\(macAddress)"
    }

    private func spcKey(for identifier: String) -> String {
        "spc_\(identifier)"
    }

    private func spcVariantKey(for identifier: String) -> String {
        "spc_variant_\(identifier)"
    }
}
