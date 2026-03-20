import Foundation
import Observation

@Observable
@MainActor
final class AppDependencies {
    let discoverTVsUseCase: DiscoverTVsUseCase
    let connectToTVUseCase: ConnectToTVUseCase
    let sendRemoteKeyUseCase: SendRemoteKeyUseCase
    let getSavedTVsUseCase: GetSavedTVsUseCase
    let wakeOnLanUseCase: WakeOnLanUseCase
    let getInstalledAppsUseCase: GetInstalledAppsUseCase
    let pairWithEncryptedTVUseCase: PairWithEncryptedTVUseCase
    let disconnectTVUseCase: DisconnectTVUseCase
    let launchTVAppUseCase: LaunchTVAppUseCase
    let forgetPairingUseCase: ForgetPairingUseCase
    let removeDeviceUseCase: RemoveDeviceUseCase
    let getRemoteNameUseCase: GetRemoteNameUseCase
    let setRemoteNameUseCase: SetRemoteNameUseCase

    init() {
        let restClient = SamsungTVRestClient()
        let webSocketClient = SamsungTVWebSocketClient()
        let smartViewClient = SmartViewSDKClient()
        let spcWebSocketClient = SpcWebSocketClient()
        let spcHandshakeClient = SpcHandshakeClient()
        let legacyRemoteClient = SamsungLegacyRemoteClient()
        let storage = TVUserDefaultsStorage()
        let secureStorage = TVSecureStorage()

        let scanner = IPRangeScanner(restClient: restClient)
        let bonjour = BonjourDiscovery(restClient: restClient)
        let ssdp = SSDPDiscovery(restClient: restClient)

        let repository = TVRepositoryImpl(
            restClient: restClient,
            webSocketClient: webSocketClient,
            smartViewClient: smartViewClient,
            spcWebSocketClient: spcWebSocketClient,
            spcHandshakeClient: spcHandshakeClient,
            legacyRemoteClient: legacyRemoteClient,
            storage: storage,
            secureStorage: secureStorage,
            ipRangeScanner: scanner,
            bonjourDiscovery: bonjour,
            ssdpDiscovery: ssdp
        )

        self.discoverTVsUseCase = DiscoverTVsUseCase(repository: repository)
        self.connectToTVUseCase = ConnectToTVUseCase(repository: repository)
        self.sendRemoteKeyUseCase = SendRemoteKeyUseCase(repository: repository)
        self.getSavedTVsUseCase = GetSavedTVsUseCase(repository: repository)
        self.wakeOnLanUseCase = WakeOnLanUseCase(repository: repository)
        self.getInstalledAppsUseCase = GetInstalledAppsUseCase(repository: repository)
        self.pairWithEncryptedTVUseCase = PairWithEncryptedTVUseCase(repository: repository)
        self.disconnectTVUseCase = DisconnectTVUseCase(repository: repository)
        self.launchTVAppUseCase = LaunchTVAppUseCase(repository: repository)
        self.forgetPairingUseCase = ForgetPairingUseCase(repository: repository)
        self.removeDeviceUseCase = RemoveDeviceUseCase(repository: repository)
        self.getRemoteNameUseCase = GetRemoteNameUseCase(repository: repository)
        self.setRemoteNameUseCase = SetRemoteNameUseCase(repository: repository)
    }
}
