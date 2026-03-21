import Foundation
import Network

final class TVRepositoryImpl: TVRepository, @unchecked Sendable {
    enum ActiveTransport: Sendable {
        case webSocket
        case smartView
        case spc
        case legacy
    }

    enum ConnectionLifecycleState: Sendable {
        case idle
        case connecting
        case pairing
        case pinRequired
        case connected
    }

    actor ConnectionCoordinator {
        struct SendSnapshot: Sendable {
            let isConnected: Bool
            let activeTransport: ActiveTransport
            let activeSpcCredentials: TVUserDefaultsStorage.SpcCredentials?
            let currentTV: SamsungTV?
        }

        struct DisconnectSnapshot: Sendable {
            let activeTransport: ActiveTransport
        }

        private(set) var lifecycleState: ConnectionLifecycleState = .idle
        private var sessionID: Int = 0
        private var activeTransport: ActiveTransport = .webSocket
        private var transportConnected = false
        private var activeSpcCredentials: TVUserDefaultsStorage.SpcCredentials?
        private var spcPairingInProgress = false
        private var currentTV: SamsungTV?

        func beginConnect(tv: SamsungTV) -> Int {
            sessionID += 1
            currentTV = tv
            transportConnected = false
            activeSpcCredentials = nil
            spcPairingInProgress = false
            lifecycleState = .connecting
            return sessionID
        }

        func isCurrentSession(_ id: Int) -> Bool {
            id == sessionID
        }

        func setActiveTransport(_ transport: ActiveTransport, session: Int) {
            guard isCurrentSession(session) else { return }
            activeTransport = transport
        }

        func markConnected(session: Int) {
            guard isCurrentSession(session) else { return }
            transportConnected = true
            lifecycleState = .connected
        }

        func markDisconnected(session: Int) {
            guard isCurrentSession(session) else { return }
            transportConnected = false
            switch lifecycleState {
            case .pairing, .pinRequired:
                break
            default:
                lifecycleState = .idle
            }
        }

        func markPairingInProgress(session: Int) {
            guard isCurrentSession(session) else { return }
            spcPairingInProgress = true
            lifecycleState = .pairing
        }

        func markPinRequired(session: Int) {
            guard isCurrentSession(session) else { return }
            lifecycleState = .pinRequired
        }

        func clearPairingInProgress(session: Int) {
            guard isCurrentSession(session) else { return }
            spcPairingInProgress = false
            if !transportConnected {
                lifecycleState = .idle
            }
        }

        func shouldDisconnectOnConnectTermination(session: Int) -> Bool {
            guard isCurrentSession(session) else { return false }
            return !spcPairingInProgress
        }

        func setActiveSpcCredentials(_ credentials: TVUserDefaultsStorage.SpcCredentials?, session: Int) {
            guard isCurrentSession(session) else { return }
            activeSpcCredentials = credentials
        }

        func currentSessionID() -> Int {
            sessionID
        }

        func sendSnapshot() -> SendSnapshot {
            SendSnapshot(
                isConnected: transportConnected,
                activeTransport: activeTransport,
                activeSpcCredentials: activeSpcCredentials,
                currentTV: currentTV
            )
        }

        func invalidateForDisconnect() -> DisconnectSnapshot {
            sessionID += 1
            let snapshot = DisconnectSnapshot(activeTransport: activeTransport)
            transportConnected = false
            activeSpcCredentials = nil
            spcPairingInProgress = false
            lifecycleState = .idle
            return snapshot
        }

        func isCurrentTV(_ tv: SamsungTV) -> Bool {
            guard let currentTV else { return false }
            if currentTV.id == tv.id { return true }
            if !tv.macAddress.isEmpty && currentTV.macAddress.caseInsensitiveCompare(tv.macAddress) == .orderedSame {
                return true
            }
            return currentTV.ipAddress == tv.ipAddress
        }
    }

    private let restClient: SamsungTVRestClient
    private let webSocketClient: SamsungTVWebSocketClient
    private let smartViewClient: SmartViewSDKClient
    private let spcWebSocketClient: SpcWebSocketClient
    private let spcHandshakeClient: SpcHandshakeClient
    private let legacyRemoteClient: SamsungLegacyRemoteClient
    private let storage: TVUserDefaultsStorage
    private let sensitiveStorage: TVSensitiveStorage
    private let ipRangeScanner: IPRangeScanner
    private let bonjourDiscovery: BonjourDiscovery
    private let ssdpDiscovery: SSDPDiscovery
    private let connectionCoordinator = ConnectionCoordinator()

    init(
        restClient: SamsungTVRestClient,
        webSocketClient: SamsungTVWebSocketClient,
        smartViewClient: SmartViewSDKClient,
        spcWebSocketClient: SpcWebSocketClient,
        spcHandshakeClient: SpcHandshakeClient,
        legacyRemoteClient: SamsungLegacyRemoteClient,
        storage: TVUserDefaultsStorage,
        secureStorage: TVSecureStorage,
        ipRangeScanner: IPRangeScanner,
        bonjourDiscovery: BonjourDiscovery,
        ssdpDiscovery: SSDPDiscovery
    ) {
        self.restClient = restClient
        self.webSocketClient = webSocketClient
        self.smartViewClient = smartViewClient
        self.spcWebSocketClient = spcWebSocketClient
        self.spcHandshakeClient = spcHandshakeClient
        self.legacyRemoteClient = legacyRemoteClient
        self.storage = storage
        self.sensitiveStorage = TVSensitiveStorage(legacy: storage, secure: secureStorage)
        self.ipRangeScanner = ipRangeScanner
        self.bonjourDiscovery = bonjourDiscovery
        self.ssdpDiscovery = ssdpDiscovery
    }

    func discoverTVs() -> AsyncStream<SamsungTV> {
        AsyncStream { continuation in
            let task = Task {
                guard await NetworkUtils.isOnWiFi() else {
                    continuation.finish()
                    return
                }

                let dedup = DiscoveredMACActor()
                if smartViewClient.isSDKAvailable {
                    // Warm SmartView service cache by IP, but do not inject SmartView-only
                    // discovery results into the UI list. Those entries can misclassify
                    // modern TVs as encrypted and route them to the wrong transport.
                    smartViewClient.startDiscovery { _ in }
                }
                let merged = AsyncStream.merge(
                    ipRangeScanner.discover(),
                    bonjourDiscovery.discover(),
                    ssdpDiscovery.discover()
                )

                for await tv in merged {
                    if await dedup.insertIfNeeded(mac: tv.macAddress, ipAddress: tv.ipAddress) {
                        continuation.yield(tv)
                    }
                }
                continuation.finish()
                self.smartViewClient.stopDiscovery()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func scanTV(at ipAddress: String) async throws -> SamsungTV {
        guard await NetworkUtils.isOnWiFi() else {
            throw TVError.notOnWifi
        }
        return try await restClient.fetchTVInfo(ipAddress: ipAddress)
    }

    func connect(to tv: SamsungTV) -> AsyncStream<TVConnectionState> {
        AsyncStream { continuation in
            let task = Task {
                let sessionID = await connectionCoordinator.beginConnect(tv: tv)
                let remoteName = storage.loadRemoteName()
                print("[TVDBG][Repo] connect start ip=\(tv.ipAddress) model=\(tv.model)")

                switch tv.protocolType {
                case .modern:
                    let wsConnected = await connectUsingWebSocket(
                        tv: tv,
                        remoteName: remoteName,
                        sessionID: sessionID,
                        continuation: continuation
                    )

                    if !wsConnected {
                        print("[TVDBG][Repo] websocket not usable, fallback to legacy ip=\(tv.ipAddress)")
                        await webSocketClient.disconnect()
                        _ = await connectUsingLegacy(
                            tv: tv,
                            remoteName: remoteName,
                            sessionID: sessionID,
                            continuation: continuation
                        )
                    } else {
                        print("[TVDBG][Repo] websocket selected ip=\(tv.ipAddress)")
                    }

                case .encrypted:
                    if !isLikelyLegacyEncrypted(tv) {
                        // Newer encrypted TVs should stay on websocket transport.
                        let wsConnected = await connectUsingWebSocket(
                            tv: tv,
                            remoteName: remoteName,
                            sessionID: sessionID,
                            continuation: continuation
                        )
                        if !wsConnected {
                            await connectionCoordinator.markDisconnected(session: sessionID)
                            continuation.yield(.error(.connectionFailed("Encrypted TV websocket connection failed.")))
                        }
                    } else {
                        _ = await connectUsingStoredOrPairingSpc(
                            tv: tv,
                            remoteName: remoteName,
                            sessionID: sessionID,
                            continuation: continuation
                        )
                    }

                case .legacy:
                    _ = await connectUsingLegacy(
                        tv: tv,
                        remoteName: remoteName,
                        sessionID: sessionID,
                        continuation: continuation
                    )
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task {
                    // Keep SPC HTTP pairing session alive while waiting for PIN submission.
                    let sessionID = await self.connectionCoordinator.currentSessionID()
                    let shouldDisconnect = await self.connectionCoordinator.shouldDisconnectOnConnectTermination(
                        session: sessionID
                    )
                    guard shouldDisconnect else { return }
                    await self.disconnect()
                }
            }
        }
    }

    func disconnect() async {
        let disconnectSnapshot = await connectionCoordinator.invalidateForDisconnect()
        await webSocketClient.disconnect()
        smartViewClient.disconnect()
        await legacyRemoteClient.disconnect()
        if disconnectSnapshot.activeTransport != .spc {
            await spcWebSocketClient.disconnect()
        }
    }

    func completeEncryptedPairing(pin: String, for tv: SamsungTV) async throws {
        guard tv.protocolType == .encrypted else { return }
        let sessionID = await connectionCoordinator.currentSessionID()
        defer {
            Task {
                await self.connectionCoordinator.clearPairingInProgress(session: sessionID)
            }
        }

        let identifier = tokenIdentifier(for: tv)
        let variants = sensitiveStorage.loadSpcVariants(identifier: identifier)
        let outcome = try await spcHandshakeClient.completePairing(
            tv: tv,
            pin: pin,
            deviceID: storage.loadOrCreateSpcDeviceID(),
            preferredStep0: variants?.step0,
            preferredStep1: variants?.step1
        )

        sensitiveStorage.saveSpcCredentials(outcome.credentials, identifier: identifier)
        sensitiveStorage.saveSpcVariants(
            .init(step0: outcome.step0Variant, step1: outcome.step1Variant),
            identifier: identifier
        )
        print("[TVDBG][SPC] credentials saved CTX=\(outcome.credentials.ctxUpperHex.prefix(8))... sessionId=\(outcome.credentials.sessionId)")
    }

    func sendKey(_ key: RemoteKey, command: String) async throws {
        let snapshot = await connectionCoordinator.sendSnapshot()
        guard snapshot.isConnected else {
            throw TVError.notConnected
        }
        switch snapshot.activeTransport {
        case .webSocket:
            try await webSocketClient.sendKey(key, command: command)
        case .smartView:
            try await smartViewClient.sendKey(key, command: command)
        case .spc:
            let creds: TVUserDefaultsStorage.SpcCredentials
            if let active = snapshot.activeSpcCredentials {
                creds = active
            } else if let tv = snapshot.currentTV,
                      let stored = sensitiveStorage.loadSpcCredentials(identifier: tokenIdentifier(for: tv)) {
                // Race fallback: restore active credentials from persisted SPC credentials.
                creds = stored
                await connectionCoordinator.setActiveSpcCredentials(
                    stored,
                    session: await connectionCoordinator.currentSessionID()
                )
            } else {
                throw TVError.spcTokenExpired
            }
            try await spcWebSocketClient.sendKey(
                key,
                command: command,
                ctxHex: creds.ctxUpperHex,
                sessionID: String(creds.sessionId)
            )
        case .legacy:
            guard command == "Click" else { return }
            try await legacyRemoteClient.sendKey(key)
        }
    }

    func launchApp(appId: String) async throws {
        let snapshot = await connectionCoordinator.sendSnapshot()
        guard snapshot.isConnected else {
            throw TVError.notConnected
        }
        switch snapshot.activeTransport {
        case .webSocket:
            try await webSocketClient.launchApp(appId: appId)
        case .smartView:
            throw TVError.appLaunchFailed
        case .spc:
            throw TVError.appLaunchFailed
        case .legacy:
            throw TVError.appLaunchFailed
        }
    }

    func wakeOnLan(macAddress: String) async throws {
        let normalized = macAddress.replacingOccurrences(of: "-", with: ":")
        let regex = /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/
        guard normalized.wholeMatch(of: regex) != nil else {
            throw TVError.invalidMacAddress
        }

        let bytes = normalized.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6 else {
            throw TVError.invalidMacAddress
        }

        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: bytes)
        }

        try await sendWakePacket(data: packet, port: 9)
        try await sendWakePacket(data: packet, port: 7)
    }

    func getQuickLaunchApps(for tv: SamsungTV) async throws -> [TVApp] {
        _ = tv
        // Curated cross-model shortcuts for v1. This is not installed-app enumeration.
        return [
            TVApp(id: "11101200001", name: "Netflix", iconURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/0/08/Netflix_2015_logo.svg")),
            TVApp(id: "3201512006963", name: "YouTube", iconURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/b/b8/YouTube_Logo_2017.svg")),
            TVApp(id: "3201601007250", name: "Prime Video", iconURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/f/f1/Prime_Video.png")),
            TVApp(id: "3201907018807", name: "Disney+", iconURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/3/3e/Disney%2B_logo.svg"))
        ]
    }

    func getSavedTVs() throws -> [SamsungTV] {
        try storage.loadSavedTVs()
    }

    func saveTV(_ tv: SamsungTV) throws {
        var tvs = try storage.loadSavedTVs()
        if let index = tvs.firstIndex(where: { $0.macAddress.caseInsensitiveCompare(tv.macAddress) == .orderedSame || $0.id == tv.id }) {
            tvs[index] = tv
        } else {
            tvs.append(tv)
        }
        try storage.saveTVs(tvs)
    }

    func deleteTV(_ tv: SamsungTV) throws {
        var tvs = try storage.loadSavedTVs()
        tvs.removeAll { $0.id == tv.id }
        try storage.saveTVs(tvs)
    }

    func renameTV(id: UUID, name: String) throws {
        var tvs = try storage.loadSavedTVs()
        guard let index = tvs.firstIndex(where: { $0.id == id }) else { return }
        tvs[index].name = name
        try storage.saveTVs(tvs)
    }

    func forgetPairing(for tv: SamsungTV) async throws {
        await clearPairingArtifacts(for: tv)
        if await connectionCoordinator.isCurrentTV(tv) {
            await disconnect()
        }
    }

    func removeDevice(_ tv: SamsungTV) async throws {
        try await forgetPairing(for: tv)
        try deleteTV(tv)
    }

    func getRemoteName() -> String {
        storage.loadRemoteName()
    }

    func setRemoteName(_ name: String) throws {
        storage.saveRemoteName(name)
    }

    private func sendWakePacket(data: Data, port: UInt16) async throws {
        let endpointPort = NWEndpoint.Port(rawValue: port)!
        let connection = NWConnection(host: "255.255.255.255", port: endpointPort, using: .udp)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false

            func resumeOnce(_ result: Result<Void, Error>) {
                guard !resumed else { return }
                resumed = true
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: data, completion: .contentProcessed { error in
                        connection.cancel()
                        if let error {
                            resumeOnce(.failure(error))
                        } else {
                            resumeOnce(.success(()))
                        }
                    })
                case .failed(let error):
                    connection.cancel()
                    resumeOnce(.failure(error))
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    private func connectUsingWebSocket(
        tv: SamsungTV,
        remoteName: String,
        sessionID: Int,
        continuation: AsyncStream<TVConnectionState>.Continuation
    ) async -> Bool {
        guard await connectionCoordinator.isCurrentSession(sessionID) else {
            return false
        }
        let shouldSkip = !(await connectionCoordinator.shouldDisconnectOnConnectTermination(session: sessionID))
        guard !shouldSkip else {
            print("[TVDBG][WS] Skipping reconnect — SPC pairing in progress")
            return false
        }
        await connectionCoordinator.setActiveTransport(.webSocket, session: sessionID)
        guard await isTVReachable(ip: tv.ipAddress) else {
            print("[TVDBG][Repo] tv not reachable ip=\(tv.ipAddress) skip websocket")
            return false
        }
        let tokenKey = tokenIdentifier(for: tv)
        let token = sensitiveStorage.loadToken(identifier: tokenKey)
        print("[TVDBG][Repo] try websocket ip=\(tv.ipAddress) token=\(token != nil)")
        await webSocketClient.setTokenHandler { [sensitiveStorage] newToken in
            Task { @MainActor in
                sensitiveStorage.saveToken(newToken, identifier: tokenKey)
            }
        }

        let stream = await webSocketClient.connect(
            ipAddress: tv.ipAddress,
            token: token,
            remoteName: remoteName
        )

        var connected = false
        var hadError = false
        for await state in stream {
            guard await connectionCoordinator.isCurrentSession(sessionID) else {
                break
            }
            continuation.yield(state)
            if case .connected = state {
                connected = true
                try? saveTV(tv)
                await connectionCoordinator.markConnected(session: sessionID)
            }
            if case .error = state {
                hadError = true
                await connectionCoordinator.markDisconnected(session: sessionID)
            }
            if case .disconnected = state {
                await connectionCoordinator.markDisconnected(session: sessionID)
            }
        }
        return connected && !hadError
    }

    private func isTVReachable(ip: String) async -> Bool {
        guard let url = URL(string: "http://\(ip):8001/api/v2/") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                return (200..<500).contains(http.statusCode)
            }
            return true
        } catch {
            return false
        }
    }

    private func connectUsingLegacy(
        tv: SamsungTV,
        remoteName: String,
        sessionID: Int,
        continuation: AsyncStream<TVConnectionState>.Continuation,
        emitErrors: Bool = true
    ) async -> Bool {
        await connectionCoordinator.setActiveTransport(.legacy, session: sessionID)
        print("[TVDBG][Repo] try legacy ip=\(tv.ipAddress)")
        let stream = await legacyRemoteClient.connect(to: tv, remoteName: remoteName)
        var connected = false
        for await state in stream {
            guard await connectionCoordinator.isCurrentSession(sessionID) else {
                break
            }
            if emitErrors || !matchesError(state) {
                continuation.yield(state)
            }
            if case .connected = state {
                connected = true
                try? saveTV(tv)
                await connectionCoordinator.markConnected(session: sessionID)
            }
            if case .error = state {
                await connectionCoordinator.markDisconnected(session: sessionID)
            }
            if case .disconnected = state {
                await connectionCoordinator.markDisconnected(session: sessionID)
            }
        }
        print("[TVDBG][Repo] legacy result ip=\(tv.ipAddress) connected=\(connected)")
        return connected
    }

    private func connectUsingSpc(
        tv: SamsungTV,
        remoteName: String,
        credentials: TVUserDefaultsStorage.SpcCredentials,
        sessionID: Int,
        continuation: AsyncStream<TVConnectionState>.Continuation
    ) async -> Bool {
        await connectionCoordinator.setActiveTransport(.spc, session: sessionID)
        await connectionCoordinator.setActiveSpcCredentials(credentials, session: sessionID)
        print("[TVDBG][Repo] try spc ip=\(tv.ipAddress)")
        let stream = await spcWebSocketClient.connect(ipAddress: tv.ipAddress, remoteName: remoteName)
        var everConnected = false

        for await state in stream {
            guard await connectionCoordinator.isCurrentSession(sessionID) else {
                break
            }
            continuation.yield(state)
            if case .connected = state {
                everConnected = true
                await connectionCoordinator.markConnected(session: sessionID)
                try? saveTV(tv)
            }
            if case .error = state {
                await connectionCoordinator.markDisconnected(session: sessionID)
            }
            if case .disconnected = state {
                await connectionCoordinator.markDisconnected(session: sessionID)
            }
        }
        return everConnected
    }

    private func connectUsingSmartView(
        tv: SamsungTV,
        remoteName: String,
        sessionID: Int,
        continuation: AsyncStream<TVConnectionState>.Continuation
    ) async -> Bool {
        await connectionCoordinator.setActiveTransport(.smartView, session: sessionID)
        print("[TVDBG][Repo] try smartview ip=\(tv.ipAddress)")

        let stream = smartViewClient.connect(to: tv, remoteName: remoteName)

        var connected = false
        var hadError = false
        for await state in stream {
            guard await connectionCoordinator.isCurrentSession(sessionID) else {
                break
            }
            // SmartView may emit transient errors; still forward stream states
            // and keep consuming until final disconnect.
            continuation.yield(state)
            if case .connected = state {
                connected = true
                await connectionCoordinator.markConnected(session: sessionID)
                try? saveTV(tv)
            }
            if case .error = state {
                hadError = true
                await connectionCoordinator.markDisconnected(session: sessionID)
            }
            if case .disconnected = state {
                await connectionCoordinator.markDisconnected(session: sessionID)
            }
        }

        return connected && !hadError
    }

    private func connectUsingStoredOrPairingSpc(
        tv: SamsungTV,
        remoteName: String,
        sessionID: Int,
        continuation: AsyncStream<TVConnectionState>.Continuation
    ) async -> Bool {
        let identifier = tokenIdentifier(for: tv)
        if let credentials = sensitiveStorage.loadSpcCredentials(identifier: identifier) {
            let connected = await connectUsingSpc(
                tv: tv,
                remoteName: remoteName,
                credentials: credentials,
                sessionID: sessionID,
                continuation: continuation
            )
            if connected {
                return true
            }

            // Stored SPC credentials are stale. Remove them and continue directly
            // into fresh PIN pairing in this same connect attempt.
            await connectionCoordinator.markDisconnected(session: sessionID)
            await connectionCoordinator.setActiveSpcCredentials(nil, session: sessionID)
            sensitiveStorage.deleteSensitiveData(identifier: identifier)
        }

        do {
            let deviceID = storage.loadOrCreateSpcDeviceID()
            let variants = sensitiveStorage.loadSpcVariants(identifier: identifier)
            await connectionCoordinator.markPairingInProgress(session: sessionID)
            continuation.yield(.pairing(countdown: 30))
            try await spcHandshakeClient.startPairing(
                tv: tv,
                deviceID: deviceID,
                preferredStep0: variants?.step0,
                preferredStep1: variants?.step1
            )
            await connectionCoordinator.markPinRequired(session: sessionID)
            continuation.yield(.pinRequired(countdown: 60))
            return false
        } catch {
            await connectionCoordinator.clearPairingInProgress(session: sessionID)
            if let tvError = error as? TVError {
                continuation.yield(.error(tvError))
            } else {
                continuation.yield(.error(.spcPairingFailed(error.localizedDescription)))
            }
            return false
        }
    }

    private func matchesError(_ state: TVConnectionState) -> Bool {
        if case .error = state { return true }
        return false
    }

    private func tokenIdentifier(for tv: SamsungTV) -> String {
        if !tv.macAddress.isEmpty {
            return tv.macAddress
        }
        return "ip_\(tv.ipAddress)"
    }

    private func clearPairingArtifacts(for tv: SamsungTV) async {
        var identifiers = Set<String>()
        identifiers.insert(tokenIdentifier(for: tv))
        identifiers.insert("ip_\(tv.ipAddress)")
        if !tv.macAddress.isEmpty {
            identifiers.insert(tv.macAddress)
        }

        for identifier in identifiers where !identifier.isEmpty {
            sensitiveStorage.deleteSensitiveData(identifier: identifier)
        }
        await connectionCoordinator.setActiveSpcCredentials(
            nil,
            session: await connectionCoordinator.currentSessionID()
        )
        await connectionCoordinator.clearPairingInProgress(
            session: await connectionCoordinator.currentSessionID()
        )
    }

    private func isLikelyLegacyEncrypted(_ tv: SamsungTV) -> Bool {
        let model = tv.model.uppercased()
        // 2014/2015 Samsung encrypted families (H/J) typically include "H" or "JU".
        // Exclude modern Lifestyle models such as LS* (M7) that should use websocket.
        if model.contains("LS") || model.contains("QN") {
            return false
        }
        if model.contains("JU") || model.contains("J") || model.contains("H") {
            return true
        }
        return false
    }
}
