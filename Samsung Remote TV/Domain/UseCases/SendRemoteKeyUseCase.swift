import Foundation

actor RemoteKeyDebouncer {
    private var lastSentAt: Date?
    private let minimumInterval: TimeInterval

    init(minimumInterval: TimeInterval = 0.1) {
        self.minimumInterval = minimumInterval
    }

    func shouldSend(now: Date = Date()) -> Bool {
        defer { lastSentAt = now }
        guard let lastSentAt else {
            return true
        }
        return now.timeIntervalSince(lastSentAt) >= minimumInterval
    }
}

struct SendRemoteKeyUseCase: Sendable {
    private let repository: any TVRepository
    private let debouncer: RemoteKeyDebouncer

    init(repository: any TVRepository, debouncer: RemoteKeyDebouncer = RemoteKeyDebouncer()) {
        self.repository = repository
        self.debouncer = debouncer
    }

    func execute(_ key: RemoteKey) async throws {
        guard await debouncer.shouldSend() else {
            return
        }
        try await repository.sendKey(key, command: "Click")
    }

    func longPress(_ key: RemoteKey, duration: Duration = .milliseconds(800)) async throws {
        try await repository.sendKey(key, command: "Press")
        try await Task.sleep(for: duration)
        try await repository.sendKey(key, command: "Release")
    }
}
