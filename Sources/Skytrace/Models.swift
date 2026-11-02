import Foundation
import CoreLocation

struct Aircraft: Identifiable, Equatable, Codable {
    var hex: String
    var registration: String = ""
    var type: String = ""
    var flags: String = ""
    var description: String = ""
    var year: String = ""
    var owner: String = ""
    var id: String { hex }
    var title: String { registration.isEmpty ? hex.uppercased() : registration }
}

struct Position: Identifiable, Equatable {
    var hex: String
    var callsign: String
    var registration: String
    var type: String
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var speed: Double?
    var heading: Double
    var verticalRate: Double?
    var squawk: String
    var observed: Date
    var onGround: Bool
    var id: String { hex }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var title: String { callsign.isEmpty ? (registration.isEmpty ? hex.uppercased() : registration) : callsign }
}

struct TrackPoint: Identifiable {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var callsign: String
    var id: Double { timestamp.timeIntervalSince1970 }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct RadioMessage: Identifiable, Codable {
    var id: String
    var timestamp: Date
    var hex: String
    var tail: String
    var flight: String
    var label: String
    var text: String
    var sourceType: String
    var frequency: String
    var station: String
    var direction: String
    var flightID: String?
    var title: String { flight.isEmpty ? (tail.isEmpty ? hex.uppercased() : tail) : flight }
}

struct HistoricFlight: Identifiable {
    var id: String
    var callsign: String
    var departure: String
    var destination: String
    var status: String
    var date: String
}
struct RemoteAirframe {
    var aircraft: Aircraft
    var flights: [HistoricFlight]
}
struct TrackingRegion: Identifiable, Hashable {
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Int
    var id: String { name }
    static let presets = [
        TrackingRegion(name: "Singapore", latitude: 1.35, longitude: 103.99, radius: 200),
        TrackingRegion(name: "London", latitude: 51.47, longitude: -0.45, radius: 200),
        TrackingRegion(name: "New York", latitude: 40.64, longitude: -73.78, radius: 200),
        TrackingRegion(name: "Los Angeles", latitude: 33.94, longitude: -118.41, radius: 200),
        TrackingRegion(name: "Dubai", latitude: 25.25, longitude: 55.36, radius: 200),
        TrackingRegion(name: "Sydney", latitude: -33.94, longitude: 151.18, radius: 200)
    ]
}

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String {
        guard let v = self[key], !(v is NSNull) else { return "" }
        return (v as? String) ?? (v as? NSNumber)?.stringValue ?? ""
    }
    func number(_ key: String) -> Double? {
        if let n = self[key] as? NSNumber { return n.doubleValue }
        return Double(string(key))
    }
    func object(_ key: String) -> [String: Any] { self[key] as? [String: Any] ?? [:] }
}

enum FeedParser {
    static func date(_ value: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    static func objects(_ data: Data) throws -> [[String: Any]] {
        let value = try JSONSerialization.jsonObject(with: data)
        if let a = value as? [[String: Any]] { return a }
        if let d = value as? [String: Any] {
            for key in ["data", "messages", "results", "airframes", "flights"] {
                if let a = d[key] as? [[String: Any]] { return a }
            }
        }
        throw FeedError.invalidResponse
    }
    static func positions(_ data: Data, received: Date = Date()) throws -> [Position] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let ac = root["ac"] as? [[String: Any]] else { throw FeedError.invalidResponse }
        // API 'now' is milliseconds since the Unix epoch. Never date old coordinates as newly observed.
        let feedTime = root.number("now").map { Date(timeIntervalSince1970: $0 / 1000) } ?? received
        return ac.compactMap { d in
            guard let lat = d.number("lat"), let lon = d.number("lon"), abs(lat) <= 90, abs(lon) <= 180,
                  !d.string("hex").isEmpty, let age = d.number("seen_pos"), age <= 60 else { return nil }
            return Position(hex: d.string("hex").lowercased(), callsign: d.string("flight").trimmingCharacters(in: .whitespaces), registration: d.string("r"), type: d.string("t"), latitude: lat, longitude: lon, altitude: d.number("alt_baro"), speed: d.number("gs"), heading: d.number("track") ?? 0, verticalRate: d.number("baro_rate"), squawk: d.string("squawk"), observed: feedTime.addingTimeInterval(-max(0, age)), onGround: d.string("alt_baro") == "ground")
        }
    }
    static func messages(_ data: Data) throws -> [RadioMessage] {
        try objects(data).compactMap { d in
            guard !d.string("id").isEmpty, let timestamp = date(d.string("timestamp")) ?? date(d.string("createdAt")) else { return nil }
            let af = d.object("airframe")
            let hex = af.string("icao").isEmpty ? d.string("fromHex") : af.string("icao")
            return RadioMessage(id: d.string("id"), timestamp: timestamp, hex: hex.lowercased(), tail: d.string("tail"), flight: d.string("flightNumber"), label: d.string("label"), text: d.string("text").isEmpty ? d.string("data") : d.string("text"), sourceType: d.string("sourceType"), frequency: d.string("frequency"), station: d.object("station").string("ident"), direction: d.string("linkDirection"), flightID: d.object("flight").string("id").isEmpty ? nil : d.object("flight").string("id"))
        }
    }
    static func airframe(_ data: Data) throws -> (Aircraft, String) {
        guard !data.isEmpty else { throw FeedError.notFound }
        guard let d = try JSONSerialization.jsonObject(with: data) as? [String: Any], !d.string("id").isEmpty else { throw FeedError.notFound }
        return (Aircraft(hex: d.string("icao").lowercased(), registration: d.string("tail"), type: d.string("icaoType"), description: d.string("description").isEmpty ? d.string("manufacturerModel") : d.string("description"), owner: d.string("owner").isEmpty ? d.object("airline").string("name") : d.string("owner")), d.string("id"))
    }
    static func flights(_ data: Data) throws -> [HistoricFlight] {
        let d = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return (d["flights"] as? [[String: Any]] ?? []).map { f in
            HistoricFlight(id: f.string("id"), callsign: f.string("flight"), departure: f.string("departingAirport"), destination: f.string("destinationAirport"), status: f.string("status"), date: f.string("departureTimeActual").isEmpty ? f.string("createdAt") : f.string("departureTimeActual"))
        }.sorted { (date($0.date) ?? .distantPast) > (date($1.date) ?? .distantPast) }
    }
}
enum FeedError: LocalizedError {
    case http(Int, String), invalidResponse, notFound
    var errorDescription: String? {
        switch self {
        case let .http(code, retry):
            if code == 429 { return "Rate limited. \(retry.isEmpty ? "Please wait before refreshing." : "Retry after \(retry) seconds.")" }
            if code == 401 || code == 403 { return "Access denied (\(code)). Add a valid Airframes API key in Settings." }
            return "The data provider returned HTTP \(code)."
        case .invalidResponse: return "The provider returned an unsupported response."
        case .notFound: return "No Airframes record was found for this aircraft."
        }
    }
}
