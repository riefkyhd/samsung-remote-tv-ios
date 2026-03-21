import Foundation

enum TVCapabilityAction: Sendable {
    case wakeOnLan
    case appLaunch
    case trackpad
    case encryptedPairing
    case numberPad
    case mediaTransport
}

enum TVGeneration: String, Sendable {
    case modernTizen
    case encryptedLegacy
    case legacy
    case unknown
}

struct TVCapabilities: Sendable, Equatable {
    let wakeOnLan: Bool
    let appLaunch: Bool
    let trackpad: Bool
    let encryptedPairing: Bool
    let numberPad: Bool
    let mediaTransport: Bool

    static func resolve(for tv: SamsungTV) -> TVCapabilities {
        let generation = resolveGeneration(for: tv)
        let isModern = generation == .modernTizen
        let isEncrypted = generation == .encryptedLegacy
        let hasMAC = !tv.macAddress.isEmpty

        return TVCapabilities(
            wakeOnLan: isModern && hasMAC,
            appLaunch: isModern,
            trackpad: isModern,
            encryptedPairing: isEncrypted,
            numberPad: true,
            mediaTransport: true
        )
    }

    static func resolveGeneration(for tv: SamsungTV) -> TVGeneration {
        switch tv.protocolType {
        case .modern:
            return .modernTizen
        case .encrypted:
            return .encryptedLegacy
        case .legacy:
            // Keep this conservative: model hint is only used to identify unknowns.
            return tv.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .unknown : .legacy
        }
    }

    func isSupported(_ action: TVCapabilityAction) -> Bool {
        switch action {
        case .wakeOnLan:
            return wakeOnLan
        case .appLaunch:
            return appLaunch
        case .trackpad:
            return trackpad
        case .encryptedPairing:
            return encryptedPairing
        case .numberPad:
            return numberPad
        case .mediaTransport:
            return mediaTransport
        }
    }

    func unsupportedReason(for action: TVCapabilityAction) -> String? {
        guard !isSupported(action) else { return nil }
        switch action {
        case .wakeOnLan:
            return "Wake on LAN is not available for this TV."
        case .appLaunch:
            return "App launch is not supported for this TV protocol."
        case .trackpad:
            return "Trackpad mode is only available on modern TVs."
        case .encryptedPairing:
            return "Encrypted pairing is not required for this TV."
        case .numberPad:
            return "Number pad is not available for this TV."
        case .mediaTransport:
            return "Media transport controls are not available for this TV."
        }
    }
}
