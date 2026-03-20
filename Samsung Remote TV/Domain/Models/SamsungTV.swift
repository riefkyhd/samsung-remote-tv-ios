import Foundation

struct SamsungTV: Codable, Hashable, Identifiable, Sendable {
    enum TVProtocol: String, Codable, Sendable {
        case modern
        case encrypted
        case legacy
    }

    enum TVType: String, Codable, Sendable {
        case tizen
        case encrypted
        case legacy
        case unknown
    }

    let id: UUID
    var name: String
    var ipAddress: String
    var macAddress: String
    var model: String
    var type: TVType
    var protocolType: TVProtocol

    nonisolated init(
        id: UUID = UUID(),
        name: String,
        ipAddress: String,
        macAddress: String,
        model: String,
        type: TVType,
        protocolType: TVProtocol? = nil
    ) {
        self.id = id
        self.name = name
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.model = model
        self.type = type
        self.protocolType = protocolType ?? Self.protocolFromType(type)
    }

    private static func protocolFromType(_ type: TVType) -> TVProtocol {
        switch type {
        case .tizen:
            return .modern
        case .encrypted:
            return .encrypted
        case .legacy, .unknown:
            return .legacy
        }
    }
}
