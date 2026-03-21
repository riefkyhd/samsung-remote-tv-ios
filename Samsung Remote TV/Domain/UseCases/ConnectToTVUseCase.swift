import Foundation

struct ConnectToTVUseCase: Sendable {
    private let repository: any TVRepository

    init(repository: any TVRepository) {
        self.repository = repository
    }

    func execute(tv: SamsungTV) -> AsyncStream<TVConnectionState> {
        repository.connect(to: tv)
    }

    func executeWithReconnection(tv: SamsungTV) -> AsyncStream<TVConnectionState> {
        AsyncStream { continuation in
            let task = Task {
                var retryCount = 0
                let fastRetryDelays: [Double] = [1.0, 2.0, 3.0, 5.0]
                let slowRetryDelay: Double = 10.0

                while !Task.isCancelled {
                    continuation.yield(.connecting)
                    var shouldPauseForPin = false
                    var sawError = false
                    var connectedThisPass = false

                    for await state in repository.connect(to: tv) {
                        continuation.yield(state)
                        if case .connected = state {
                            connectedThisPass = true
                            retryCount = 0
                        }
                        if case .pinRequired = state {
                            shouldPauseForPin = true
                            break
                        }
                        if case .error = state {
                            sawError = true
                            break
                        }
                    }

                    if shouldPauseForPin {
                        // Wait until user submits PIN explicitly.
                        break
                    }
                    if Task.isCancelled { break }

                    let delay = retryCount < fastRetryDelays.count
                        ? fastRetryDelays[retryCount]
                        : slowRetryDelay
                    retryCount += 1
                    if sawError || !connectedThisPass {
                        DiagnosticsLogger.log(
                            .reconnect,
                            "scheduled reconnect attempt",
                            metadata: [
                                "delaySeconds": String(delay),
                                "attempt": String(retryCount),
                                "reason": sawError ? "error" : "noConnectedState"
                            ]
                        )
                    }
                    try? await Task.sleep(for: .seconds(delay))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task {
                    await repository.disconnect()
                }
            }
        }
    }
}
