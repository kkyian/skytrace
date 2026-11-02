import Foundation
import CSQLite

private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
private final class SQLite {
    var handle: OpaquePointer?
    init(_ path: String, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE
        guard sqlite3_open_v2(path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw CocoaError(.fileReadUnknown) }
        sqlite3_busy_timeout(handle, 5000)
    }
    deinit { sqlite3_close(handle) }
    func run(_ sql: String, _ values: [String] = []) throws {
        let s = try statement(sql, values); defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_DONE else { throw error() }
    }
    func statement(_ sql: String, _ values: [String] = []) throws -> OpaquePointer {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &s, nil) == SQLITE_OK, let s else { throw error() }
        for (i, value) in values.enumerated() { sqlite3_bind_text(s, Int32(i + 1), value, -1, transient) }
        return s
    }
    func rows(_ sql: String, _ values: [String] = []) throws -> [[String]] {
        let s = try statement(sql, values); defer { sqlite3_finalize(s) }
        var rows: [[String]] = []
        var status = sqlite3_step(s)
        while status == SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(s)).map { i in
                sqlite3_column_text(s, i).map { String(cString: $0) } ?? ""
            })
            status = sqlite3_step(s)
        }
        guard status == SQLITE_DONE else { throw error() }
        return rows
    }
    func error() -> NSError { NSError(domain: "SQLite", code: Int(sqlite3_errcode(handle)), userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle))]) }
}

actor Database {
    private let catalog: SQLite
    private let personal: SQLite
    static var bundledCatalog: URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "catalog", withExtension: "sqlite")
        #else
        return Bundle.main.url(forResource: "catalog", withExtension: "sqlite")
        #endif
    }
    static var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Skytrace", isDirectory: true)
    }
    init(catalogURL: URL, personalURL: URL) throws {
        try FileManager.default.createDirectory(at: personalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        catalog = try SQLite(catalogURL.path, readOnly: true)
        personal = try SQLite(personalURL.path)
        _ = try personal.rows("PRAGMA journal_mode=WAL")
        try personal.run("CREATE TABLE IF NOT EXISTS observations(hex TEXT NOT NULL,time REAL NOT NULL,lat REAL,lon REAL,alt REAL,callsign TEXT,PRIMARY KEY(hex,time))")
        try personal.run("CREATE INDEX IF NOT EXISTS observations_time ON observations(time)")
        try personal.run("CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY,time REAL NOT NULL,hex TEXT,body BLOB)")
        try personal.run("CREATE INDEX IF NOT EXISTS messages_time ON messages(time)")
        try personal.run("CREATE TABLE IF NOT EXISTS watchlist(hex TEXT PRIMARY KEY)")
    }
    func snapshotDate() throws -> String { try catalog.rows("SELECT value FROM metadata WHERE key='downloaded'").first?.first ?? "Unknown" }
    func count() throws -> Int { Int(try catalog.rows("SELECT COUNT(*) FROM aircraft")[0][0]) ?? 0 }
    private func aircraft(_ r: [String]) -> Aircraft { Aircraft(hex: r[0].lowercased(), registration: r[1], type: r[2], flags: r[3], description: r[4], year: r[5], owner: r[6]) }
    func lookup(_ hex: String) throws -> Aircraft? {
        try catalog.rows("SELECT * FROM aircraft WHERE hex=?", [hex.uppercased()]).first.map(aircraft)
    }
    func search(_ term: String, offset: Int = 0) throws -> [Aircraft] {
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            .replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
        if q.isEmpty { return try catalog.rows("SELECT * FROM aircraft ORDER BY hex LIMIT 101 OFFSET ?", [String(offset)]).map(aircraft) }
        let predicate = ["hex", "registration", "type", "owner", "description"].map { "\($0) LIKE ? ESCAPE '\\'" }.joined(separator: " OR ")
        return try catalog.rows("SELECT * FROM aircraft WHERE \(predicate) ORDER BY hex LIMIT 101 OFFSET ?", Array(repeating: q + "%", count: 5) + [String(offset)]).map(aircraft)
    }
    func save(positions: [Position]) throws {
        try personal.run("BEGIN IMMEDIATE")
        do {
            let s = try personal.statement("INSERT OR IGNORE INTO observations VALUES(?,?,?,?,?,?)")
            defer { sqlite3_finalize(s) }
            for p in positions {
                sqlite3_reset(s); sqlite3_clear_bindings(s)
                sqlite3_bind_text(s, 1, p.hex, -1, transient)
                sqlite3_bind_double(s, 2, p.observed.timeIntervalSince1970)
                sqlite3_bind_double(s, 3, p.latitude); sqlite3_bind_double(s, 4, p.longitude)
                if let alt = p.altitude { sqlite3_bind_double(s, 5, alt) } else { sqlite3_bind_null(s, 5) }
                sqlite3_bind_text(s, 6, p.callsign, -1, transient)
                guard sqlite3_step(s) == SQLITE_DONE else { throw personal.error() }
            }
            try personal.run("COMMIT")
        } catch { try? personal.run("ROLLBACK"); throw error }
    }
    func track(_ hex: String, since: Date = Date().addingTimeInterval(-86400)) throws -> [TrackPoint] {
        try personal.rows("SELECT time,lat,lon,alt,callsign FROM (SELECT * FROM observations WHERE hex=? AND time>=? ORDER BY time DESC LIMIT 5000) ORDER BY time", [hex, String(since.timeIntervalSince1970)]).compactMap { r in
            guard let time = Double(r[0]), let lat = Double(r[1]), let lon = Double(r[2]) else { return nil }
            return TrackPoint(timestamp: Date(timeIntervalSince1970: time), latitude: lat, longitude: lon, altitude: Double(r[3]), callsign: r[4])
        }
    }
    func save(messages: [RadioMessage]) throws {
        try personal.run("BEGIN IMMEDIATE")
        do {
            let encoder = JSONEncoder()
            for m in messages {
                let body = String(decoding: try encoder.encode(m), as: UTF8.self)
                try personal.run("INSERT OR REPLACE INTO messages VALUES(?,?,?,?)", [m.id, String(m.timestamp.timeIntervalSince1970), m.hex, body])
            }
            try personal.run("COMMIT")
        } catch { try? personal.run("ROLLBACK"); throw error }
    }
    func messages() throws -> [RadioMessage] {
        try personal.rows("SELECT body FROM messages ORDER BY time DESC LIMIT 1000").compactMap { try? JSONDecoder().decode(RadioMessage.self, from: Data($0[0].utf8)) }
    }
    func watches() throws -> Set<String> { Set(try personal.rows("SELECT hex FROM watchlist").map { $0[0] }) }
    func setWatch(_ hex: String, on: Bool) throws {
        if on { try personal.run("INSERT OR IGNORE INTO watchlist VALUES(?)", [hex]) }
        else { try personal.run("DELETE FROM watchlist WHERE hex=?", [hex]) }
    }
    func historyAircraft() throws -> [(String, Int, Date)] {
        try personal.rows("SELECT hex,COUNT(*),MAX(time) FROM observations GROUP BY hex ORDER BY MAX(time) DESC LIMIT 500").compactMap { r in
            guard let n = Int(r[1]), let time = Double(r[2]) else { return nil }
            return (r[0], n, Date(timeIntervalSince1970: time))
        }
    }
    func prune(days: Int) throws {
        let cutoff = String(Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970)
        try personal.run("DELETE FROM observations WHERE time < ?", [cutoff])
        try personal.run("DELETE FROM messages WHERE time < ?", [cutoff])
    }
}
