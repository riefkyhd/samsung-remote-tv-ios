import Foundation
import Testing
@testable import Samsung_Remote_TV

@Suite("ConnectToTVUseCase")
struct ConnectToTVUseCaseTests {
    @Test("No stored token produces Pairing connection state")
    func noTokenPairing() async {
        let repo = MockTVRepository()
        repo.connectionStates = [.connecting, .pairing(countdown: 30)]
        let sut = ConnectToTVUseCase(repository: repo)
        let tv = SamsungTV(name: "TV", ipAddress: "1.1.1.1", macAddress: "AA", model: "Q", type: .tizen)

        var states: [TVConnectionState] = []
        for await state in sut.execute(tv: tv) { states.append(state) }

        #expect(states.contains(.pairing(countdown: 30)))
    }

    @Test("Valid stored token produces Connected state without pairing")
    func tokenConnected() async {
        let repo = MockTVRepository()
        repo.connectionStates = [.connecting, .connected]
        let sut = ConnectToTVUseCase(repository: repo)
        let tv = SamsungTV(name: "TV", ipAddress: "1.1.1.1", macAddress: "AA", model: "Q", type: .tizen)

        var states: [TVConnectionState] = []
        for await state in sut.execute(tv: tv) { states.append(state) }

        #expect(states.contains(.connected))
        #expect(!states.contains(.pairing(countdown: 30)))
    }

    @Test("Connection stream preserves fallback-style state sequence from repository")
    func fallbackStateSequenceIsPreserved() async {
        let repo = MockTVRepository()
        repo.connectionStates = [
            .connecting,
            .error(.connectionFailed("wss failed")),
            .connecting,
            .connected
        ]
        let sut = ConnectToTVUseCase(repository: repo)
        let tv = SamsungTV(name: "TV", ipAddress: "1.1.1.1", macAddress: "AA", model: "Q", type: .tizen)

        var states: [TVConnectionState] = []
        for await state in sut.execute(tv: tv) {
            states.append(state)
        }

        #expect(states == repo.connectionStates)
    }

    @Test("TV rejects pairing produces Error state with PairingRejected")
    func pairingRejectedState() async {
        let repo = MockTVRepository()
        repo.connectionStates = [.error(.pairingRejected)]
        let sut = ConnectToTVUseCase(repository: repo)
        let tv = SamsungTV(name: "TV", ipAddress: "1.1.1.1", macAddress: "AA", model: "Q", type: .tizen)

        var emittedError = false
        for await state in sut.execute(tv: tv) {
            if state == .error(.pairingRejected) { emittedError = true }
        }
        #expect(emittedError)
    }

    @Test("Reconnection uses exponential backoff sequence 1s-2s-4s-8s-16s-30s")
    func backoffSequence() {
        let expected = [1, 2, 4, 8, 16, 30]
        var values: [Int] = []
        var delay = 1
        for _ in 0..<6 {
            values.append(delay)
            delay = min(delay * 2, 30)
        }
        #expect(values == expected)
    }

    @Test("Reconnection stream emits connecting before repository state")
    func reconnectionStreamStartsWithConnectingState() async {
        let repo = MockTVRepository()
        repo.connectionStates = [.error(.connectionFailed("network down"))]
        let sut = ConnectToTVUseCase(repository: repo)
        let tv = SamsungTV(name: "TV", ipAddress: "1.1.1.1", macAddress: "AA", model: "Q", type: .tizen)

        let stream = sut.executeWithReconnection(tv: tv)
        let collectTask = Task { () -> [TVConnectionState] in
            var states: [TVConnectionState] = []
            for await state in stream {
                states.append(state)
                if states.count == 2 { break }
            }
            return states
        }
        let states = await collectTask.value

        #expect(states.count == 2)
        #expect(states[0] == .connecting)
        #expect(states[1] == .error(.connectionFailed("network down")))
    }
}
