import Foundation

enum TVConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case pairing(countdown: Int)
    case pinRequired(countdown: Int)
    case connected
    case error(TVError)
}
