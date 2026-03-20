import Foundation
import Testing
@testable import Samsung_Remote_TV

@Suite("TVRepositoryImpl")
struct TVRepositoryImplTests {
    @Test("Save TV persists to UserDefaults and can be retrieved")
    func saveAndLoad() throws {
        let defaults = UserDefaults(suiteName: "TVRepositoryImplTests")!
        defaults.removePersistentDomain(forName: "TVRepositoryImplTests")

        let storage = TVUserDefaultsStorage(userDefaults: defaults)
        let tv = SamsungTV(name: "TV", ipAddress: "1.1.1.1", macAddress: "AA", model: "Q", type: .tizen)

        try storage.saveTVs([tv])
        let loaded = try storage.loadSavedTVs()

        #expect(loaded.count == 1)
    }

    @Test("Delete TV removes it from UserDefaults correctly")
    func deleteTV() throws {
        let defaults = UserDefaults(suiteName: "TVRepositoryImplTests.delete")!
        defaults.removePersistentDomain(forName: "TVRepositoryImplTests.delete")
        let storage = TVUserDefaultsStorage(userDefaults: defaults)

        let tv = SamsungTV(name: "TV", ipAddress: "1.1.1.1", macAddress: "AA", model: "Q", type: .tizen)
        try storage.saveTVs([tv])
        try storage.saveTVs([])

        #expect((try storage.loadSavedTVs()).isEmpty)
    }

    @Test("Discovered TVs are merged with saved TVs without duplicates")
    func mergeNoDuplicates() {
        let a = SamsungTV(name: "TV A", ipAddress: "1", macAddress: "AA", model: "Q", type: .tizen)
        let b = SamsungTV(name: "TV B", ipAddress: "2", macAddress: "AA", model: "Q", type: .tizen)
        let merged = Dictionary(grouping: [a, b], by: { $0.macAddress }).compactMap { $0.value.first }
        #expect(merged.count == 1)
    }

    @Test("ForgetPairing clears token, SPC credentials, and SPC variants but keeps saved TV")
    func forgetPairingClearsPairingArtifacts() async throws {
        let defaults = UserDefaults(suiteName: "TVRepositoryImplTests.forgetPairing")!
        defaults.removePersistentDomain(forName: "TVRepositoryImplTests.forgetPairing")
        let storage = TVUserDefaultsStorage(userDefaults: defaults)
        let secureStorage = TVSecureStorage(service: "TVRepositoryImplTests.forgetPairing.secure")
        let repository = makeRepository(storage: storage, secureStorage: secureStorage)
        let tv = SamsungTV(name: "TV", ipAddress: "192.168.1.50", macAddress: "AA:BB:CC:DD:EE:FF", model: "Q", type: .encrypted)

        try repository.saveTV(tv)
        storage.saveToken("token123", macAddress: tv.macAddress)
        try storage.saveSpcCredentials(.init(ctxUpperHex: "ABCD", sessionId: 5), identifier: tv.macAddress)
        try storage.saveSpcVariants(.init(step0: "s0", step1: "s1"), identifier: tv.macAddress)

        try await repository.forgetPairing(for: tv)

        #expect(storage.loadToken(macAddress: tv.macAddress) == nil)
        #expect(storage.loadSpcCredentials(identifier: tv.macAddress) == nil)
        #expect(storage.loadSpcVariants(identifier: tv.macAddress) == nil)
        #expect(secureStorage.loadToken(identifier: tv.macAddress) == nil)
        #expect(secureStorage.loadSpcCredentials(identifier: tv.macAddress) == nil)
        #expect(secureStorage.loadSpcVariants(identifier: tv.macAddress) == nil)
        #expect(try repository.getSavedTVs().count == 1)
    }

    @Test("RemoveDevice clears pairing artifacts and deletes saved TV entry")
    func removeDeviceClearsArtifactsAndDeletesSavedTV() async throws {
        let defaults = UserDefaults(suiteName: "TVRepositoryImplTests.removeDevice")!
        defaults.removePersistentDomain(forName: "TVRepositoryImplTests.removeDevice")
        let storage = TVUserDefaultsStorage(userDefaults: defaults)
        let secureStorage = TVSecureStorage(service: "TVRepositoryImplTests.removeDevice.secure")
        let repository = makeRepository(storage: storage, secureStorage: secureStorage)
        let tv = SamsungTV(name: "TV", ipAddress: "192.168.1.50", macAddress: "AA:BB:CC:DD:EE:FF", model: "Q", type: .encrypted)

        try repository.saveTV(tv)
        storage.saveToken("token123", macAddress: tv.macAddress)
        try storage.saveSpcCredentials(.init(ctxUpperHex: "ABCD", sessionId: 5), identifier: tv.macAddress)
        try storage.saveSpcVariants(.init(step0: "s0", step1: "s1"), identifier: tv.macAddress)

        try await repository.removeDevice(tv)

        #expect(storage.loadToken(macAddress: tv.macAddress) == nil)
        #expect(storage.loadSpcCredentials(identifier: tv.macAddress) == nil)
        #expect(storage.loadSpcVariants(identifier: tv.macAddress) == nil)
        #expect(secureStorage.loadToken(identifier: tv.macAddress) == nil)
        #expect(secureStorage.loadSpcCredentials(identifier: tv.macAddress) == nil)
        #expect(secureStorage.loadSpcVariants(identifier: tv.macAddress) == nil)
        #expect(try repository.getSavedTVs().isEmpty)
    }

    @Test("Sensitive storage migrates legacy values on read")
    func sensitiveStorageMigratesLegacyValues() throws {
        let defaults = UserDefaults(suiteName: "TVRepositoryImplTests.migration")!
        defaults.removePersistentDomain(forName: "TVRepositoryImplTests.migration")
        let legacy = TVUserDefaultsStorage(userDefaults: defaults)
        let secure = TVSecureStorage(service: "TVRepositoryImplTests.migration.secure")
        let sensitive = TVSensitiveStorage(legacy: legacy, secure: secure)
        let identifier = "AA:BB:CC:DD:EE:FF"
        legacy.saveToken("legacyToken", macAddress: identifier)
        try legacy.saveSpcCredentials(.init(ctxUpperHex: "ABCD", sessionId: 1), identifier: identifier)
        try legacy.saveSpcVariants(.init(step0: "v0", step1: "v1"), identifier: identifier)

        let token = sensitive.loadToken(identifier: identifier)
        let creds = sensitive.loadSpcCredentials(identifier: identifier)
        let variants = sensitive.loadSpcVariants(identifier: identifier)

        #expect(token == "legacyToken")
        #expect(creds?.sessionId == 1)
        #expect(variants?.step0 == "v0")
        #expect(legacy.loadToken(macAddress: identifier) == nil)
        #expect(legacy.loadSpcCredentials(identifier: identifier) == nil)
        #expect(legacy.loadSpcVariants(identifier: identifier) == nil)
        #expect(secure.loadToken(identifier: identifier) == "legacyToken")
        #expect(secure.loadSpcCredentials(identifier: identifier)?.sessionId == 1)
        #expect(secure.loadSpcVariants(identifier: identifier)?.step0 == "v0")
    }

    private func makeRepository(storage: TVUserDefaultsStorage, secureStorage: TVSecureStorage) -> TVRepositoryImpl {
        let restClient = SamsungTVRestClient()
        return TVRepositoryImpl(
            restClient: restClient,
            webSocketClient: SamsungTVWebSocketClient(),
            smartViewClient: SmartViewSDKClient(),
            spcWebSocketClient: SpcWebSocketClient(),
            spcHandshakeClient: SpcHandshakeClient(),
            legacyRemoteClient: SamsungLegacyRemoteClient(),
            storage: storage,
            secureStorage: secureStorage,
            ipRangeScanner: IPRangeScanner(restClient: restClient),
            bonjourDiscovery: BonjourDiscovery(restClient: restClient),
            ssdpDiscovery: SSDPDiscovery(restClient: restClient)
        )
    }
}
