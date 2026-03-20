import Foundation

final class SamsungTVSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        guard SamsungTVSessionDelegate.isLocalHost(host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    private static func isLocalHost(_ host: String) -> Bool {
        if host.hasPrefix("192.168.") || host.hasPrefix("10.") || host.hasPrefix("127.") {
            return true
        }
        if host.hasPrefix("172."),
           let secondOctet = host.split(separator: ".").dropFirst().first,
           let second = Int(secondOctet),
           (16...31).contains(second) {
            return true
        }
        return false
    }
}

actor SamsungTVWebSocketClient {
    typealias TokenHandler = @Sendable (String) -> Void
    private enum KeyCommandMode {
        case remoteControl
        case emitKeypress
        case emitKeypressWithSession
        case emitRemoteControlWithSession
    }

    private let delegate = SamsungTVSessionDelegate()
    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var continuation: AsyncStream<TVConnectionState>.Continuation?
    private var tokenHandler: TokenHandler?
    private var isConnected = false
    private var keyCommandMode: KeyCommandMode = .remoteControl
    private var sessionIdentifier: String?

    func setTokenHandler(_ handler: @escaping TokenHandler) {
        tokenHandler = handler
    }

    func connect(ipAddress: String, token: String?, remoteName: String) -> AsyncStream<TVConnectionState> {
        AsyncStream { continuation in
            self.continuation = continuation
            self.keyCommandMode = .remoteControl
            self.sessionIdentifier = nil
            print("[TVDBG][WS] connect start ip=\(ipAddress) token=\(token != nil)")
            continuation.yield(.connecting)
            if token == nil {
                continuation.yield(.pairing(countdown: 30))
            }

            let task = Task {
                do {
                    try await self.openConnection(ipAddress: ipAddress, token: token, remoteName: remoteName)
                } catch {
                    print("[TVDBG][WS] connect failed ip=\(ipAddress) error=\(error.localizedDescription)")
                    continuation.yield(.error(.connectionFailed(error.localizedDescription)))
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task {
                    await self.disconnect()
                }
            }
        }
    }

    func disconnect() {
        print("[TVDBG][WS] disconnect")
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        continuation?.yield(.disconnected)
        continuation?.finish()
    }

    func sendKey(_ key: RemoteKey, command: String) async throws {
        guard isConnected, let webSocketTask else {
            throw TVError.notConnected
        }

        let payload = makeKeyPayload(key: key, command: command)
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let string = String(data: data, encoding: .utf8) else {
            throw TVError.invalidResponse
        }

        do {
            print("[TVDBG][WS] send key mode=\(String(describing: keyCommandMode)) key=\(key.rawValue)")
            try await webSocketTask.send(.string(string))
        } catch {
            throw TVError.commandFailed(key, error.localizedDescription)
        }
    }

    func launchApp(appId: String) async throws {
        guard isConnected, let webSocketTask else {
            throw TVError.notConnected
        }

        let payload: [String: Any] = [
            "method": "ms.channel.emit",
            "params": [
                "event": "ed.apps.launch",
                "to": "host",
                "data": [
                    "appId": appId,
                    "action_type": "DEEP_LINK"
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let string = String(data: data, encoding: .utf8) else {
            throw TVError.appLaunchFailed
        }

        do {
            try await webSocketTask.send(.string(string))
        } catch {
            throw TVError.appLaunchFailed
        }
    }

    private func openConnection(ipAddress: String, token: String?, remoteName: String) async throws {
        if try await attemptConnection(
            ipAddress: ipAddress,
            token: token,
            remoteName: remoteName,
            scheme: "wss",
            port: 8002
        ) {
            return
        }

        guard try await attemptConnection(
            ipAddress: ipAddress,
            token: nil,
            remoteName: remoteName,
            scheme: "ws",
            port: 8001
        ) else {
            throw TVError.connectionFailed("Failed SSL and plain WebSocket connection attempts.")
        }
    }

    private func attemptConnection(
        ipAddress: String,
        token: String?,
        remoteName: String,
        scheme: String,
        port: Int
    ) async throws -> Bool {
        let encodedName = Data(remoteName.utf8).base64EncodedString()
        var query = "name=\(encodedName)"
        if let token, !token.isEmpty {
            query += "&token=\(token)"
        }

        guard let url = URL(string: "\(scheme)://\(ipAddress):\(port)/api/v2/channels/samsung.remote.control?\(query)") else {
            return false
        }
        print("[TVDBG][WS] attempting \(scheme.uppercased()) \(ipAddress):\(port)")

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10

        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        task.resume()

        do {
            let message = try await receiveWithTimeout(task: task, timeout: 10)
            self.session = session
            self.webSocketTask = task
            handleMessage(message)
            startReceiveLoop(task: task)
            print("[TVDBG][WS] first message received \(scheme.uppercased()) \(ipAddress):\(port)")
            return true
        } catch {
            print("[TVDBG][WS] attempt failed \(scheme.uppercased()) \(ipAddress):\(port) error=\(error.localizedDescription)")
            task.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
            return false
        }
    }

    private func receiveWithTimeout(task: URLSessionWebSocketTask, timeout: Double) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask {
                try await task.receive()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw TVError.pairingTimeout
            }

            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    private func startReceiveLoop(task: URLSessionWebSocketTask) {
        receiveTask = Task {
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    handleMessage(message)
                } catch {
                    isConnected = false
                    continuation?.yield(.disconnected)
                    continuation?.finish()
                    break
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let string):
            text = string
        case .data(let data):
            text = String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            text = ""
        }

        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let event = json["event"] as? String {
            print("[TVDBG][WS] event=\(event)")

            if event == "ms.channel.connect" {
                isConnected = true
                continuation?.yield(.connected)
                updateSessionIdentifier(from: json)
                maybeStoreToken(from: json)
                return
            }

            if event == "ms.channel.clientConnect" {
                updateSessionIdentifier(from: json)
                maybeStoreToken(from: json)
                return
            }

            if event == "ms.error" {
                let reason = errorReason(from: json) ?? "unknown"
                print("[TVDBG][WS] ms.error reason=\(reason)")
                if reason.localizedCaseInsensitiveContains("unrecognized method value : ms.remote.control") {
                    keyCommandMode = .emitKeypress
                    print("[TVDBG][WS] switching key mode -> emitKeypress")
                    return
                }
                if keyCommandMode == .emitKeypress,
                   (reason.localizedCaseInsensitiveContains("cannot read property 'session' of null")
                    || reason.localizedCaseInsensitiveContains("unrecognized method value : ms.channel.emit")) {
                    keyCommandMode = .emitKeypressWithSession
                    print("[TVDBG][WS] switching key mode -> emitKeypressWithSession")
                    return
                }
                if keyCommandMode == .emitKeypressWithSession,
                   reason.localizedCaseInsensitiveContains("cannot read property 'session' of null") {
                    keyCommandMode = .emitRemoteControlWithSession
                    print("[TVDBG][WS] switching key mode -> emitRemoteControlWithSession")
                    return
                }
                if keyCommandMode == .emitRemoteControlWithSession,
                   reason.localizedCaseInsensitiveContains("cannot read property 'session' of null") {
                    isConnected = false
                    continuation?.yield(.error(.unsupportedProtocol(reason)))
                    continuation?.finish()
                    return
                }
                if reason.localizedCaseInsensitiveContains("unauthor")
                    || reason.localizedCaseInsensitiveContains("forbidden")
                    || reason.localizedCaseInsensitiveContains("denied")
                    || reason.localizedCaseInsensitiveContains("reject") {
                    isConnected = false
                    continuation?.yield(.error(.pairingRejected))
                    continuation?.finish()
                }
                return
            }

            if event.localizedCaseInsensitiveContains("unauthorized")
                || event.localizedCaseInsensitiveContains("denied")
                || event.localizedCaseInsensitiveContains("forbidden") {
                isConnected = false
                continuation?.yield(.error(.pairingRejected))
                continuation?.finish()
            }
        }
    }

    private func maybeStoreToken(from json: [String: Any]) {
        guard let payload = json["data"] as? [String: Any],
              let token = payload["token"] as? String,
              !token.isEmpty else {
            return
        }
        print("[TVDBG][WS] token received")
        tokenHandler?(token)
    }

    private func errorReason(from json: [String: Any]) -> String? {
        if let data = json["data"] as? [String: Any] {
            if let message = data["message"] as? String {
                return message
            }
            if let details = data["details"] as? String {
                return details
            }
        }
        if let message = json["message"] as? String {
            return message
        }
        return nil
    }

    private func updateSessionIdentifier(from json: [String: Any]) {
        guard let payload = json["data"] as? [String: Any] else { return }
        if let session = payload["id"] as? String, !session.isEmpty {
            sessionIdentifier = session
            print("[TVDBG][WS] session id captured")
            return
        }
        if let clients = payload["clients"] as? [[String: Any]],
           let session = clients.first?["id"] as? String,
           !session.isEmpty {
            sessionIdentifier = session
            print("[TVDBG][WS] session id captured from clients")
        }
    }

    private func makeKeyPayload(key: RemoteKey, command: String) -> [String: Any] {
        switch keyCommandMode {
        case .remoteControl:
            return [
                "method": "ms.remote.control",
                "params": [
                    "Cmd": command,
                    "DataOfCmd": key.rawValue,
                    "Option": "false",
                    "TypeOfRemote": "SendRemoteKey"
                ]
            ]
        case .emitKeypress:
            return [
                "method": "ms.channel.emit",
                "params": [
                    "event": "ed.keypress",
                    "to": "host",
                    "data": [
                        "key": key.rawValue
                    ]
                ]
            ]
        case .emitKeypressWithSession:
            var params: [String: Any] = [
                "event": "ed.keypress",
                "to": "host",
                "data": [
                    "key": key.rawValue
                ]
            ]
            if let sessionIdentifier, !sessionIdentifier.isEmpty {
                params["session"] = sessionIdentifier
            }
            return [
                "method": "ms.channel.emit",
                "params": params
            ]
        case .emitRemoteControlWithSession:
            var params: [String: Any] = [
                "event": "ed.remote.control",
                "to": "host",
                "data": [
                    "Cmd": command,
                    "DataOfCmd": key.rawValue,
                    "Option": "false",
                    "TypeOfRemote": "SendRemoteKey"
                ]
            ]
            if let sessionIdentifier, !sessionIdentifier.isEmpty {
                params["session"] = sessionIdentifier
            }
            return [
                "method": "ms.channel.emit",
                "params": params
            ]
        }
    }
}
