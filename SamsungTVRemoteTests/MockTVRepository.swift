import Foundation
@testable import Samsung_Remote_TV

final class MockTVRepository: TVRepository, @unchecked Sendable {
    var discoveredTVs: [SamsungTV] = []
    var savedTVs: [SamsungTV] = []
    var connectionStates: [TVConnectionState] = [.disconnected]
    var shouldThrowOnSend = false
    var sentKeys: [(RemoteKey, String)] = []
    var launchedAppId: String?

    func discoverTVs() -> AsyncStream<SamsungTV> {
        AsyncStream { continuation in
            for tv in discoveredTVs { continuation.yield(tv) }
            continuation.finish()
        }
    }

    func scanTV(at ipAddress: String) async throws -> SamsungTV {
        if let found = discoveredTVs.first(where: { $0.ipAddress == ipAddress }) {
            return found
        }
        throw TVError.invalidResponse
    }

    func connect(to tv: SamsungTV) -> AsyncStream<TVConnectionState> {
        _ = tv
        return AsyncStream { continuation in
            for state in connectionStates { continuation.yield(state) }
            continuation.finish()
        }
    }

    func disconnect() async {}

    func sendKey(_ key: RemoteKey, command: String) async throws {
        if shouldThrowOnSend { throw TVError.notConnected }
        sentKeys.append((key, command))
    }

    func launchApp(appId: String) async throws {
        launchedAppId = appId
    }

    func wakeOnLan(macAddress: String) async throws {
        guard macAddress.contains(":") else { throw TVError.invalidMacAddress }
    }

    func getInstalledApps(for tv: SamsungTV) async throws -> [TVApp] {
        _ = tv
        return [TVApp(id: "1", name: "TestApp", iconURL: nil)]
    }

    func getSavedTVs() throws -> [SamsungTV] { savedTVs }
    func saveTV(_ tv: SamsungTV) throws { savedTVs.append(tv) }
    func deleteTV(_ tv: SamsungTV) throws { savedTVs.removeAll { $0.id == tv.id } }

    func renameTV(id: UUID, name: String) throws {
        if let i = savedTVs.firstIndex(where: { $0.id == id }) {
            savedTVs[i].name = name
        }
    }

    func forgetToken(for macAddress: String) throws { _ = macAddress }
    func getRemoteName() -> String { "SamsungTVRemote" }
    func setRemoteName(_ name: String) throws { _ = name }
}
