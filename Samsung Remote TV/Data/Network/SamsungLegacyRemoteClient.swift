import Foundation
import Network

actor SamsungLegacyRemoteClient {
    private static let controlAppString = "iphone.iapp.samsung"
    private var connection: NWConnection?
    private var currentTV: SamsungTV?
    private var remoteName: String = "SamsungTVRemote"
    private var hasLoggedFirstKeyResult = false
    private var activePort: UInt16?

    func connect(to tv: SamsungTV, remoteName: String) -> AsyncStream<TVConnectionState> {
        AsyncStream { continuation in
            let task = Task {
                print("[TVDBG][TVDBG][LegacyRemote] connect start ip=\(tv.ipAddress) ports=[55000,55001,52235] model=\(tv.model) name=\(tv.name)")
                continuation.yield(.connecting)
                do {
                    try await self.open(tv: tv, remoteName: remoteName)
                    continuation.yield(.connected)
                } catch {
                    print("[TVDBG][LegacyRemote] connect failed ip=\(tv.ipAddress) error=\(error.localizedDescription)")
                    continuation.yield(.error(.connectionFailed(error.localizedDescription)))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func disconnect() {
        print("[TVDBG][LegacyRemote] disconnect")
        connection?.cancel()
        connection = nil
        currentTV = nil
        hasLoggedFirstKeyResult = false
        activePort = nil
    }

    func sendKey(_ key: RemoteKey) async throws {
        guard let tv = currentTV else {
            throw TVError.notConnected
        }

        do {
            if connection == nil {
                try await open(tv: tv, remoteName: remoteName)
            }

            let packet = Self.makeKeyPacket(key: key)
            if !hasLoggedFirstKeyResult {
                print("[TVDBG][LegacyRemote] first key packet key=\(key.rawValue) bytes=\(packet.count) port=\(activePort ?? 0)")
            }
            try await send(packet)

            if !hasLoggedFirstKeyResult {
                hasLoggedFirstKeyResult = true
                print("[TVDBG][LegacyRemote] first key send result=success")
            }
        } catch {
            if !hasLoggedFirstKeyResult {
                print("[TVDBG][LegacyRemote] first key send result=failure error=\(error.localizedDescription)")
            }
            disconnect()
            throw TVError.commandFailed(key, error.localizedDescription)
        }
    }

    private func open(tv: SamsungTV, remoteName: String) async throws {
        disconnect()

        self.currentTV = tv
        self.remoteName = remoteName
        self.hasLoggedFirstKeyResult = false

        let ports: [UInt16] = [55000, 55001, 52235]
        var lastError: Error = TVError.notConnected

        for port in ports {
            do {
                try await openOnPort(tv: tv, remoteName: remoteName, port: port)
                activePort = port
                print("[TVDBG][LegacyRemote] connected on port=\(port)")
                return
            } catch {
                lastError = error
                print("[TVDBG][LegacyRemote] port=\(port) failed error=\(error.localizedDescription)")
                connection?.cancel()
                connection = nil
            }
        }

        throw lastError
    }

    private func openOnPort(tv: SamsungTV, remoteName: String, port: UInt16) async throws {
        let host = NWEndpoint.Host(tv.ipAddress)
        let endpointPort = NWEndpoint.Port(rawValue: port)!
        let connection = NWConnection(host: host, port: endpointPort, using: .tcp)
        self.connection = connection

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    final class ResumeBox: @unchecked Sendable {
                        let lock = NSLock()
                        var resumed = false
                    }
                    let box = ResumeBox()

                    let resumeOnce: @Sendable (Result<Void, Error>) -> Void = { result in
                        box.lock.lock()
                        defer { box.lock.unlock() }
                        guard !box.resumed else { return }
                        box.resumed = true
                        switch result {
                        case .success:
                            continuation.resume(returning: ())
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }

                    connection.stateUpdateHandler = { state in
                        print("[TVDBG][LegacyRemote] state ip=\(tv.ipAddress):\(port) \(String(describing: state))")
                        switch state {
                        case .ready:
                            Task {
                                do {
                                    let handshake1 = Self.makeHandshakePacket(
                                        remoteName: remoteName
                                    )
                                    print("[TVDBG][LegacyRemote] handshake1 bytes=\(handshake1.count) port=\(port)")
                                    try await self.send(handshake1)

                                    // Some legacy TVs require the second auth message after initial hello.
                                    let handshake2 = Self.makeAuthPacket()
                                    print("[TVDBG][LegacyRemote] handshake2 bytes=\(handshake2.count) port=\(port)")
                                    try await self.send(handshake2)

                                    let response = try await self.receiveOnce(timeout: .seconds(2))
                                    if let response, Self.isAccessDenied(response) {
                                        throw TVError.pairingRejected
                                    }

                                    resumeOnce(.success(()))
                                } catch {
                                    resumeOnce(.failure(error))
                                }
                            }
                        case .failed(let error):
                            resumeOnce(.failure(error))
                        case .waiting(let error):
                            // ECONNREFUSED often appears here; fail fast so the next port can be tried.
                            resumeOnce(.failure(error))
                        case .cancelled:
                            resumeOnce(.failure(TVError.notConnected))
                        default:
                            break
                        }
                    }

                    connection.start(queue: .global())
                }
            }

            group.addTask {
                try await Task.sleep(for: .seconds(3))
                throw TVError.connectionFailed("Legacy port \(port) timed out.")
            }

            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func send(_ data: Data) async throws {
        guard let connection else {
            throw TVError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    private func receiveOnce(timeout: Duration) async throws -> Data? {
        guard let connection else { return nil }
        return try await withThrowingTaskGroup(of: Data?.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }
                        if isComplete, data == nil {
                            continuation.resume(returning: nil)
                            return
                        }
                        continuation.resume(returning: data)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }

            let value = try await group.next() ?? nil
            group.cancelAll()
            return value
        }
    }

    nonisolated private static func makeHandshakePacket(remoteName: String) -> Data {
        let description = "iOS Samsung Remote"
        let identifier = NetworkUtils.localIPAddress() ?? "iPhone"

        var payload = Data([0x64, 0x00])
        payload.append(serializeString(description))
        payload.append(serializeString(identifier))
        payload.append(serializeString(remoteName))
        return makePacket(
            appString: controlAppString,
            payload: payload
        )
    }

    nonisolated private static func makeAuthPacket() -> Data {
        let payload = Data([0xC8, 0x00])
        return makePacket(appString: controlAppString, payload: payload)
    }

    nonisolated private static func makeKeyPacket(key: RemoteKey) -> Data {
        var payload = Data([0x00, 0x00, 0x00])
        payload.append(serializeString(key.rawValue))
        return makePacket(appString: controlAppString, payload: payload)
    }

    nonisolated private static func makePacket(appString: String, payload: Data) -> Data {
        var packet = Data([0x00])
        packet.append(serializeData(Data(appString.utf8), raw: true))
        packet.append(serializeData(payload, raw: true))
        return packet
    }

    nonisolated private static func serializeString(_ value: String) -> Data {
        serializeData(Data(value.utf8), raw: false)
    }

    nonisolated private static func serializeData(_ value: Data, raw: Bool) -> Data {
        let payload: Data
        if raw {
            payload = value
        } else {
            payload = Data(value.base64EncodedString().utf8)
        }

        let length = UInt8(min(payload.count, 255))
        var data = Data()
        data.append(length)
        data.append(0x00)
        data.append(payload.prefix(Int(length)))
        return data
    }

    nonisolated private static func isAccessDenied(_ data: Data) -> Bool {
        data.starts(with: [0x65]) || data.range(of: Data([0x64, 0x00, 0x00, 0x00])) != nil
    }
}
