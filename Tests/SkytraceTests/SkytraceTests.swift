import XCTest
@testable import Skytrace

final class FeedParserTests: XCTestCase {
    func testADSBAgeAltitudeAndIdentity() throws {
        let data = Data(#"{"now":1700000000000,"ac":[{"hex":"ABC123","flight":"SIA123  ","r":"9V-ABC","t":"A359","lat":1.3,"lon":104.0,"seen_pos":4,"alt_baro":35000,"gs":450,"track":90},{"hex":"aaa001","lat":1,"lon":2,"seen_pos":80},{"hex":"aaa002","lat":1},{"hex":"aaa003","lat":200,"lon":2,"seen_pos":0},{"hex":"aaa004","lat":1,"lon":2,"seen_pos":0,"alt_baro":"ground"}]}"#.utf8)
        let result = try FeedParser.positions(data)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].hex, "abc123")
        XCTAssertEqual(result[0].callsign, "SIA123")
        XCTAssertEqual(result[0].altitude, 35000)
        XCTAssertEqual(result[0].observed.timeIntervalSince1970, 1699999996)
        XCTAssertTrue(result[1].onGround)
        XCTAssertNil(result[1].altitude)
    }
    func testACARSNumericFrequencyNullFieldsAndArchiveTimeFallback() throws {
        let data = Data(#"[{"id":7990199279,"timestamp":null,"createdAt":"2026-11-01T23:22:12.588Z","airframe":{"icao":"A72B6B"},"tail":"N561JB","flightNumber":"B60369","sourceType":"vdl","label":"BA","frequency":136.8,"text":"/USADCXA.AT1.N561JB","station":{"ident":"PHL"},"flight":{"id":5556595201}}]"#.utf8)
        let message = try XCTUnwrap(FeedParser.messages(data).first)
        XCTAssertEqual(message.id, "7990199279")
        XCTAssertEqual(message.hex, "a72b6b")
        XCTAssertEqual(message.frequency, "136.8")
        XCTAssertEqual(message.flightID, "5556595201")
        XCTAssertEqual(message.station, "PHL")
    }
    func testInvalidPayloadIsAnErrorNotAnEmptyFeed() {
        XCTAssertThrowsError(try FeedParser.positions(Data(#"{"error":"unavailable"}"#.utf8)))
        XCTAssertThrowsError(try FeedParser.messages(Data(#"{"error":"unavailable"}"#.utf8)))
    }
    func testAirframeAndHistory() throws {
        let data = Data(#"{"id":123,"icao":"76B459","tail":"9V-MBY","owner":null,"airline":{"name":"Singapore Airlines"},"flights":[{"id":444,"flight":"SQ123","departingAirport":"WSSS","destinationAirport":"EGLL","status":"arrived","createdAt":"2026-11-01T10:00:00Z"}]}"#.utf8)
        let (aircraft, id) = try FeedParser.airframe(data)
        XCTAssertEqual(id, "123"); XCTAssertEqual(aircraft.owner, "Singapore Airlines")
        let flights = try FeedParser.flights(data)
        XCTAssertEqual(flights.first?.destination, "EGLL")
    }
    func testEncodedQueryAndStableVersion() {
        let url = FeedClient().url("messages", query: [.init(name: "icao", value: "a&b"), .init(name: "limit", value: "100")])
        XCTAssertEqual(url.path, "/v1/messages")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "a&b")
    }
}

final class DatabaseTests: XCTestCase {
    var folder: URL!
    var catalog: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Use the actual bundled catalog, so its schema and indexes are verified too.
        catalog = try XCTUnwrap(Database.bundledCatalog)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }
    func db() throws -> Database { try Database(catalogURL: catalog, personalURL: folder.appendingPathComponent("personal.sqlite")) }
    func testCatalogSearchAndLiteralWildcards() async throws {
        let db = try db()
        let count = try await db.count(); XCTAssertGreaterThan(count, 600000)
        let lookup = try await db.lookup("76b459"); XCTAssertEqual(lookup?.registration, "9V-MBY")
        let results = try await db.search("9V-MB"); XCTAssertTrue(results.contains { $0.hex == "76b459" })
        let escaped = try await db.search("%'; DROP TABLE aircraft;--"); XCTAssertTrue(escaped.isEmpty)
        let again = try await db.count(); XCTAssertEqual(again, count)
    }
    func testObservationsDeduplicateAndPersist() async throws {
        let db = try db()
        let p = Position(hex: "abc123", callsign: "TEST1", registration: "", type: "", latitude: 1.2, longitude: 103.5, heading: 45, squawk: "", observed: Date(), onGround: false)
        try await db.save(positions: [p, p])
        let first = try await db.track("abc123"); XCTAssertEqual(first.count, 1); XCTAssertNil(first[0].altitude)
        let reopened = try self.db()
        let persisted = try await reopened.track("abc123"); XCTAssertEqual(persisted.count, 1); XCTAssertEqual(persisted[0].callsign, "TEST1")
        let different = try await db.track("abc124"); XCTAssertTrue(different.isEmpty)
    }
    func testMessageUpsertWatchlistAndRetention() async throws {
        let db = try db()
        let m = RadioMessage(id: "123", timestamp: Date().addingTimeInterval(-100*86400), hex: "abc123", tail: "N1", flight: "TEST", label: "H1", text: "A \"quoted\"\nmessage", sourceType: "acars", frequency: "131.55", station: "TEST", direction: "downlink")
        try await db.save(messages: [m, m])
        let messages = try await db.messages(); XCTAssertEqual(messages.count, 1); XCTAssertEqual(messages[0].text, m.text)
        try await db.setWatch("abc123", on: true)
        let watches = try await db.watches(); XCTAssertEqual(watches, ["abc123"])
        try await db.setWatch("abc123", on: false)
        let empty = try await db.watches(); XCTAssertTrue(empty.isEmpty)
        try await db.prune(days: 90)
        let pruned = try await db.messages(); XCTAssertTrue(pruned.isEmpty)
    }
}

private final class MockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, headers, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class FeedClientTests: XCTestCase {
    var session: URLSession!
    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        session = URLSession(configuration: config)
    }
    override func tearDown() { session.invalidateAndCancel(); MockProtocol.handler = nil }
    func testAirframesHexNormalizedAndAPIKeySent() async throws {
        var paths: [String] = []
        MockProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-KEY"), "test-key")
            paths.append(request.url!.path)
            return (200, [:], Data(#"{"id":123,"icao":"ABC123","tail":"N1","flights":[]}"#.utf8))
        }
        let result = try await FeedClient(apiKey: "test-key", session: session).airframe(hex: "abc123")
        XCTAssertEqual(result.aircraft.hex, "abc123")
        XCTAssertEqual(paths, ["/v1/airframes/icao/ABC123", "/v1/airframes/123"])
    }
    func testMessageFilterCanonicalHexAndCursor() async throws {
        MockProtocol.handler = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "icao" }?.value, "ABC123")
            XCTAssertEqual(query.first { $0.name == "before_id" }?.value, "7990000000")
            return (200, [:], Data("[]".utf8))
        }
        let result = try await FeedClient(session: session).messages(hex: "abc123", before: "7990000000")
        XCTAssertTrue(result.isEmpty)
    }
    func testRateLimitPreservesRetryAfter() async throws {
        MockProtocol.handler = { _ in (429, ["Retry-After": "120"], Data()) }
        do { _ = try await FeedClient(session: session).messages(); XCTFail("Should throw on HTTP 429") }
        catch FeedError.http(let code, let retry) { XCTAssertEqual(code, 429); XCTAssertEqual(retry, "120") }
    }
    func testEmptyAirframeIsNotFound() {
        XCTAssertThrowsError(try FeedParser.airframe(Data())) { error in
            guard case FeedError.notFound = error else { return XCTFail("Expected not found, got \(error)") }
        }
    }
}
