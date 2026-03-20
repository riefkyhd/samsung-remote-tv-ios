import Foundation

protocol TVRepository: Sendable {
    func discoverTVs() -> AsyncStream<SamsungTV>
    func scanTV(at ipAddress: String) async throws -> SamsungTV

    func connect(to tv: SamsungTV) -> AsyncStream<TVConnectionState>
    func completeEncryptedPairing(pin: String, for tv: SamsungTV) async throws
    func disconnect() async

    func sendKey(_ key: RemoteKey, command: String) async throws
    func launchApp(appId: String) async throws

    func wakeOnLan(macAddress: String) async throws
    func getInstalledApps(for tv: SamsungTV) async throws -> [TVApp]

    func getSavedTVs() throws -> [SamsungTV]
    func saveTV(_ tv: SamsungTV) throws
    func deleteTV(_ tv: SamsungTV) throws
    func renameTV(id: UUID, name: String) throws

    func forgetPairing(for tv: SamsungTV) async throws
    func removeDevice(_ tv: SamsungTV) async throws
    func getRemoteName() -> String
    func setRemoteName(_ name: String) throws
}
