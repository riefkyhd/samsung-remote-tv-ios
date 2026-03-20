import Foundation

enum TVError: Error, Equatable, LocalizedError, Sendable {
    case notConnected
    case pairingRejected
    case pairingTimeout
    case connectionFailed(String)
    case commandFailed(RemoteKey, String)
    case unsupportedProtocol(String)
    case invalidMacAddress
    case notOnWifi
    case invalidResponse
    case appLaunchFailed
    case spcPairingFailed(String)
    case spcHandshakeFailed(String)
    case spcTokenExpired
    case pinTimeout
    case encryptionFailed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "TV is not connected."
        case .pairingRejected:
            return "Pairing was rejected on the TV."
        case .pairingTimeout:
            return "Pairing timed out."
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .commandFailed(let key, let reason):
            return "Failed to send \(key.rawValue): \(reason)"
        case .unsupportedProtocol(let reason):
            return "Unsupported TV command protocol: \(reason)"
        case .invalidMacAddress:
            return "Invalid MAC address format."
        case .notOnWifi:
            return "Wi-Fi is required."
        case .invalidResponse:
            return "Invalid response from TV."
        case .appLaunchFailed:
            return "Failed to launch app on TV."
        case .spcPairingFailed(let reason):
            return "Encrypted pairing failed: \(reason)"
        case .spcHandshakeFailed(let reason):
            return "Encrypted handshake failed: \(reason)"
        case .spcTokenExpired:
            return "Encrypted TV token expired. Please pair again."
        case .pinTimeout:
            return "PIN entry timed out."
        case .encryptionFailed:
            return "Encrypted command failed."
        }
    }
}
