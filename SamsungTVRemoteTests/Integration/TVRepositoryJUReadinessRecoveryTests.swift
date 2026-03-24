import Foundation
import Testing
@testable import Samsung_Remote_TV

@Suite("TVRepository JU SPC readiness recovery")
@MainActor
struct TVRepositoryJUReadinessRecoveryTests {
    @Test("Stored JU SPC stale path does not auto-send command and falls through to fresh pairing")
    func storedSpcStaleFallsBackToFreshPairingWithoutAutoCommand() async throws {
        let defaults = UserDefaults(suiteName: "TVRepositoryJUReadinessRecoveryTests.stale")!
        defaults.removePersistentDomain(forName: "TVRepositoryJUReadinessRecoveryTests.stale")
        let storage = TVUserDefaultsStorage(userDefaults: defaults)
        let secureStorage = TVSecureStorage(service: "TVRepositoryJUReadinessRecoveryTests.stale.secure")

        let fakeSpcSocket = FakeSpcWebSocketTransport(emitTokenExpiredOnFirstSend: true)
        let fakeSpcHandshake = FakeSpcHandshakeTransport()
        let repository = makeRepository(
            storage: storage,
            secureStorage: secureStorage,
            spcWebSocketClient: fakeSpcSocket,
            spcHandshakeClient: fakeSpcHandshake
        )

        let tv = SamsungTV(
            name: "Living Room",
            ipAddress: "192.168.1.50",
            macAddress: "AA:BB:CC:DD:EE:FF",
            model: "UN55JU6400",
            type: .encrypted
        )
        let identifier = tv.macAddress

        // Seed stored pairing artifacts so connect uses stored SPC first.
        try storage.saveSpcCredentials(.init(ctxUpperHex: "ABCD", sessionId: 42), identifier: identifier)
        try storage.saveSpcVariants(.init(step0: "s0", step1: "s1"), identifier: identifier)
        storage.saveToken("legacy-token", macAddress: identifier)
        try secureStorage.saveSpcCredentials(.init(ctxUpperHex: "ABCD", sessionId: 42), identifier: identifier)
        try secureStorage.saveSpcVariants(.init(step0: "s0", step1: "s1"), identifier: identifier)
        try secureStorage.saveToken("secure-token", identifier: identifier)

        let stream = repository.connect(to: tv)
        var iterator = stream.makeAsyncIterator()

        let firstState = await iterator.next()
        #expect(firstState == .connected)
        #expect(await fakeSpcSocket.sendKeyCount() == 0) // no auto command on connect

        try await repository.sendKey(.KEY_VOLUP, command: "Click")

        let secondState = await iterator.next()
        let thirdState = await iterator.next()
        let fourthState = await iterator.next()

        #expect(secondState == .error(.spcTokenExpired)) // first command timeout/error path
        #expect(thirdState == .pairing(countdown: 30)) // same connect attempt falls into fresh pairing
        #expect(fourthState == .pinRequired(countdown: 60))

        #expect(await fakeSpcHandshake.startPairingCount() == 1)
        #expect(await fakeSpcSocket.connectCount() == 1)
        #expect(await fakeSpcSocket.sendKeyCount() == 1)

        // Stale SPC artifacts are cleared before fresh pairing.
        #expect(storage.loadToken(macAddress: identifier) == nil)
        #expect(storage.loadSpcCredentials(identifier: identifier) == nil)
        #expect(storage.loadSpcVariants(identifier: identifier) == nil)
        #expect(secureStorage.loadToken(identifier: identifier) == nil)
        #expect(secureStorage.loadSpcCredentials(identifier: identifier) == nil)
        #expect(secureStorage.loadSpcVariants(identifier: identifier) == nil)

        // No misleading ready state after stale recovery path.
        do {
            try await repository.sendKey(.KEY_VOLDOWN, command: "Click")
            Issue.record("Expected notConnected while recovery is in pairing state")
        } catch let error as TVError {
            #expect(error == .notConnected)
        }
    }

    private func makeRepository(
        storage: TVUserDefaultsStorage,
        secureStorage: TVSecureStorage,
        spcWebSocketClient: SpcWebSocketTransport,
        spcHandshakeClient: SpcHandshakeTransport
    ) -> TVRepositoryImpl {
        let restClient = SamsungTVRestClient()
        return TVRepositoryImpl(
            restClient: restClient,
            webSocketClient: SamsungTVWebSocketClient(),
            smartViewClient: SmartViewSDKClient(),
            spcWebSocketClient: spcWebSocketClient,
            spcHandshakeClient: spcHandshakeClient,
            legacyRemoteClient: SamsungLegacyRemoteClient(),
            storage: storage,
            secureStorage: secureStorage,
            ipRangeScanner: IPRangeScanner(restClient: restClient),
            bonjourDiscovery: BonjourDiscovery(restClient: restClient),
            ssdpDiscovery: SSDPDiscovery(restClient: restClient)
        )
    }
}

private actor FakeSpcWebSocketTransport: SpcWebSocketTransport {
    private var continuation: AsyncStream<TVConnectionState>.Continuation?
    private var _connectCount = 0
    private var _sendKeyCount = 0
    private let emitTokenExpiredOnFirstSend: Bool

    init(emitTokenExpiredOnFirstSend: Bool) {
        self.emitTokenExpiredOnFirstSend = emitTokenExpiredOnFirstSend
    }

    func connect(ipAddress: String, remoteName: String) async -> AsyncStream<TVConnectionState> {
        _ = ipAddress
        _ = remoteName
        _connectCount += 1
        return AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(.connected)
        }
    }

    func disconnect() async {
        continuation?.yield(.disconnected)
        continuation?.finish()
    }

    func sendKey(_ key: RemoteKey, command: String, ctxHex: String, sessionID: String) async throws {
        _ = key
        _ = command
        _ = ctxHex
        _ = sessionID
        _sendKeyCount += 1
        if emitTokenExpiredOnFirstSend && _sendKeyCount == 1 {
            continuation?.yield(.error(.spcTokenExpired))
            continuation?.finish()
        }
    }

    func connectCount() -> Int { _connectCount }
    func sendKeyCount() -> Int { _sendKeyCount }
}

private actor FakeSpcHandshakeTransport: SpcHandshakeTransport {
    private var _startPairingCount = 0

    func startPairing(
        tv: SamsungTV,
        deviceID: String,
        preferredStep0: String?,
        preferredStep1: String?
    ) async throws {
        _ = tv
        _ = deviceID
        _ = preferredStep0
        _ = preferredStep1
        _startPairingCount += 1
    }

    func completePairing(
        tv: SamsungTV,
        pin: String,
        deviceID: String,
        preferredStep0: String?,
        preferredStep1: String?
    ) async throws -> (
        credentials: TVUserDefaultsStorage.SpcCredentials,
        step0Variant: String,
        step1Variant: String
    ) {
        _ = tv
        _ = pin
        _ = deviceID
        _ = preferredStep0
        _ = preferredStep1
        return (
            credentials: .init(ctxUpperHex: "ABCD", sessionId: 1),
            step0Variant: "CONFIRMED",
            step1Variant: "CONFIRMED"
        )
    }

    func cancelPairing(tv: SamsungTV) async {
        _ = tv
    }

    func startPairingCount() -> Int { _startPairingCount }
}
