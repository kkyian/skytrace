import Foundation
import Security

struct FeedClient {
    var apiKey: String = ""
    var session: URLSession = .shared
    func request(_ url: URL, airframes: Bool = false) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.setValue("Skytrace-macOS/1.0", forHTTPHeaderField: "User-Agent")
        if airframes && !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw FeedError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw FeedError.http(response.statusCode, response.value(forHTTPHeaderField: "Retry-After") ?? "") }
        return data
    }
    func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var c = URLComponents(string: "https://api.airframes.io/v1/" + path)!
        c.queryItems = query.isEmpty ? nil : query
        return c.url!
    }
    func positions(region: TrackingRegion) async throws -> [Position] {
        let address = "https://api.adsb.lol/v2/point/\(region.latitude)/\(region.longitude)/\(region.radius)"
        return try FeedParser.positions(await request(URL(string: address)!))
    }
    func messages(hex: String? = nil, before: String? = nil, since: Date? = nil, until: Date? = nil) async throws -> [RadioMessage] {
        var q = [URLQueryItem(name: "limit", value: "100")]
        if let hex { q.append(.init(name: "icao", value: hex.uppercased())) }
        if let before { q.append(.init(name: "before_id", value: before)) }
        if let since { q.append(.init(name: "since", value: ISO8601DateFormatter().string(from: since))) }
        if let until { q.append(.init(name: "until", value: ISO8601DateFormatter().string(from: until))) }
        return try FeedParser.messages(await request(url("messages", query: q), airframes: true))
    }
    func airframe(hex: String) async throws -> RemoteAirframe {
        let first = try await request(url("airframes/icao/" + hex.uppercased()), airframes: true)
        let (aircraft, id) = try FeedParser.airframe(first)
        let detail = try await request(url("airframes/" + id), airframes: true)
        let (enriched, _) = try FeedParser.airframe(detail)
        return RemoteAirframe(aircraft: enriched.hex.isEmpty ? aircraft : enriched, flights: try FeedParser.flights(detail))
    }
}

enum Keychain {
    static let service = "io.skytrace.airframes"
    static func read() -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "api-key", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func save(_ value: String) throws {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "api-key"]
        if value.isEmpty {
            let status = SecItemDelete(q as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw error(status) }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw error(added) }
        } else if status != errSecSuccess { throw error(status) }
    }
    static func error(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error"])
    }
}
