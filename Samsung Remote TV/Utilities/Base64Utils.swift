import Foundation

enum Base64Utils {
    static func encode(_ string: String) -> String {
        Data(string.utf8).base64EncodedString()
    }
}
