import Foundation
import Testing
@testable import Samsung_Remote_TV

@Suite("TVRepository ConnectionCoordinator")
struct TVRepositoryConnectionCoordinatorTests {
    @Test("State transitions are explicit across connect pairing pin and disconnect")
    func explicitStateTransitions() async {
        let coordinator = TVRepositoryImpl.ConnectionCoordinator()
        let tv = SamsungTV(
            name: "TV",
            ipAddress: "192.168.1.20",
            macAddress: "AA:BB:CC:DD:EE:FF",
            model: "Q",
            type: .tizen
        )

        let session = await coordinator.beginConnect(tv: tv)
        #expect(await isState(coordinator, .connecting))

        await coordinator.markPairingInProgress(session: session)
        #expect(await isState(coordinator, .pairing))

        await coordinator.markPinRequired(session: session)
        #expect(await isState(coordinator, .pinRequired))

        await coordinator.markConnected(session: session)
        #expect(await isState(coordinator, .connected))

        _ = await coordinator.invalidateForDisconnect()
        #expect(await isState(coordinator, .idle))
    }

    @Test("Stale session updates are ignored after a new connect begins")
    func staleSessionUpdatesIgnored() async {
        let coordinator = TVRepositoryImpl.ConnectionCoordinator()
        let tv = SamsungTV(
            name: "TV",
            ipAddress: "192.168.1.20",
            macAddress: "AA:BB:CC:DD:EE:FF",
            model: "Q",
            type: .tizen
        )

        let oldSession = await coordinator.beginConnect(tv: tv)
        let newSession = await coordinator.beginConnect(tv: tv)

        await coordinator.markConnected(session: oldSession)
        #expect(await isState(coordinator, .connecting))
        #expect(await coordinator.isCurrentSession(newSession))
    }

    @Test("Termination disconnect guard is disabled during pairing")
    func terminationGuardDuringPairing() async {
        let coordinator = TVRepositoryImpl.ConnectionCoordinator()
        let tv = SamsungTV(
            name: "TV",
            ipAddress: "192.168.1.20",
            macAddress: "AA:BB:CC:DD:EE:FF",
            model: "Q",
            type: .tizen
        )

        let session = await coordinator.beginConnect(tv: tv)
        await coordinator.markPairingInProgress(session: session)

        let shouldDisconnect = await coordinator.shouldDisconnectOnConnectTermination(session: session)
        #expect(shouldDisconnect == false)
    }

    private func isState(
        _ coordinator: TVRepositoryImpl.ConnectionCoordinator,
        _ expected: TVRepositoryImpl.ConnectionLifecycleState
    ) async -> Bool {
        let state = await coordinator.lifecycleState
        switch (state, expected) {
        case (.idle, .idle), (.connecting, .connecting), (.pairing, .pairing),
             (.pinRequired, .pinRequired), (.connected, .connected):
            return true
        default:
            return false
        }
    }
}
