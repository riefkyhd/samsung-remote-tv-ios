import Foundation

struct TVInfoDTO: Codable, Sendable {
    struct Device: Codable, Sendable {
        let id: String?
        let name: String?
        let modelName: String?
        let type: String?
        let wifiMac: String?
        let networkType: String?
        let tokenAuthSupport: String?
    }

    let device: Device?

    func toDomain(ipAddress: String) -> SamsungTV {
        let model = device?.modelName ?? "Unknown"
        let detectedProtocol = detectProtocol(model: model, tokenAuthSupport: device?.tokenAuthSupport)
        let tvType: SamsungTV.TVType = switch detectedProtocol {
        case .modern:
            .tizen
        case .encrypted:
            .encrypted
        case .legacy:
            .legacy
        }

        return SamsungTV(
            name: decodeHTMLEntities(device?.name ?? "Samsung TV"),
            ipAddress: ipAddress,
            macAddress: device?.wifiMac ?? "",
            model: model,
            type: tvType,
            protocolType: detectedProtocol
        )
    }

    private func detectProtocol(model: String, tokenAuthSupport: String?) -> SamsungTV.TVProtocol {
        let tokenAuth = tokenAuthSupport?.lowercased() == "true"
        if tokenAuth {
            return .modern
        }

        let upperModel = model.uppercased()
        let encryptedMarkers = [
            "JU", "JS", "J6", "J5", "J4",
            "HU", "HS", "H6", "H5", "H4"
        ]
        if encryptedMarkers.contains(where: { upperModel.contains($0) }) {
            return .encrypted
        }

        // Default to modern to avoid false negatives on newer model names.
        return .modern
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        var decoded = text
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        if let regex = try? NSRegularExpression(pattern: "&#(x?[0-9A-Fa-f]+);") {
            let source = decoded
            let nsrange = NSRange(source.startIndex..<source.endIndex, in: source)
            let matches = regex.matches(in: source, range: nsrange).reversed()
            for match in matches {
                guard
                    match.numberOfRanges >= 2,
                    let tokenRange = Range(match.range(at: 1), in: source),
                    let fullRange = Range(match.range(at: 0), in: decoded)
                else { continue }

                let token = String(source[tokenRange])
                let scalarValue: UInt32?
                if token.lowercased().hasPrefix("x") {
                    scalarValue = UInt32(token.dropFirst(), radix: 16)
                } else {
                    scalarValue = UInt32(token, radix: 10)
                }

                if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
                    decoded.replaceSubrange(fullRange, with: String(Character(scalar)))
                } else {
                    decoded.replaceSubrange(fullRange, with: "")
                }
            }
        }

        return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
