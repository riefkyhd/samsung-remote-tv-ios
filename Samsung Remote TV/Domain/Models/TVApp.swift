import Foundation

struct TVApp: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let iconURL: URL?

    init(id: String, name: String, iconURL: URL?) {
        self.id = id
        self.name = name
        self.iconURL = iconURL
    }
}
