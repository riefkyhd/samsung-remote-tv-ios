import Foundation

actor SpcWebSocketClient {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var continuation: AsyncStream<TVConnectionState>.Continuation?
    private var isConnected = false

    func connect(ipAddress: String, remoteName: String) -> AsyncStream<TVConnectionState> {
        _ = remoteName
        return AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(.connecting)
            print("[TVDBG][SPC] ws connect start ip=\(ipAddress)")

            let connectTask = Task {
                do {
                    try await self.open(ipAddress: ipAddress)
                    continuation.yield(.connected)
                } catch {
                    continuation.yield(.error(.connectionFailed(error.localizedDescription)))
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                connectTask.cancel()
                Task { await self.disconnect() }
            }
        }
    }

    func disconnect() {
        print("[TVDBG][SPC] ws disconnect")
        receiveTask?.cancel()
        heartbeatTask?.cancel()
        receiveTask = nil
        heartbeatTask = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
        continuation?.yield(.disconnected)
        continuation?.finish()
    }

    func sendKey(_ key: RemoteKey, command: String, ctxHex: String, sessionID: String) async throws {
        _ = command
        guard isConnected, let task else {
            throw TVError.notConnected
        }
        guard let sessionId = Int(sessionID) else {
            throw TVError.encryptionFailed
        }
        // Send command directly - namespace already confirmed on connect
        let commandMessage = try SpcCrypto.generateCommand(
            ctxUpperHex: ctxHex,
            sessionId: sessionId,
            keyCode: key.rawValue
        )
        try await task.send(.string(commandMessage))
        print("[TVDBG][SPC] ws send key=\(key.rawValue)")
    }

    private func open(ipAddress: String) async throws {
        let sid = try await fetchSocketIOSessionID(ipAddress: ipAddress)
        let wsURL = URL(string: "ws://\(ipAddress):8000/socket.io/1/websocket/\(sid)")!

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: wsURL)
        task.resume()
        self.session = session
        self.task = task

        // Heartbeat - 2 colons, NOT 3
        try await task.send(.string("2::"))

        // Connect to companion namespace and wait for TV confirmation
        try await task.send(.string("1::/com.samsung.companion"))
        await waitForNamespaceConfirm(task: task, timeout: 2.0)

        self.isConnected = true
        startHeartbeatLoop()
        startReceiveLoop()
        print("[TVDBG][SPC] ws connected ip=\(ipAddress) sid=\(sid)")
    }

    private func waitForNamespaceConfirm(task: URLSessionWebSocketTask, timeout: Double) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard let msg = try? await task.receive(),
                  case .string(let text) = msg else {
                try? await Task.sleep(for: .milliseconds(100))
                continue
            }
            print("[TVDBG][SPC] ws received: \(text)")
            if text.contains("com.samsung.companion") {
                print("[TVDBG][SPC] namespace confirmed")
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        print("[TVDBG][SPC] namespace confirm timeout - proceeding anyway")
    }

    private func fetchSocketIOSessionID(ipAddress: String) async throws -> String {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        guard let url = URL(string: "http://\(ipAddress):8000/socket.io/1/?t=\(ts)") else {
            throw TVError.connectionFailed("Invalid Socket.IO URL")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TVError.connectionFailed("Socket.IO handshake failed")
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        let sid = body.components(separatedBy: ":").first ?? ""
        guard !sid.isEmpty else {
            throw TVError.connectionFailed("Socket.IO session id missing")
        }
        return sid
    }

    private func startReceiveLoop() {
        guard let task else { return }
        receiveTask = Task {
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    if case .string(let text) = message {
                        print("[TVDBG][SPC] ws rx: \(text)")
                        // Reply to heartbeat - 2 colons
                        if text.hasPrefix("2::") {
                            try? await task.send(.string("2::"))
                        }
                    }
                } catch {
                    print("[TVDBG][SPC] ws receive error: \(error)")
                    isConnected = false
                    continuation?.yield(.disconnected)
                    continuation?.finish()
                    break
                }
            }
        }
    }

    private func startHeartbeatLoop() {
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                try? await task?.send(.string("2::"))
            }
        }
    }
}
