import Foundation
import Observation

@Observable
@MainActor
final class DiscoveryViewModel {
    var discoveredTVs: [SamsungTV] = []
    var savedTVs: [SamsungTV] = []
    var isScanning = false
    var showManualSheet = false
    var manualIPAddress = ""
    var alertMessage: String?

    private let discoverTVsUseCase: DiscoverTVsUseCase
    private let getSavedTVsUseCase: GetSavedTVsUseCase

    init(dependencies: AppDependencies) {
        self.discoverTVsUseCase = dependencies.discoverTVsUseCase
        self.getSavedTVsUseCase = dependencies.getSavedTVsUseCase
    }

    func loadSavedTVs() {
        savedTVs = (try? getSavedTVsUseCase.execute()) ?? []
    }

    func startDiscovery() async {
        await scan()
    }

    func scan() async {
        isScanning = true
        discoveredTVs.removeAll()

        let stream = discoverTVsUseCase.execute()
        for await tv in stream {
            if !discoveredTVs.contains(where: { $0.id == tv.id || $0.macAddress == tv.macAddress }) {
                discoveredTVs.append(tv)
            }
        }

        isScanning = false
    }

    func connectManual() async {
        let trimmed = manualIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alertMessage = "Please enter an IP address."
            return
        }

        do {
            let tv = try await discoverTVsUseCase.scanManually(ipAddress: trimmed)
            discoveredTVs.insert(tv, at: 0)
            showManualSheet = false
            manualIPAddress = ""
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func deleteSavedTV(_ tv: SamsungTV) {
        do {
            try getSavedTVsUseCase.delete(tv)
            loadSavedTVs()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
