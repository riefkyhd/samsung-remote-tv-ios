import Foundation

struct TVSensitiveStorage: Sendable {
    private let legacy: TVUserDefaultsStorage
    private let secure: TVSecureStorage

    init(legacy: TVUserDefaultsStorage, secure: TVSecureStorage) {
        self.legacy = legacy
        self.secure = secure
    }

    func saveToken(_ token: String, identifier: String) {
        guard !identifier.isEmpty else { return }
        do {
            try secure.saveToken(token, identifier: identifier)
            legacy.deleteToken(macAddress: identifier)
        } catch {
            DiagnosticsLogger.log(
                .error,
                "secure token save failed",
                metadata: [
                    "identifier": DiagnosticsLogger.redactIdentifier(identifier)
                ]
            )
        }
    }

    func loadToken(identifier: String) -> String? {
        guard !identifier.isEmpty else { return nil }
        if let secureValue = secure.loadToken(identifier: identifier) {
            legacy.deleteToken(macAddress: identifier)
            return secureValue
        }
        guard let legacyValue = legacy.loadToken(macAddress: identifier) else {
            return nil
        }
        do {
            try secure.saveToken(legacyValue, identifier: identifier)
            legacy.deleteToken(macAddress: identifier)
        } catch {
            DiagnosticsLogger.log(
                .error,
                "secure token migration failed",
                metadata: [
                    "identifier": DiagnosticsLogger.redactIdentifier(identifier)
                ]
            )
        }
        return legacyValue
    }

    func saveSpcCredentials(_ credentials: TVUserDefaultsStorage.SpcCredentials, identifier: String) {
        guard !identifier.isEmpty else { return }
        do {
            try secure.saveSpcCredentials(credentials, identifier: identifier)
            legacy.deleteSpcCredentials(identifier: identifier)
        } catch {
            DiagnosticsLogger.log(
                .error,
                "secure spc credentials save failed",
                metadata: [
                    "identifier": DiagnosticsLogger.redactIdentifier(identifier)
                ]
            )
        }
    }

    func loadSpcCredentials(identifier: String) -> TVUserDefaultsStorage.SpcCredentials? {
        guard !identifier.isEmpty else { return nil }
        if let secureValue = secure.loadSpcCredentials(identifier: identifier) {
            legacy.deleteSpcCredentials(identifier: identifier)
            return secureValue
        }
        guard let legacyValue = legacy.loadSpcCredentials(identifier: identifier) else {
            return nil
        }
        do {
            try secure.saveSpcCredentials(legacyValue, identifier: identifier)
            legacy.deleteSpcCredentials(identifier: identifier)
        } catch {
            DiagnosticsLogger.log(
                .error,
                "secure spc credentials migration failed",
                metadata: [
                    "identifier": DiagnosticsLogger.redactIdentifier(identifier)
                ]
            )
        }
        return legacyValue
    }

    func saveSpcVariants(_ variants: TVUserDefaultsStorage.SpcVariants, identifier: String) {
        guard !identifier.isEmpty else { return }
        do {
            try secure.saveSpcVariants(variants, identifier: identifier)
            legacy.deleteSpcVariants(identifier: identifier)
        } catch {
            DiagnosticsLogger.log(
                .error,
                "secure spc variants save failed",
                metadata: [
                    "identifier": DiagnosticsLogger.redactIdentifier(identifier)
                ]
            )
        }
    }

    func loadSpcVariants(identifier: String) -> TVUserDefaultsStorage.SpcVariants? {
        guard !identifier.isEmpty else { return nil }
        if let secureValue = secure.loadSpcVariants(identifier: identifier) {
            legacy.deleteSpcVariants(identifier: identifier)
            return secureValue
        }
        guard let legacyValue = legacy.loadSpcVariants(identifier: identifier) else {
            return nil
        }
        do {
            try secure.saveSpcVariants(legacyValue, identifier: identifier)
            legacy.deleteSpcVariants(identifier: identifier)
        } catch {
            DiagnosticsLogger.log(
                .error,
                "secure spc variants migration failed",
                metadata: [
                    "identifier": DiagnosticsLogger.redactIdentifier(identifier)
                ]
            )
        }
        return legacyValue
    }

    func deleteSensitiveData(identifier: String) {
        guard !identifier.isEmpty else { return }
        secure.deleteToken(identifier: identifier)
        secure.deleteSpcCredentials(identifier: identifier)
        secure.deleteSpcVariants(identifier: identifier)
        legacy.deleteToken(macAddress: identifier)
        legacy.deleteSpcCredentials(identifier: identifier)
        legacy.deleteSpcVariants(identifier: identifier)
    }
}
