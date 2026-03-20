import Foundation

enum SpcHandshakeParser {
    struct Step1Result: Sendable {
        let requestID: String
        let clientHelloHex: String
    }

    struct Step2Result: Sendable {
        let ctxHex: String
        let sessionID: String
    }

    nonisolated static func serverHelloHex(from jsonData: Data) throws -> String {
        if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            if let authData = object(from: json, keys: ["auth_Data", "auth_data"]),
               let value = string(from: authData, keys: ["GeneratorServerHello", "generatorServerHello", "generator_server_hello"]),
               !value.isEmpty {
                return value
            }

            if let value = string(from: json, keys: ["GeneratorServerHello", "generatorServerHello", "generator_server_hello"]),
               !value.isEmpty {
                return value
            }
        }

        guard let text = String(data: jsonData, encoding: .utf8) else {
            throw TVError.spcPairingFailed("Missing GeneratorServerHello")
        }

        if let value = capture(
            text,
            pattern: "(?i)GeneratorServerHello\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""
        ) {
            return value
        }

        if let value = capture(
            text,
            pattern: "(?i)server_hello\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""
        ) {
            return value
        }

        throw TVError.spcPairingFailed("Missing GeneratorServerHello")
    }

    nonisolated private static func object(
        from dictionary: [String: Any],
        keys: [String]
    ) -> [String: Any]? {
        for key in keys {
            if let object = dictionary[key] as? [String: Any] {
                return object
            }
            if let objectText = dictionary[key] as? String,
               let data = objectText.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return object
            }
        }
        return nil
    }

    nonisolated private static func string(
        from dictionary: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                return value
            }
        }
        return nil
    }

    nonisolated static func step1Result(from jsonData: Data) throws -> Step1Result {
        if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let authData = object(from: json, keys: ["auth_Data", "auth_data"]) {
            let requestID = string(from: authData, keys: ["request_id", "requestId"])
            let clientHello = string(from: authData, keys: ["GeneratorClientHello", "generatorClientHello", "generator_client_hello"])
            if let requestID, let clientHello, !requestID.isEmpty, !clientHello.isEmpty {
                return Step1Result(requestID: requestID, clientHelloHex: clientHello)
            }
        }

        guard let text = String(data: jsonData, encoding: .utf8) else {
            throw TVError.spcPairingFailed("Invalid step1 response")
        }

        let requestID = capture(text, pattern: "(?i)request_id\\\"\\s*:\\s*\\\"?(\\d+)\\\"?")
        let clientHello = capture(text, pattern: "(?i)GeneratorClientHello\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"")

        guard let requestID, let clientHello else {
            throw TVError.spcPairingFailed("Missing request_id or GeneratorClientHello")
        }

        return Step1Result(requestID: requestID, clientHelloHex: clientHello)
    }

    nonisolated static func step2Result(from jsonData: Data) throws -> Step2Result {
        if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let authData = object(from: json, keys: ["auth_Data", "auth_data"]) {
            let ctxHex = string(from: authData, keys: ["ClientAckMsg", "clientAckMsg", "client_ack_msg"])
            if let ctxHex, !ctxHex.isEmpty {
                let sessionID = string(from: authData, keys: ["session_id", "sessionId"]) ?? "1"
                return Step2Result(ctxHex: ctxHex, sessionID: sessionID)
            }
        }

        guard let text = String(data: jsonData, encoding: .utf8) else {
            throw TVError.spcPairingFailed("Invalid step2 response")
        }

        let ctxHex = capture(text, pattern: "(?i)ClientAckMsg\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"")
        let sessionID = capture(text, pattern: "(?i)session_id\\\"\\s*:\\s*\\\"?(\\d+)\\\"?")

        guard let ctxHex, let sessionID else {
            throw TVError.spcPairingFailed("Missing ClientAckMsg or session_id")
        }

        return Step2Result(ctxHex: ctxHex, sessionID: sessionID)
    }

    nonisolated private static func capture(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }
}
