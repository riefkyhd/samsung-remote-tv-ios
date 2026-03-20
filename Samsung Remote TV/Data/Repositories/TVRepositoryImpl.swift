import Foundation
import Network

final class TVRepositoryImpl: TVRepository, @unchecked Sendable {
    private enum ActiveTransport {
        case webSocket
        case smartView
        case spc
        case legacy
    }

    private let restClient: SamsungTVRestClient
    private let webSocketClient: SamsungTVWebSocketClient
    private let smartViewClient: SmartViewSDKClient
    private let spcWebSocketClient: SpcWebSocketClient
    private let spcHandshakeClient: SpcHandshakeClient
    private let legacyRemoteClient: SamsungLegacyRemoteClient
    private let storage: TVUserDefaultsStorage
    private let ipRangeScanner: IPRangeScanner
    private let bonjourDiscovery: BonjourDiscovery
    private let ssdpDiscovery: SSDPDiscovery
    private var activeTransport: ActiveTransport = .webSocket
    private var transportConnected = false
    private var activeSpcCredentials: TVUserDefaultsStorage.SpcCredentials?
    private var spcPairingInProgress = false
    private var currentTV: SamsungTV?

    init(
        restClient: SamsungTVRestClient,
        webSocketClient: SamsungTVWebSocketClient,
        smartViewClient: SmartViewSDKClient,
        spcWebSocketClient: SpcWebSocketClient,
        spcHandshakeClient: SpcHandshakeClient,
        legacyRemoteClient: SamsungLegacyRemoteClient,
        storage: TVUserDefaultsStorage,
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
                currentTV = tv
                transportConnected = false
                let remoteName = storage.loadRemoteName()
                print("[TVDBG][Repo] connect start ip=\(tv.ipAddress) model=\(tv.model)")

                switch tv.protocolType {
                case .modern:
                    let wsConnected = await connectUsingWebSocket(
                        tv: tv,
                        remoteName: remoteName,
                        continuation: continuation
                    )

                    if !wsConnected {
                        print("[TVDBG][Repo] websocket not usable, fallback to legacy ip=\(tv.ipAddress)")
                        await webSocketClient.disconnect()
                        _ = await connectUsingLegacy(
                            tv: tv,
                            remoteName: remoteName,
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
                            continuation: continuation
                        )
                        if !wsConnected {
                            transportConnected = false
                            continuation.yield(.error(.connectionFailed("Encrypted TV websocket connection failed.")))
                        }
                    } else {
                        _ = await connectUsingStoredOrPairingSpc(
                            tv: tv,
                            remoteName: remoteName,
                            continuation: continuation
                        )
                    }

                case .legacy:
                    _ = await connectUsingLegacy(
                        tv: tv,
                        remoteName: remoteName,
                        continuation: continuation
                    )
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task {
                    // Keep SPC HTTP pairing session alive while waiting for PIN submission.
                    guard !self.spcPairingInProgress else { return }
                    await self.disconnect()
                }
            }
        }
    }

    func disconnect() async {
        spcPairingInProgress = false
        transportConnected = false
        await webSocketClient.disconnect()
        smartViewClient.disconnect()
        await legacyRemoteClient.disconnect()
        if activeTransport != .spc {
            await spcWebSocketClient.disconnect()
            activeSpcCredentials = nil
        }
    }

    func completeEncryptedPairing(pin: String, for tv: SamsungTV) async throws {
        guard tv.protocolType == .encrypted else { return }
        defer { spcPairingInProgress = false }

        let identifier = tokenIdentifier(for: tv)
        let outcome = try await spcHandshakeClient.completePairing(
            tv: tv,
            pin: pin,
            deviceID: storage.loadOrCreateSpcDeviceID(),
            preferredStep0: nil,
            preferredStep1: nil
        )

        try storage.saveSpcCredentials(outcome.credentials, identifier: identifier)
        print("[TVDBG][SPC] credentials saved CTX=\(outcome.credentials.ctxUpperHex.prefix(8))... sessionId=\(outcome.credentials.sessionId)")
    }

    func sendKey(_ key: RemoteKey, command: String) async throws {
        guard transportConnected else {
            throw TVError.notConnected
        }
        switch activeTransport {
        case .webSocket:
            try await webSocketClient.sendKey(key, command: command)
        case .smartView:
            try await smartViewClient.sendKey(key, command: command)
        case .spc:
            let creds: TVUserDefaultsStorage.SpcCredentials
            if let active = activeSpcCredentials {
                creds = active
            } else if let tv = currentTV,
                      let stored = storage.loadSpcCredentials(identifier: tokenIdentifier(for: tv)) {
                // Race fallback: restore active credentials from persisted SPC credentials.
                creds = stored
                activeSpcCredentials = stored
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
        guard transportConnected else {
            throw TVError.notConnected
        }
        switch activeTransport {
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

    func getInstalledApps(for tv: SamsungTV) async throws -> [TVApp] {
        _ = tv
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

    func forgetToken(for macAddress: String) throws {
        storage.deleteToken(macAddress: macAddress)
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
        continuation: AsyncStream<TVConnectionState>.Continuation
    ) async -> Bool {
        guard !spcPairingInProgress else {
            print("[TVDBG][WS] Skipping reconnect — SPC pairing in progress")
            return false
        }
        activeTransport = .webSocket
        let tokenKey = tokenIdentifier(for: tv)
        let token = storage.loadToken(macAddress: tokenKey)
        print("[TVDBG][Repo] try websocket ip=\(tv.ipAddress) token=\(token != nil)")
        await webSocketClient.setTokenHandler { [storage] newToken in
            Task { @MainActor in
                storage.saveToken(newToken, macAddress: tokenKey)
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
            continuation.yield(state)
            if case .connected = state {
                connected = true
                try? saveTV(tv)
                transportConnected = true
            }
            if case .error = state {
                hadError = true
                transportConnected = false
            }
            if case .disconnected = state {
                transportConnected = false
            }
        }
        return connected && !hadError
    }

    private func connectUsingLegacy(
        tv: SamsungTV,
        remoteName: String,
        continuation: AsyncStream<TVConnectionState>.Continuation,
        emitErrors: Bool = true
    ) async -> Bool {
        activeTransport = .legacy
        print("[TVDBG][Repo] try legacy ip=\(tv.ipAddress)")
        let stream = await legacyRemoteClient.connect(to: tv, remoteName: remoteName)
        var connected = false
        for await state in stream {
            if emitErrors || !matchesError(state) {
                continuation.yield(state)
            }
            if case .connected = state {
                connected = true
                try? saveTV(tv)
                transportConnected = true
            }
            if case .error = state {
                transportConnected = false
            }
            if case .disconnected = state {
                transportConnected = false
            }
        }
        print("[TVDBG][Repo] legacy result ip=\(tv.ipAddress) connected=\(connected)")
        return connected
    }

    private func connectUsingSpc(
        tv: SamsungTV,
        remoteName: String,
        credentials: TVUserDefaultsStorage.SpcCredentials,
        continuation: AsyncStream<TVConnectionState>.Continuation
    ) async -> Bool {
        activeTransport = .spc
        activeSpcCredentials = credentials
        print("[TVDBG][Repo] try spc ip=\(tv.ipAddress)")
        let stream = await spcWebSocketClient.connect(ipAddress: tv.ipAddress, remoteName: remoteName)
        var everConnected = false

        for await state in stream {
            continuation.yield(state)
            if case .connected = state {
                everConnected = true
                transportConnected = true
            }
            if case .error = state {
                transportConnected = false
            }
            if case .disconnected = state {
                transportConnected = false
            }
        }
        return everConnected
    }

    private func connectUsingSmartView(
        tv: SamsungTV,
        remoteName: String,
        continuation: AsyncStream<TVConnectionState>.Continuation
    ) async -> Bool {
        activeTransport = .smartView
        print("[TVDBG][Repo] try smartview ip=\(tv.ipAddress)")

        let stream = smartViewClient.connect(to: tv, remoteName: remoteName)

        var connected = false
        var hadError = false
        for await state in stream {
            // SmartView may emit transient errors; still forward stream states
            // and keep consuming until final disconnect.
            continuation.yield(state)
            if case .connected = state {
                connected = true
                transportConnected = true
                try? saveTV(tv)
            }
            if case .error = state {
                hadError = true
                transportConnected = false
            }
            if case .disconnected = state {
                transportConnected = false
            }
        }

        return connected && !hadError
    }

    private func connectUsingStoredOrPairingSpc(
        tv: SamsungTV,
        remoteName: String,
        continuation: AsyncStream<TVConnectionState>.Continuation
    ) async -> Bool {
        let identifier = tokenIdentifier(for: tv)
        if let credentials = storage.loadSpcCredentials(identifier: identifier) {
            let connected = await connectUsingSpc(
                tv: tv,
                remoteName: remoteName,
                credentials: credentials,
                continuation: continuation
            )
            if !connected {
                transportConnected = false
                storage.deleteSpcCredentials(identifier: identifier)
                continuation.yield(.error(.spcTokenExpired))
            }
            return connected
        }

        do {
            let deviceID = storage.loadOrCreateSpcDeviceID()
            spcPairingInProgress = true
            continuation.yield(.pairing(countdown: 30))
            try await spcHandshakeClient.startPairing(
                tv: tv,
                deviceID: deviceID,
                preferredStep0: nil,
                preferredStep1: nil
            )
            continuation.yield(.pinRequired(countdown: 60))
            return false
        } catch {
            spcPairingInProgress = false
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
