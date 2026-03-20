import Foundation

struct SamsungTVRestClient: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchTVInfo(ipAddress: String, timeout: TimeInterval = 2.0) async throws -> SamsungTV {
        guard !NetworkUtils.isLinkLocalIPAddress(ipAddress) else {
            throw TVError.invalidResponse
        }

        guard let url = URL(string: "http://\(ipAddress):8001/api/v2/") else {
            throw TVError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TVError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(TVInfoDTO.self, from: data)
        var tv = decoded.toDomain(ipAddress: ipAddress)
        if tv.protocolType == .encrypted {
            let supportsSpc = await NetworkUtils.isTCPPortOpen(ipAddress: ipAddress, port: 8080, timeout: .seconds(2))
            if !supportsSpc {
                tv.protocolType = .legacy
                tv.type = .legacy
            }
        }
        return tv
    }
}
