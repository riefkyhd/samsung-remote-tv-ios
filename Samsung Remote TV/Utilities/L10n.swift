import Foundation

enum L10n {
    static func text(_ key: String, _ defaultValue: String) -> String {
        Bundle.main.localizedString(forKey: key, value: defaultValue, table: nil)
    }
}
