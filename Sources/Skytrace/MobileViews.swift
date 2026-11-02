#if os(iOS)
import SwiftUI
import MapKit
import UniformTypeIdentifiers

@main struct SkytraceMobileApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            MobileRootView().environmentObject(model).preferredColorScheme(.dark)
                .task { await model.start() }
                .onChange(of: phase) { _, value in
                    model.appActive = value == .active
                    if value == .active { Task { await model.refresh() } }
                }
        }
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
struct MobileRootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        TabView(selection: $model.section) {
            ForEach(Section.allCases) { section in
                NavigationStack {
                    Group {
                        switch section {
                        case .live: MobileRadarView()
                        case .database: MobileCatalogView()
                        case .messages: MobileMessagesView()
                        case .history: MobileSavedView(watchlist: false)
                        case .watchlist: MobileSavedView(watchlist: true)
                        }
                    }
                    .navigationTitle(section == .live ? "Skytrace" : section.rawValue)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { model.settingsPresented = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Settings")
                        }
                        ToolbarItem(placement: .topBarLeading) {
                            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Refresh feeds")
                        }
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if let error = model.storageError { Notice(text: error, warning: true) }
                    }
                }
                .tabItem { Label(tabName(section), systemImage: section.icon) }.tag(section)
            }
        }
        .tint(Palette.accent)
        .sheet(isPresented: $model.settingsPresented) { MobileSettingsView() }
        .sheet(isPresented: $model.inspectorPresented) {
            NavigationStack {
                MobileInspectorView().background(Palette.sidebar)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { model.closeInspector() } }
                        ToolbarItem(placement: .topBarLeading) { Button { model.exportTrack() } label: { Image(systemName: "square.and.arrow.up") }.disabled(model.track.isEmpty).accessibilityLabel("Export saved track") }
                    }
                    .fileExporter(isPresented: $model.exportPresented, document: CSVDocument(text: model.exportContent), contentType: .commaSeparatedText, defaultFilename: model.exportName) { exportResult($0) }
                .alert("Export", isPresented: Binding(get: { model.exportNotice != nil && model.inspectorPresented }, set: { if !$0 { model.exportNotice = nil } })) {
                    Button("OK") { model.exportNotice = nil }
                } message: { Text(model.exportNotice ?? "") }
            }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .fileExporter(isPresented: Binding(get: { model.exportPresented && !model.inspectorPresented }, set: { model.exportPresented = $0 }), document: CSVDocument(text: model.exportContent), contentType: .commaSeparatedText, defaultFilename: model.exportName) { exportResult($0) }
        .alert("Export", isPresented: Binding(get: { model.exportNotice != nil && !model.inspectorPresented }, set: { if !$0 { model.exportNotice = nil } })) { Button("OK") { model.exportNotice = nil } } message: { Text(model.exportNotice ?? "") }
        .onChange(of: model.section) { _, section in
            if section == .history || section == .watchlist { Task { await model.reloadLists() } }
        }
    }
    private func tabName(_ section: Section) -> String {
        switch section { case .live: return "Radar"; case .database: return "Aircraft"; case .messages: return "ACARS"; case .history: return "History"; case .watchlist: return "Watchlist" }
    }
    private func exportResult(_ result: Result<URL, Error>) {
        switch result { case .success: model.exportNotice = "CSV saved."; case .failure(let error): model.exportNotice = error.localizedDescription }
    }
}

struct MobileRadarView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var aircraftList = false
    @State private var pendingPosition: Position?
    @State private var satellite = false
    var filtered: [Position] { model.positions.filter { search.isEmpty || [$0.title, $0.hex, $0.registration, $0.type].joined(separator: " ").localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Menu {
                    ForEach(TrackingRegion.presets) { region in Button(region.name) { model.setRegion(region) } }
                    Button("Custom area…") { model.settingsPresented = true }
                } label: { Label(model.region.name, systemImage: "location.circle") }
                Spacer()
                Text("\(model.positions.count) aircraft").font(.subheadline).foregroundStyle(Palette.muted)
                Button { model.paused.toggle() } label: { Image(systemName: model.paused ? "play.fill" : "pause.fill").frame(width: 32, height: 32) }.accessibilityLabel(model.paused ? "Resume tracking" : "Pause tracking")
            }.padding(.horizontal).padding(.vertical, 5)
            if model.paused { Notice(text: "Automatic tracking paused.") }
            if let error = model.liveError { Notice(text: error + " Displayed positions may be stale.", warning: true) }
            Map(position: $model.mapPosition) {
                MapCircle(center: .init(latitude: model.region.latitude, longitude: model.region.longitude), radius: Double(model.region.radius) * 1852)
                    .foregroundStyle(Palette.accent.opacity(0.03)).stroke(Palette.accent.opacity(0.3), lineWidth: 1)
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    MapPolyline(coordinates: segment.map(\.coordinate)).stroke(Palette.accent, lineWidth: 3)
                }
                ForEach(filtered) { p in
                    Annotation(p.title, coordinate: p.coordinate) {
                        Button { model.selectPosition(p) } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "airplane").font(.system(size: 21, weight: .semibold)).rotationEffect(.degrees(p.heading - 90))
                                Text(p.title).font(.system(size: 9, weight: .bold, design: .monospaced)).padding(4).background(Palette.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
                            }.foregroundStyle(model.selected?.hex == p.hex ? Palette.accent : Palette.blue).padding(5)
                        }.buttonStyle(.plain).accessibilityLabel("\(p.title), \(p.registration)")
                    }.annotationTitles(.hidden)
                }
            }
            .mapStyle(satellite ? .imagery : .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass(); MapScaleView() }
            .overlay(alignment: .bottomTrailing) {
                VStack(spacing: 10) {
                    Button { satellite.toggle() } label: { Image(systemName: satellite ? "map" : "globe.americas").frame(width: 44, height: 44) }.accessibilityLabel("Change map style")
                    Button { model.centerMap() } label: { Image(systemName: "scope").frame(width: 44, height: 44) }.accessibilityLabel("Center tracking area")
                }.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(.trailing, 12).padding(.bottom, 35)
            }
            HStack {
                Button { aircraftList = true } label: { Label("Aircraft list", systemImage: "list.bullet") }
                Spacer()
                if let date = model.lastLive { Text(date, style: .time).font(.caption).foregroundStyle(Palette.muted) }
                Link("adsb.lol", destination: URL(string: "https://www.adsb.lol/about")!).font(.caption)
            }.padding(14).background(Palette.sidebar)
        }.background(Palette.background)
        .sheet(isPresented: $aircraftList, onDismiss: {
            if let position = pendingPosition { pendingPosition = nil; model.selectPosition(position) }
        }) {
            NavigationStack {
                List(filtered) { p in
                    Button { pendingPosition = p; aircraftList = false } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) { Text(p.title).font(.headline.monospaced()); Text([p.registration, p.type].joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            VStack(alignment: .trailing) { Text(p.onGround ? "Ground" : valueString(p.altitude, suffix: " ft")); Text(valueString(p.speed, suffix: " kt")).foregroundStyle(.secondary) }.font(.caption.monospaced())
                        }.padding(.vertical, 6)
                    }
                }.searchable(text: $search, prompt: "Callsign, registration, type")
                    .navigationTitle("Nearby aircraft").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { aircraftList = false } } }
            }.presentationDetents([.medium, .large])
        }
    }
    private var segments: [[TrackPoint]] {
        var result: [[TrackPoint]] = []
        for p in model.track {
            if let previous = result.last?.last, p.timestamp.timeIntervalSince(previous.timestamp) <= 120, abs(p.longitude - previous.longitude) < 180 { result[result.count - 1].append(p) }
            else { result.append([p]) }
        }
        return result.filter { $0.count > 1 }
    }
}

struct MobileAircraftRow: View {
    var aircraft: Aircraft
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "airplane").foregroundStyle(Palette.accent).frame(width: 25)
            VStack(alignment: .leading, spacing: 6) {
                Text(aircraft.title).font(.headline.monospaced())
                Text(aircraft.description.isEmpty ? aircraft.type : aircraft.description).font(.caption).foregroundStyle(.secondary)
                if !aircraft.owner.isEmpty { Text(aircraft.owner).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            Text(aircraft.hex.uppercased()).font(.caption2.monospaced()).foregroundStyle(.secondary)
        }.padding(.vertical, 6).foregroundStyle(.primary)
    }
}
struct MobileCatalogView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            Text("\(model.catalogCount.formatted()) records · Snapshot \(model.catalogDate)").font(.caption).foregroundStyle(Palette.muted).padding(12)
            if model.catalogBusy { ProgressView().padding(8) }
            List {
                ForEach(model.catalog) { aircraft in Button { model.select(aircraft) } label: { MobileAircraftRow(aircraft: aircraft) } }
                if model.catalog.isEmpty && !model.catalogBusy { Text("No matching aircraft. Search by the beginning of a registration, hex, type, owner, or description.").foregroundStyle(.secondary) }
            }.listStyle(.plain)
            HStack {
                Button("Previous") { model.catalogPage -= 1; Task { await model.loadCatalog() } }.disabled(model.catalogPage == 0 || model.catalogBusy)
                Spacer(); Text("Page \(model.catalogPage + 1)").font(.caption.monospaced()); Spacer()
                Button("Next") { model.catalogPage += 1; Task { await model.loadCatalog() } }.disabled(!model.catalogHasMore || model.catalogBusy)
            }.padding()
        }.searchable(text: $model.catalogQuery, prompt: "Registration, hex, type, owner")
            .onChange(of: model.catalogQuery) { _, _ in model.scheduleCatalogSearch() }
    }
}

struct MobileMessagesView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            Picker("Feed", selection: $model.archiveMode) { Text("Recent feed").tag(false); Text("Archive").tag(true) }.pickerStyle(.segmented).padding(.horizontal).padding(.top, 8)
            HStack {
                Picker("Link", selection: $model.messageSource) { ForEach(["All links", "ACARS", "VDL", "HFDL", "SATCOM", "IRIDIUM"], id: \.self) { Text($0) } }
                Spacer()
                Button { model.exportMessages() } label: { Label("Export", systemImage: "square.and.arrow.up") }.disabled(model.visibleMessages.isEmpty)
            }.font(.subheadline).padding(.horizontal)
            if model.archiveMode {
                HStack {
                    DatePicker("Day", selection: $model.archiveDate, in: ...Date(), displayedComponents: .date).labelsHidden()
                    Button("Search") { Task { await model.loadArchive() } }.buttonStyle(.bordered)
                    if model.archiveBusy { ProgressView().controlSize(.small) }
                }.padding(.bottom, 8)
            }
            if let error = model.archiveMode ? model.archiveError : model.acarsError { Notice(text: error, warning: true) }
            List {
                ForEach(model.visibleMessages) { m in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button(m.title.isEmpty ? "Unidentified" : m.title) { model.select(Aircraft(hex: m.hex, registration: m.tail)) }.font(.headline.monospaced()).disabled(m.hex.isEmpty)
                            Spacer(); Tag(text: m.sourceType.uppercased()); Tag(text: m.label)
                        }
                        Text(m.text.isEmpty ? "No text payload" : m.text).font(.footnote.monospaced()).textSelection(.enabled)
                        Text([m.timestamp.formatted(date: .abbreviated, time: .standard), m.station, m.frequency.isEmpty ? "" : m.frequency + " MHz"].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
                if model.visibleMessages.isEmpty { Text(model.messageBusy || model.archiveBusy ? "Receiving messages…" : "No messages. Adjust filters, search a day, or check provider access in Settings.").foregroundStyle(.secondary) }
                if model.archiveMode && !model.archiveExhausted && !model.archiveMessages.isEmpty { Button("Load older messages") { Task { await model.loadArchive(reset: false) } }.disabled(model.archiveBusy) }
                Link("Data: Airframes.io & community feeders", destination: URL(string: "https://airframes.io")!).font(.caption)
            }.listStyle(.plain).refreshable { if model.archiveMode { await model.loadArchive() } else { await model.refreshMessages() } }
        }.searchable(text: $model.messageQuery, prompt: "Flight, tail, label, text")
    }
}
struct MobileSavedView: View {
    @EnvironmentObject var model: AppModel
    var watchlist: Bool
    var body: some View {
        List {
            if watchlist {
                if model.watchAircraft.isEmpty { Text("Add aircraft using the star in their details.").foregroundStyle(.secondary) }
                ForEach(model.watchAircraft) { a in Button { model.select(a) } label: { MobileAircraftRow(aircraft: a) } }
            } else {
                Text("Observations saved on this device while Skytrace is open and active.").font(.caption).foregroundStyle(.secondary)
                ForEach(model.historyRows, id: \.aircraft.hex) { row in
                    Button { model.select(row.aircraft) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            MobileAircraftRow(aircraft: row.aircraft)
                            Text("\(row.count) observations · \(row.last.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.listStyle(.plain).refreshable { await model.reloadLists() }.task { await model.reloadLists() }
    }
}
struct MobileSettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var name = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var radius = 200
    @State private var status: String?
    @AppStorage("retention") private var retention = 90
    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section("Airframes") {
                    SecureField("API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save key to Keychain") { do { try model.saveKey(key); status = "API key saved." } catch { status = error.localizedDescription } }
                    Button("Test connection") { Task { do { _ = try await FeedClient(apiKey: key.trimmingCharacters(in: .whitespacesAndNewlines)).messages(); status = "Connected to Airframes." } catch { status = error.localizedDescription } } }
                    Link("API access & authentication", destination: URL(string: "https://docs.airframes.io/api/authentication/")!)
                }
                SwiftUI.Section("Radar area") {
                    TextField("Area name", text: $name)
                    TextField("Latitude, −90 to 90", text: $latitude).keyboardType(.numbersAndPunctuation)
                    TextField("Longitude, −180 to 180", text: $longitude).keyboardType(.numbersAndPunctuation)
                    Picker("Radius", selection: $radius) { ForEach([25, 50, 100, 200, 250], id: \.self) { Text("\($0) NM").tag($0) } }
                    Button("Apply area") {
                        guard let lat = Double(latitude), let lon = Double(longitude), lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180 else { status = "Enter valid latitude and longitude coordinates."; return }
                        model.setRegion(.init(name: name.isEmpty ? "Custom area" : name, latitude: lat, longitude: lon, radius: radius)); status = "Radar area updated."
                    }
                }
                SwiftUI.Section("Storage") {
                    Picker("Retention", selection: $retention) { Text("30 days").tag(30); Text("90 days").tag(90); Text("1 year").tag(365) }
                    Text("Expired observations and messages are removed on launch. Data stays on this device; it does not sync to your Mac. Tracking pauses when the app is in the background.").font(.caption).foregroundStyle(.secondary)
                }
                SwiftUI.Section("Data sources") {
                    Text("\(model.catalogCount.formatted()) aircraft records · \(model.catalogDate)")
                    Link("Aircraft: Mictronics / tar1090-db", destination: URL(string: "https://github.com/wiedehopf/tar1090-db")!)
                    Link("Live positions: adsb.lol · ODbL", destination: URL(string: "https://www.adsb.lol/about")!)
                    Link("Messages & flight history: Airframes", destination: URL(string: "https://docs.airframes.io/api/")!)
                    Text("The catalog and provider history can have missing or outdated records. No complete lifetime history is bundled.").font(.caption).foregroundStyle(.secondary)
                }
                if let status { SwiftUI.Section { Text(status).font(.footnote).textSelection(.enabled) } }
            }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.onAppear { key = model.apiKey; name = model.region.name; latitude = String(model.region.latitude); longitude = String(model.region.longitude); radius = model.region.radius }
    }
}
struct MobileInspectorView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = "Overview"
    var body: some View {
        List {
            if let a = model.selected {
                SwiftUI.Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.selectedPosition?.title ?? a.title).font(.title2.bold().monospaced())
                            Text(a.description.isEmpty ? a.type : a.description).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { model.toggleWatch(a.hex) } label: { Image(systemName: model.watches.contains(a.hex) ? "star.fill" : "star").font(.title2).frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel("Toggle watchlist")
                    }
                    Picker("Details", selection: $tab) { ForEach(["Overview", "History", "ACARS"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                }
                if tab == "Overview" {
                    SwiftUI.Section("Aircraft") {
                        LabeledContent("Registration", value: a.registration.isEmpty ? "Unknown" : a.registration)
                        LabeledContent("ICAO hex", value: a.hex.uppercased())
                        LabeledContent("Type", value: a.type.isEmpty ? "Unknown" : a.type)
                        LabeledContent("Build year", value: a.year.isEmpty ? "Not supplied" : a.year)
                        if !a.owner.isEmpty { LabeledContent("Owner", value: a.owner) }
                    }
                    if let p = model.selectedPosition {
                        SwiftUI.Section("Live position") {
                            if Date().timeIntervalSince(p.observed) > 60 { Text("This position may be stale.").foregroundStyle(.orange) }
                            LabeledContent("Altitude", value: p.onGround ? "Ground" : valueString(p.altitude, suffix: " ft"))
                            LabeledContent("Ground speed", value: valueString(p.speed, suffix: " kt"))
                            LabeledContent("Heading", value: valueString(p.heading, suffix: "°"))
                            LabeledContent("Vertical rate", value: valueString(p.verticalRate, suffix: " ft/m"))
                            LabeledContent("Squawk", value: p.squawk)
                            LabeledContent("Observed", value: p.observed.formatted(date: .omitted, time: .standard))
                            Button("Locate on radar") { model.focusSelected() }
                        }
                    }
                } else if tab == "History" {
                    SwiftUI.Section("Saved observations") {
                        Text("\(model.track.count.formatted()) positions saved on this device")
                        if let first = model.track.first, let last = model.track.last {
                            LabeledContent("First shown", value: first.timestamp.formatted(date: .abbreviated, time: .shortened))
                            LabeledContent("Latest", value: last.timestamp.formatted(date: .abbreviated, time: .shortened))
                            Button("Show track") { model.focusSelected() }
                            Button("Export track CSV") { model.exportTrack() }
                        }
                    }
                    SwiftUI.Section("Airframes flight history") {
                        ForEach(model.flights) { f in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(f.callsign.isEmpty ? "Flight \(f.id)" : f.callsign).font(.headline)
                                Text("\(f.departure.isEmpty ? "Unknown" : f.departure) → \(f.destination.isEmpty ? "Unknown" : f.destination)")
                                Text([f.status, FeedParser.date(f.date)?.formatted(date: .abbreviated, time: .shortened) ?? f.date].joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if model.flights.isEmpty { Text(model.detailMessage ?? "No flights returned.").foregroundStyle(.secondary) }
                    }
                } else {
                    SwiftUI.Section("Recent airframe messages") {
                        ForEach(model.aircraftMessages) { m in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(m.sourceType.uppercased()) · \(m.label) · \(m.timestamp.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                                Text(m.text.isEmpty ? "No text payload" : m.text).font(.footnote.monospaced()).textSelection(.enabled)
                            }.padding(.vertical, 4)
                        }
                        if model.aircraftMessages.isEmpty { Text("No messages returned.").foregroundStyle(.secondary) }
                    }
                }
                SwiftUI.Section {
                    if model.detailBusy { ProgressView("Loading Airframes records…") }
                    if let error = model.detailError { Text(error).font(.footnote).foregroundStyle(.orange) }
                    Button("Reload aircraft details") { model.select(a) }.disabled(model.detailBusy)
                    Text("Aircraft: Mictronics / tar1090-db. Positions: adsb.lol. Messages and flight history: Airframes.io and community feeders. Coverage may be incomplete.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("Aircraft details").navigationBarTitleDisplayMode(.inline)
    }
}
#endif
