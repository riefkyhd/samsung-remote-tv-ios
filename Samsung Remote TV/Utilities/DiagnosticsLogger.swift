import Foundation
import OSLog

enum DiagnosticsCategory: String {
    case protocolSelection = "protocol"
    case pairing = "pairing"
    case reconnect = "reconnect"
    case capabilities = "capabilities"
    case error = "error"
    case lifecycle = "lifecycle"
}

enum DiagnosticsLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SamsungRemoteTV",
        category: "TVDiagnostics"
    )

    static func log(
        _ category: DiagnosticsCategory,
        _ message: String,
        metadata: [String: String] = [:]
    ) {
        let normalizedMetadata = metadata
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let payload = normalizedMetadata.isEmpty ? "" : " \(normalizedMetadata)"
        logger.debug("[TVDBG][\(category.rawValue)] \(message, privacy: .public)\(payload, privacy: .public)")
    }

    static func redactIdentifier(_ value: String) -> String {
        guard value.count > 4 else { return value }
        return "\(value.prefix(2))...\(value.suffix(2))"
    }
}
