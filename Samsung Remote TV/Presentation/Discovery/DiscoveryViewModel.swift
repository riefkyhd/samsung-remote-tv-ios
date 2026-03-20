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
    var visibleDiscoveredTVs: [SamsungTV] {
        discoveredTVs.filter { tv in
            !savedTVs.contains(where: { saved in
                saved.ipAddress == tv.ipAddress ||
                (!saved.macAddress.isEmpty && saved.macAddress == tv.macAddress)
            })
        }
    }

    private let discoverTVsUseCase: DiscoverTVsUseCase
    private let getSavedTVsUseCase: GetSavedTVsUseCase

    init(dependencies: AppDependencies) {
        self.discoverTVsUseCase = dependencies.discoverTVsUseCase
        self.getSavedTVsUseCase = dependencies.getSavedTVsUseCase
    }

    init(
        discoverTVsUseCase: DiscoverTVsUseCase,
        getSavedTVsUseCase: GetSavedTVsUseCase
    ) {
        self.discoverTVsUseCase = discoverTVsUseCase
        self.getSavedTVsUseCase = getSavedTVsUseCase
    }

    func loadSavedTVs() {
        savedTVs = (try? getSavedTVsUseCase.execute()) ?? []
    }

    func startDiscovery() async {
        await scan()
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }

        loadSavedTVs()
        var freshlyFoundIPs = Set<String>()
        let savedIPs = Set(savedTVs.map(\.ipAddress))

        let stream = discoverTVsUseCase.execute()
        for await tv in stream {
            freshlyFoundIPs.insert(tv.ipAddress)

            if let existingIndex = discoveredTVs.firstIndex(where: { $0.ipAddress == tv.ipAddress }) {
                discoveredTVs[existingIndex] = tv
            } else {
                discoveredTVs.append(tv)
            }
        }

        discoveredTVs.removeAll { tv in
            !freshlyFoundIPs.contains(tv.ipAddress) && !savedIPs.contains(tv.ipAddress)
        }
    }

    func connectManual() async -> SamsungTV? {
        let trimmed = manualIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alertMessage = "Please enter an IP address."
            return nil
        }

        guard isValidIPv4(trimmed) else {
            alertMessage = "Please enter a valid IPv4 address."
            return nil
        }

        do {
            let tv = try await discoverTVsUseCase.scanManually(ipAddress: trimmed)
            if let existingIndex = discoveredTVs.firstIndex(where: { $0.ipAddress == tv.ipAddress }) {
                discoveredTVs[existingIndex] = tv
            } else {
                discoveredTVs.insert(tv, at: 0)
            }
            showManualSheet = false
            manualIPAddress = ""
            return tv
        } catch {
            alertMessage = manualErrorMessage(for: error)
            return nil
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

    private func isValidIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            guard let octet = Int(part), (0...255).contains(octet) else {
                return false
            }
        }
        return true
    }

    private func manualErrorMessage(for error: Error) -> String {
        guard let tvError = error as? TVError else {
            return error.localizedDescription
        }
        switch tvError {
        case .notOnWifi:
            return "Connect to Wi-Fi, then try again."
        case .invalidResponse, .connectionFailed:
            return "Could not reach a compatible Samsung TV at that IP."
        default:
            return tvError.localizedDescription
        }
    }
}
