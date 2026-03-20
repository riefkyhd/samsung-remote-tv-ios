import Foundation

actor SpcHandshakeClient {
    struct PairingOutcome: Sendable {
        let credentials: TVUserDefaultsStorage.SpcCredentials
        let step0Variant: String
        let step1Variant: String
    }

    struct Step2SessionResult: Sendable {
        let sessionId: Int
    }

    private let session: URLSession
    private let appID = "12345"
    private let fixedDeviceID = "654321"
    private var pendingByIP: Set<String> = []

    init(session: URLSession = .shared) {
        self.session = session
    }

    func startPairing(
        tv: SamsungTV,
        deviceID: String,
        preferredStep0: String?,
        preferredStep1: String?
    ) async throws {
        _ = deviceID
        _ = preferredStep0
        _ = preferredStep1
        if pendingByIP.contains(tv.ipAddress) {
            // Keep existing pending session to avoid re-triggering duplicated TV PIN overlays.
            return
        }
        print("[TVDBG][SPC] prepare pairing ip=\(tv.ipAddress)")
        try await requestDeletePinPage(ip: tv.ipAddress)
        try await requestShowPinPage(ip: tv.ipAddress)
        pendingByIP.insert(tv.ipAddress)
    }

    func preparePairing(tv: SamsungTV) async throws {
        print("[TVDBG][SPC] prepare pairing ip=\(tv.ipAddress)")
        try await requestDeletePinPage(ip: tv.ipAddress)
        try await requestShowPinPage(ip: tv.ipAddress)
    }

    func completePairing(
        tv: SamsungTV,
        pin: String,
        deviceID: String,
        preferredStep0: String?,
        preferredStep1: String?
    ) async throws -> PairingOutcome {
        _ = deviceID
        _ = preferredStep0
        _ = preferredStep1

        _ = try await requestStep0(ip: tv.ipAddress, deviceID: fixedDeviceID)
        let step1Result = try await requestStep1WithCrypto(
            ip: tv.ipAddress,
            deviceID: fixedDeviceID,
            pin: pin
        )
        let step1Data = step1Result.data
        guard let step1Raw = String(data: step1Data, encoding: .utf8),
              let clientHelloHex = parseGeneratorClientHello(from: step1Raw) else {
            print("[TVDBG][SPC] step1 FAILED - GeneratorClientHello missing")
            throw TVError.spcHandshakeFailed("Step1 returned empty auth_data")
        }

        guard let parsedHello = try SpcCrypto.parseClientHello(
            clientHelloHex: clientHelloHex,
            hash: step1Result.hash,
            aesKey: step1Result.aesKey,
            userId: fixedDeviceID
        ) else {
            throw TVError.spcPairingFailed("PIN incorrect")
        }

        // Step2 must follow parseClientHello immediately to avoid session expiry.
        let serverAckMsg = SpcCrypto.generateServerAcknowledge(skPrime: parsedHello.skPrime)
        let requestID = extractRequestID(from: step1Data) ?? "0"
        let step2Data = try await requestStep2(
            ip: tv.ipAddress,
            deviceID: fixedDeviceID,
            requestID: requestID,
            serverAckMsg: serverAckMsg
        )
        if isAuthDataEmpty(step2Data) {
            throw TVError.spcPairingFailed("Step2 returned empty — session expired")
        }

        let sessionResult = try parseDoubleEncodedStep2(step2Data)
        pendingByIP.remove(tv.ipAddress)
        let ctxUpperHex = parsedHello.ctx.map { String(format: "%02X", $0) }.joined()
        print("[TVDBG][SPC] pairing complete CTX=\(ctxUpperHex.prefix(8))... sessionId=\(sessionResult.sessionId)")

        let creds = TVUserDefaultsStorage.SpcCredentials(
            ctxUpperHex: ctxUpperHex,
            sessionId: sessionResult.sessionId
        )
        return PairingOutcome(
            credentials: creds,
            step0Variant: "CONFIRMED",
            step1Variant: "CONFIRMED"
        )
    }

    func cancelPairing(tv: SamsungTV) {
        pendingByIP.remove(tv.ipAddress)
    }
}

private extension SpcHandshakeClient {
    func requestDeletePinPage(ip: String) async throws {
        guard let url = URL(string: "http://\(ip):8080/ws/apps/CloudPINPage/run") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 3
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[TVDBG][SPC] request DELETE /ws/apps/CloudPINPage/run status=\(status) body={\(String(data: data, encoding: .utf8) ?? "")}")
    }

    func requestShowPinPage(ip: String) async throws {
        let getURL = URL(string: "http://\(ip):8080/ws/apps/CloudPINPage")!
        var getReq = URLRequest(url: getURL)
        getReq.httpMethod = "GET"
        getReq.timeoutInterval = 3
        let (getData, getResp) = try await session.data(for: getReq)
        let getStatus = (getResp as? HTTPURLResponse)?.statusCode ?? 0
        print("[TVDBG][SPC] request GET /ws/apps/CloudPINPage status=\(getStatus) body={\(String(data: getData, encoding: .utf8) ?? "")}")

        var postReq = URLRequest(url: getURL)
        postReq.httpMethod = "POST"
        postReq.timeoutInterval = 3
        postReq.httpBody = Data("pin4".utf8)
        let (postData, postResp) = try await session.data(for: postReq)
        let postStatus = (postResp as? HTTPURLResponse)?.statusCode ?? 0
        print("[TVDBG][SPC] request POST /ws/apps/CloudPINPage status=\(postStatus) body={\(String(data: postData, encoding: .utf8) ?? "")}")
        if !(200..<300).contains(postStatus) {
            throw TVError.spcPairingFailed("CloudPINPage POST failed (\(postStatus))")
        }
        print("[TVDBG][SPC] CloudPINPage POST ok status=\(postStatus)")
    }

    func pairingURL(ip: String, step: Int, deviceID: String) -> URL {
        let base = "http://\(ip):8080/ws/pairing?step=\(step)&app_id=\(appID)&device_id=\(deviceID)"
        return URL(string: step == 0 ? base + "&type=1" : base)!
    }

    func requestStep0(ip: String, deviceID: String) async throws -> Data {
        let url = pairingURL(ip: ip, step: 0, deviceID: deviceID)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 3
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[TVDBG][SPC] step0 response status=\(status) body={\(String(data: data, encoding: .utf8) ?? "")}")
        // {"auth_data":""} is normal for step0 on many JU firmwares.
        return data
    }

    func requestStep1WithCrypto(
        ip: String,
        deviceID: String,
        pin: String
    ) async throws -> (data: Data, aesKey: Data, hash: Data) {
        let url = pairingURL(ip: ip, step: 1, deviceID: deviceID)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let localHello = try SpcCrypto.generateServerHello(userId: deviceID, pin: pin)
        let serverHelloHex = localHello.serverHello.map { String(format: "%02X", $0) }.joined()
        let body = "{\"auth_Data\":{\"auth_type\":\"SPC\",\"GeneratorServerHello\":\"\(serverHelloHex)\"}}"
        req.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[TVDBG][SPC] step1 response status=\(status) body={\(String(data: data, encoding: .utf8) ?? "")}")
        guard (200..<300).contains(status) else {
            throw TVError.spcHandshakeFailed("Step1 failed (\(status))")
        }
        guard let raw = String(data: data, encoding: .utf8),
              parseGeneratorClientHello(from: raw) != nil else {
            print("[TVDBG][SPC] step1 FAILED — GeneratorClientHello missing from raw response")
            print("[TVDBG][SPC] possible cause: pairing session reset before step1")
            throw TVError.spcHandshakeFailed("Step1 returned empty auth_data")
        }
        return (data, localHello.aesKey, localHello.hash)
    }

    func requestStep2(
        ip: String,
        deviceID: String,
        requestID: String,
        serverAckMsg: String
    ) async throws -> Data {
        let url = pairingURL(ip: ip, step: 2, deviceID: deviceID)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 3
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "auth_Data": [
                "auth_type": "SPC",
                "request_id": requestID,
                "ServerAckMsg": serverAckMsg
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[TVDBG][SPC] step2 raw status=\(status) body={\(String(data: data, encoding: .utf8) ?? "")}")
        guard (200..<300).contains(status) else {
            throw TVError.spcHandshakeFailed("Step2 failed (\(status))")
        }
        return data
    }

    func extractRequestID(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let direct = (json["auth_Data"] as? [String: Any]) ?? (json["auth_data"] as? [String: Any])
        if let requestID = direct?["request_id"] as? String {
            return requestID
        }

        if let authString = (json["auth_Data"] as? String) ?? (json["auth_data"] as? String),
           let innerData = authString.data(using: .utf8),
           let inner = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any],
           let requestID = inner["request_id"] as? String {
            return requestID
        }

        return nil
    }

    func parseDoubleEncodedStep2(_ data: Data) throws -> Step2SessionResult {
        guard
            let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let authString = (outer["auth_data"] as? String) ?? (outer["auth_Data"] as? String),
            let authData = authString.data(using: .utf8),
            let inner = try? JSONSerialization.jsonObject(with: authData) as? [String: Any]
        else {
            throw TVError.spcHandshakeFailed("Invalid step2 double-encoded response")
        }

        let sessionString = (inner["session_id"] as? String) ?? ""
        let sessionId = Int(sessionString) ?? 0
        guard sessionId > 0 else {
            throw TVError.spcHandshakeFailed("Missing session_id in step2 response")
        }
        return Step2SessionResult(sessionId: sessionId)
    }

    func parseGeneratorClientHello(from response: String) -> String? {
        guard
            let data = response.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if let authData = json["auth_Data"] as? [String: Any],
           let hello = authData["GeneratorClientHello"] as? String {
            return hello
        }
        if let authData = json["auth_data"] as? [String: Any],
           let hello = authData["GeneratorClientHello"] as? String {
            return hello
        }
        if let authString = json["auth_data"] as? String,
           let innerData = authString.data(using: .utf8),
           let inner = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any],
           let hello = inner["GeneratorClientHello"] as? String {
            return hello
        }
        return nil
    }

    func isAuthDataEmpty(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8)?
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .lowercased() else {
            return true
        }
        return text == "{\"auth_data\":\"\"}" || text == "{\"auth_data\":null}" || text.contains("\"auth_data\":\"\"")
    }
}
