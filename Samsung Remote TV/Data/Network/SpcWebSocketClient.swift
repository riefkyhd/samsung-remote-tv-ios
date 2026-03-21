import Foundation

actor SpcWebSocketClient {
    private typealias PendingCommand = (key: RemoteKey, ctxHex: String, sessionId: Int)

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var sendQueue: AsyncStream<PendingCommand>.Continuation?
    private var sendQueueTask: Task<Void, Never>?
    private var firstCommandVerifyTask: Task<Void, Never>?
    private var continuation: AsyncStream<TVConnectionState>.Continuation?
    private var isConnected = false
    private var receivedFirstResponse = false
    private var queuedFirstCommand = false

    func connect(ipAddress: String, remoteName: String) -> AsyncStream<TVConnectionState> {
        _ = remoteName
        resetSendQueue()

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
        firstCommandVerifyTask?.cancel()
        resetSendQueue()
        receiveTask = nil
        heartbeatTask = nil
        firstCommandVerifyTask = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
        receivedFirstResponse = false
        queuedFirstCommand = false
        continuation?.yield(.disconnected)
        continuation?.finish()
    }

    func sendKey(_ key: RemoteKey, command: String, ctxHex: String, sessionID: String) async throws {
        _ = command
        guard isConnected else { throw TVError.notConnected }
        guard let sessionId = Int(sessionID) else { throw TVError.encryptionFailed }
        sendQueue?.yield((key: key, ctxHex: ctxHex, sessionId: sessionId))
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
        self.receivedFirstResponse = false
        self.queuedFirstCommand = false
        startSendQueue()
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
                        if text.contains("receiveCommon") {
                            receivedFirstResponse = true
                        }
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

    private func startSendQueue() {
        let stream = AsyncStream<PendingCommand> { continuation in
            self.sendQueue = continuation
        }

        sendQueueTask = Task {
            for await command in stream {
                guard let task = self.task else { continue }
                let message: String?
                do {
                    message = try await MainActor.run(body: {
                        try SpcCrypto.generateCommand(
                            ctxUpperHex: command.ctxHex,
                            sessionId: command.sessionId,
                            keyCode: command.key.rawValue
                        )
                    })
                } catch {
                    message = nil
                }
                guard let message else {
                    continue
                }

                try? await task.send(.string(message))
                print("[TVDBG][SPC] ws send key=\(command.key.rawValue)")

                if !queuedFirstCommand {
                    queuedFirstCommand = true
                    firstCommandVerifyTask?.cancel()
                    firstCommandVerifyTask = Task {
                        await verifyFirstCommandResponse()
                    }
                }

                // Keep command cadence stable and avoid TV-side command buffering spikes.
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func resetSendQueue() {
        sendQueueTask?.cancel()
        sendQueue?.finish()
        sendQueue = nil
        sendQueueTask = nil
    }

    private func verifyFirstCommandResponse() async {
        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            if receivedFirstResponse { return }
            try? await Task.sleep(for: .milliseconds(200))
        }

        guard isConnected else { return }
        print("[TVDBG][SPC] no response to first command — credentials may be stale")
        continuation?.yield(.error(.spcTokenExpired))
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
