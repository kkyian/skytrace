import SwiftUI
import MapKit
#if os(macOS)
import AppKit
#endif

enum Section: String, CaseIterable, Identifiable {
    case live = "Live radar", database = "Aircraft database", messages = "ACARS messages", history = "Tracking history", watchlist = "Watchlist"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .live: return "dot.radiowaves.left.and.right"
        case .database: return "airplane.circle"
        case .messages: return "waveform.path"
        case .history: return "clock.arrow.circlepath"
        case .watchlist: return "star"
        }
    }
}

@MainActor final class AppModel: ObservableObject {
    @Published var section: Section = .live
    @Published var positions: [Position] = []
    @Published var messages: [RadioMessage] = []
    @Published var aircraftMessages: [RadioMessage] = []
    @Published var catalog: [Aircraft] = []
    @Published var catalogCount = 0
    @Published var catalogDate = "2026-11-02"
    @Published var catalogQuery = ""
    @Published var catalogPage = 0
    @Published var catalogHasMore = false
    @Published var catalogBusy = false
    @Published var watches: Set<String> = []
    @Published var watchAircraft: [Aircraft] = []
    @Published var historyRows: [(aircraft: Aircraft, count: Int, last: Date)] = []
    @Published var selected: Aircraft?
    @Published var inspectorPresented = false
    @Published var track: [TrackPoint] = []
    @Published var flights: [HistoricFlight] = []
    @Published var detailError: String?
    @Published var detailBusy = false
    @Published var detailMessage: String?
    @Published var liveError: String?
    @Published var acarsError: String?
    @Published var storageError: String?
    @Published var lastLive: Date?
    @Published var lastMessages: Date?
    @Published var liveBusy = false
    @Published var messageBusy = false
    @Published var paused = false
    var appActive = true
    @Published var mapPosition: MapCameraPosition = .region(MKCoordinateRegion(center: .init(latitude: 1.35, longitude: 103.99), span: .init(latitudeDelta: 6, longitudeDelta: 6)))
    @Published var region: TrackingRegion
    @Published var settingsPresented = false
    @Published var apiKey: String = ""
    @Published var messageQuery = ""
    @Published var messageSource = "All links"
    @Published var archiveDate = Date()
    @Published var archiveMode = false
    @Published var archiveMessages: [RadioMessage] = []
    @Published var archiveExhausted = false
    @Published var archiveBusy = false
    @Published var archiveError: String?
    @Published var exportNotice: String?
    #if os(iOS)
    @Published var exportPresented = false
    @Published var exportContent = ""
    @Published var exportName = "Skytrace.csv"
    #endif
    private var database: Database?
    private var refreshTask: Task<Void, Never>?
    private var selectTask: Task<Void, Never>?
    private var catalogTask: Task<Void, Never>?
    private var detailGeneration = UUID()
    private var catalogGeneration = UUID()
    private var liveGeneration = UUID()
    private var archiveGeneration = UUID()
    private var archiveBefore: String?
    private var booted = false
    private var messagesRetryAt = Date.distantPast
    private var liveRetryAt = Date.distantPast
    var client: FeedClient { FeedClient(apiKey: apiKey) }
    var selectedPosition: Position? { positions.first { $0.hex == selected?.hex } }
    var visibleMessages: [RadioMessage] {
        (archiveMode ? archiveMessages : messages).filter { m in
            (messageSource == "All links" || m.sourceType.uppercased() == messageSource) &&
            (messageQuery.isEmpty || [m.flight, m.tail, m.hex, m.text, m.label, m.station].joined(separator: " ").localizedCaseInsensitiveContains(messageQuery))
        }
    }
    init() {
        let d = UserDefaults.standard
        region = TrackingRegion(name: d.string(forKey: "regionName") ?? "Singapore", latitude: d.object(forKey: "latitude") as? Double ?? 1.35, longitude: d.object(forKey: "longitude") as? Double ?? 103.99, radius: d.object(forKey: "radius") as? Int ?? 200)
        mapPosition = .region(MKCoordinateRegion(center: .init(latitude: region.latitude, longitude: region.longitude), span: .init(latitudeDelta: 6, longitudeDelta: 6)))
    }
    func start() async {
        guard !booted else { return }; booted = true
        apiKey = Keychain.read()
        do {
            guard let url = Database.bundledCatalog else { throw CocoaError(.fileNoSuchFile) }
            let db = try Database(catalogURL: url, personalURL: Database.dataDirectory.appendingPathComponent("history.sqlite"))
            database = db
            catalogCount = try await db.count()
            catalogDate = try await db.snapshotDate()
            watches = try await db.watches()
            messages = try await db.messages()
            try await db.prune(days: UserDefaults.standard.object(forKey: "retention") as? Int ?? 90)
            await loadCatalog()
            await reloadLists()
        } catch { storageError = error.localizedDescription }
        await refresh()
        refreshTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                guard let self else { return }
                tick += 1
                if !self.paused && self.appActive {
                    await self.refreshLive()
                    if tick % 3 == 0 { await self.refreshMessages() }
                }
            }
        }
    }
    func refresh() async {
        async let live: () = refreshLive()
        async let radio: () = refreshMessages()
        _ = await (live, radio)
    }
    func refreshLive() async {
        guard !liveBusy, Date() >= liveRetryAt else { return }
        let generation = liveGeneration
        let requestedRegion = region
        liveBusy = true
        defer { liveBusy = false }
        do {
            var data = try await client.positions(region: requestedRegion)
            guard generation == liveGeneration else { return }
            if let db = database {
                for i in data.indices where data[i].registration.isEmpty || data[i].type.isEmpty {
                    if let a = try await db.lookup(data[i].hex) {
                        if data[i].registration.isEmpty { data[i].registration = a.registration }
                        if data[i].type.isEmpty { data[i].type = a.type }
                    }
                }
                guard generation == liveGeneration else { return }
                do { try await db.save(positions: data) } catch { storageError = error.localizedDescription }
            }
            guard generation == liveGeneration else { return }
            positions = data.sorted { $0.title < $1.title }
            lastLive = Date(); liveError = nil
            if let hex = selected?.hex, let db = database {
                let newTrack = try await db.track(hex, since: .distantPast)
                if selected?.hex == hex { track = newTrack }
            }
        } catch {
            guard generation == liveGeneration else { return }
            liveError = error.localizedDescription
            liveRetryAt = retryDate(error)
        }
    }
    func refreshMessages() async {
        guard !messageBusy, Date() >= messagesRetryAt else { return }
        messageBusy = true; defer { messageBusy = false }
        do {
            let data = try await client.messages()
            var indexed = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for m in data { indexed[m.id] = m }
            messages = Array(indexed.values).sorted { $0.timestamp > $1.timestamp }.prefix(1000).map { $0 }
            lastMessages = Date(); acarsError = nil
            do { try await database?.save(messages: data) } catch { storageError = error.localizedDescription }
        } catch { acarsError = error.localizedDescription; messagesRetryAt = retryDate(error) }
    }
    private func retryDate(_ error: Error) -> Date {
        if case let FeedError.http(code, retry) = error, code == 429 {
            return Date().addingTimeInterval(max(60, Double(retry) ?? 60))
        }
        return Date().addingTimeInterval(30)
    }
    func setRegion(_ value: TrackingRegion) {
        region = value; liveGeneration = UUID(); positions = []; lastLive = nil
        let d = UserDefaults.standard
        d.set(value.name, forKey: "regionName"); d.set(value.latitude, forKey: "latitude"); d.set(value.longitude, forKey: "longitude"); d.set(value.radius, forKey: "radius")
        centerMap()
        Task {
            // Let an in-flight request release the refresh lock before starting the new region.
            while liveBusy { try? await Task.sleep(for: .milliseconds(100)); if Task.isCancelled { return } }
            await refreshLive()
        }
    }
    func centerMap() {
        let span = max(0.5, Double(region.radius) / 30)
        mapPosition = .region(MKCoordinateRegion(center: .init(latitude: region.latitude, longitude: region.longitude), span: .init(latitudeDelta: span, longitudeDelta: span)))
    }
    func focusSelected() {
        if let p = selectedPosition {
            mapPosition = .region(MKCoordinateRegion(center: p.coordinate, span: .init(latitudeDelta: 1.5, longitudeDelta: 1.5)))
        } else if let p = track.last {
            mapPosition = .region(MKCoordinateRegion(center: p.coordinate, span: .init(latitudeDelta: 2, longitudeDelta: 2)))
        }
        section = .live
        inspectorPresented = false
    }
    func select(_ aircraft: Aircraft) {
        selectTask?.cancel()
        let generation = UUID(); detailGeneration = generation
        inspectorPresented = true
        selected = aircraft; track = []; flights = []; detailError = nil; detailMessage = nil
        aircraftMessages = messages.filter { $0.hex.caseInsensitiveCompare(aircraft.hex) == .orderedSame }
        detailBusy = true
        selectTask = Task {
            defer { if detailGeneration == generation { detailBusy = false } }
            do {
                if let db = database {
                    let points = try await db.track(aircraft.hex, since: .distantPast)
                    guard detailGeneration == generation, !Task.isCancelled else { return }
                    track = points
                    if let a = try await db.lookup(aircraft.hex) { selected = a }
                }
                async let remote = client.airframe(hex: aircraft.hex)
                async let radio = client.messages(hex: aircraft.hex)
                do {
                    let r = try await remote
                    guard detailGeneration == generation, !Task.isCancelled else { return }
                    if var a = selected {
                        let x = r.aircraft
                        if a.registration.isEmpty { a.registration = x.registration }
                        if a.type.isEmpty { a.type = x.type }
                        if a.description.isEmpty { a.description = x.description }
                        if a.owner.isEmpty { a.owner = x.owner }
                        selected = a
                    }
                    flights = r.flights
                    detailMessage = r.flights.isEmpty ? "Airframes returned no flight history for this airframe." : nil
                } catch {
                    guard detailGeneration == generation, !Task.isCancelled else { return }
                    detailError = error.localizedDescription
                }
                do {
                    let r = try await radio
                    guard detailGeneration == generation, !Task.isCancelled else { return }
                    aircraftMessages = r
                    do { try await database?.save(messages: r) } catch { storageError = error.localizedDescription }
                } catch {
                    guard detailGeneration == generation, !Task.isCancelled else { return }
                    detailError = [detailError, "Messages: " + error.localizedDescription].compactMap { $0 }.joined(separator: "\n")
                }
            } catch {
                if detailGeneration == generation { detailError = error.localizedDescription }
            }
        }
    }
    func selectPosition(_ p: Position) {
        select(Aircraft(hex: p.hex, registration: p.registration, type: p.type))
    }
    func closeInspector() {
        inspectorPresented = false
        selectTask?.cancel(); detailGeneration = UUID(); selected = nil; detailBusy = false; track = []
    }
    func scheduleCatalogSearch() {
        catalogTask?.cancel()
        catalogPage = 0
        catalogTask = Task {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            await loadCatalog()
        }
    }
    func loadCatalog() async {
        let generation = UUID(); catalogGeneration = generation; catalogBusy = true
        let q = catalogQuery; let page = catalogPage
        defer { if generation == catalogGeneration { catalogBusy = false } }
        do {
            let rows = try await database?.search(q, offset: page * 100) ?? []
            guard generation == catalogGeneration, q == catalogQuery, page == catalogPage, !Task.isCancelled else { return }
            catalog = Array(rows.prefix(100)); catalogHasMore = rows.count > 100
        } catch { storageError = error.localizedDescription }
    }
    func toggleWatch(_ hex: String) {
        Task {
            do {
                let on = !watches.contains(hex)
                try await database?.setWatch(hex, on: on)
                if on { watches.insert(hex) } else { watches.remove(hex) }
                await reloadLists()
            } catch { storageError = error.localizedDescription }
        }
    }
    func reloadLists() async {
        guard let db = database else { return }
        do {
            var list: [Aircraft] = []
            for hex in watches.sorted() { list.append(try await db.lookup(hex) ?? Aircraft(hex: hex)) }
            watchAircraft = list
            var history: [(Aircraft, Int, Date)] = []
            for (hex, count, date) in try await db.historyAircraft() { history.append((try await db.lookup(hex) ?? Aircraft(hex: hex), count, date)) }
            historyRows = history
        } catch { storageError = error.localizedDescription }
    }
    func loadArchive(reset: Bool = true) async {
        if archiveBusy && !reset { return }
        if reset { archiveGeneration = UUID(); archiveMessages = []; archiveExhausted = false; archiveBefore = nil }
        let generation = archiveGeneration
        let day = archiveDate
        archiveBusy = true; archiveError = nil
        defer { if generation == archiveGeneration { archiveBusy = false } }
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        do {
            let page = try await client.messages(before: reset ? nil : archiveBefore, since: start, until: end)
            guard generation == archiveGeneration else { return }
            var seen = Set(archiveMessages.map(\.id))
            archiveMessages.append(contentsOf: page.filter { seen.insert($0.id).inserted })
            archiveMessages.sort { $0.timestamp > $1.timestamp }
            archiveBefore = page.map(\.id).min { (Int64($0) ?? 0) < (Int64($1) ?? 0) }
            archiveExhausted = page.count < 100
            try await database?.save(messages: page)
        } catch {
            if generation == archiveGeneration { archiveError = error.localizedDescription }
        }
    }
    func exportMessages() {
        exportCSV(name: "Skytrace-ACARS.csv", header: ["id", "timestamp", "hex", "registration", "flight", "label", "link", "frequency_mhz", "station", "text"], rows: visibleMessages.map { [$0.id, ISO8601DateFormatter().string(from: $0.timestamp), $0.hex, $0.tail, $0.flight, $0.label, $0.sourceType, $0.frequency, $0.station, $0.text] })
    }
    func exportTrack() {
        exportCSV(name: "Skytrace-\(selected?.title ?? "track").csv", header: ["timestamp", "latitude", "longitude", "altitude_ft", "callsign"], rows: track.map { [ISO8601DateFormatter().string(from: $0.timestamp), String($0.latitude), String($0.longitude), $0.altitude.map { String($0) } ?? "", $0.callsign] })
    }
    private func exportCSV(name: String, header: [String], rows: [[String]]) {
        func escape(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let csv = ([header] + rows).map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n")
        #if os(macOS)
        let panel = NSSavePanel(); panel.nameFieldStringValue = name; panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try csv.write(to: url, atomically: true, encoding: .utf8); exportNotice = "Exported \(rows.count) records to \(url.lastPathComponent)." }
        catch { exportNotice = error.localizedDescription }
        #else
        exportName = name; exportContent = csv; exportPresented = true
        #endif
    }

    func saveKey(_ key: String) throws { try Keychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines)); apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines); messagesRetryAt = .distantPast }
}
