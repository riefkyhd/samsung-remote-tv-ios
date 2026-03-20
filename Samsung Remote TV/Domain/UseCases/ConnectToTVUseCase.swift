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
                var delay: Double = 1
                while !Task.isCancelled {
                    var shouldPauseForPin = false
                    var shouldStopReconnect = false
                    for await state in repository.connect(to: tv) {
                        continuation.yield(state)
                        if case .connected = state {
                            delay = 1
                        }
                        if case .pinRequired = state {
                            shouldPauseForPin = true
                        }
                        if case .error(let error) = state {
                            switch error {
                            case .spcHandshakeFailed, .spcPairingFailed, .pinTimeout, .unsupportedProtocol:
                                shouldStopReconnect = true
                            default:
                                break
                            }
                        }
                    }

                    if shouldPauseForPin {
                        // Wait until user submits PIN via explicit pairing action.
                        break
                    }
                    if shouldStopReconnect {
                        break
                    }

                    continuation.yield(.connecting)
                    try? await Task.sleep(for: .seconds(delay))
                    delay = min(delay * 2, 30)
                }
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
