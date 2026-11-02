#if os(macOS)
import SwiftUI

struct CatalogView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                SearchField(prompt: "Search registration, ICAO hex, aircraft type, owner…", text: $model.catalogQuery)
                if model.catalogBusy { ProgressView().controlSize(.small) }
            }.padding(22)
            Notice(text: "Mictronics / tar1090-db · Snapshot \(model.catalogDate) · Prefix search · Select an aircraft for its records and history.")
            AircraftTable(aircraft: model.catalog)
            HStack {
                Text("\(model.catalogCount.formatted()) records in catalog").foregroundStyle(Palette.muted)
                Spacer()
                Button { model.catalogPage -= 1; Task { await model.loadCatalog() } } label: { Image(systemName: "chevron.left") }.disabled(model.catalogPage == 0 || model.catalogBusy)
                Text("Page \(model.catalogPage + 1)").monospacedDigit().frame(minWidth: 70)
                Button { model.catalogPage += 1; Task { await model.loadCatalog() } } label: { Image(systemName: "chevron.right") }.disabled(!model.catalogHasMore || model.catalogBusy)
            }.font(.system(size: 11)).padding(18)
        }.onChange(of: model.catalogQuery) { _, _ in model.scheduleCatalogSearch() }
    }
}
struct AircraftTable: View {
    @EnvironmentObject var model: AppModel
    var aircraft: [Aircraft]
    @State private var sortOrder = [KeyPathComparator(\Aircraft.registration)]
    var body: some View {
        if aircraft.isEmpty {
            EmptyViewCard(icon: "magnifyingglass", title: "No matching aircraft", detail: "Search by the start of a registration, hex code, type, owner, or description.")
        } else {
            Table(aircraft.sorted(using: sortOrder), selection: Binding(get: { model.selected?.hex }, set: { hex in if let a = aircraft.first(where: { $0.hex == hex }) { model.select(a) } }), sortOrder: $sortOrder) {
                TableColumn("Registration", value: \.registration) { a in
                    HStack(spacing: 8) { Image(systemName: "airplane").foregroundStyle(Palette.accent); Text(a.title).font(.system(size: 12, weight: .semibold, design: .monospaced)) }
                }.width(min: 100, ideal: 120)
                TableColumn("ICAO hex", value: \.hex) { a in Text(a.hex.uppercased()).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted) }.width(80)
                TableColumn("Type", value: \.type) { a in Text(a.type.isEmpty ? "—" : a.type).font(.system(size: 11, design: .monospaced)) }.width(65)
                TableColumn("Aircraft", value: \.description) { a in Text(a.description.isEmpty ? "Unknown" : a.description).font(.system(size: 11)).lineLimit(1) }.width(min: 120, ideal: 200)
                TableColumn("Year", value: \.year) { a in Text(a.year.isEmpty ? "—" : a.year).font(.system(size: 11, design: .monospaced)) }.width(50)
                TableColumn("Owner", value: \.owner) { a in Text(a.owner.isEmpty ? "—" : a.owner).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1) }.width(min: 80, ideal: 160)
            }.alternatingRowBackgrounds().tableStyle(.inset)
        }
    }
}
struct MessagesView: View {
    @EnvironmentObject var model: AppModel
    @State private var expanded: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SearchField(prompt: "Search flight, tail, message text or label…", text: $model.messageQuery)
                Picker("Link", selection: $model.messageSource) {
                    ForEach(["All links", "ACARS", "VDL", "HFDL", "SATCOM", "IRIDIUM"], id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 120)
                Button { model.exportMessages() } label: { Label("Export", systemImage: "square.and.arrow.up") }.disabled(model.visibleMessages.isEmpty)
            }.padding(20)
            HStack(spacing: 12) {
                Picker("Feed", selection: $model.archiveMode) { Text("Recent feed").tag(false); Text("Historical search").tag(true) }.pickerStyle(.segmented).frame(width: 240)
                if model.archiveMode {
                    DatePicker("Day", selection: $model.archiveDate, in: ...Date(), displayedComponents: .date).labelsHidden()
                    Button("Search") { Task { await model.loadArchive() } }
                    if model.archiveBusy { ProgressView().controlSize(.small) }
                } else {
                    Circle().fill(model.paused ? .orange : Palette.accent).frame(width: 5, height: 5)
                    Text(model.paused ? "Auto refresh paused" : "Refreshes every 30 seconds").foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Text("\(model.visibleMessages.count) messages").foregroundStyle(Palette.muted)
            }.font(.system(size: 10)).padding(.horizontal, 22).padding(.bottom, 16)
            if let error = model.archiveMode ? model.archiveError : model.acarsError { Notice(text: error, warning: true) }
            if !model.archiveMode && model.lastMessages == nil && !model.messages.isEmpty { Notice(text: "Showing messages saved on this Mac. Connecting to Airframes…") }
            if model.visibleMessages.isEmpty {
                EmptyViewCard(icon: "waveform.path", title: model.messageBusy || model.archiveBusy ? "Receiving messages" : "No messages to show", detail: model.archiveMode ? "Choose a day and search the Airframes archive. Availability depends on provider access and coverage." : "Messages appear when the feed responds. Adjust your filters or check API access in Settings.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.visibleMessages) { m in
                            MessageCard(message: m, expanded: expanded == m.id) {
                                expanded = expanded == m.id ? nil : m.id
                            }
                        }
                        if model.archiveMode {
                            Button(model.archiveExhausted ? "End of results" : "Load older messages") { Task { await model.loadArchive(reset: false) } }.disabled(model.archiveExhausted || model.archiveBusy).padding(12)
                        }
                    }.padding(20).padding(.top, 0)
                }
            }
            HStack {
                Link("Data: Airframes.io & community feeders", destination: URL(string: "https://airframes.io")!)
                Spacer()
                if let date = model.lastMessages, !model.archiveMode { Text("Last fetched \(date.formatted(date: .omitted, time: .standard))") }
            }.font(.system(size: 9)).foregroundStyle(Palette.muted).padding(13).background(Palette.sidebar)
        }
    }
}
struct MessageCard: View {
    @EnvironmentObject var model: AppModel
    var message: RadioMessage
    var expanded: Bool = true
    var action: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    if !message.hex.isEmpty { model.select(Aircraft(hex: message.hex, registration: message.tail)) }
                } label: { Text(message.title.isEmpty ? "Unidentified" : message.title).font(.system(size: 12, weight: .semibold, design: .monospaced)) }.buttonStyle(.plain).foregroundStyle(Palette.accent).disabled(message.hex.isEmpty)
                Text(message.tail).font(.system(size: 10)).foregroundStyle(Palette.muted)
                Spacer(minLength: 3)
                Tag(text: message.sourceType.uppercased(), color: Palette.blue)
                Tag(text: message.label.isEmpty ? "—" : message.label)
                Text(message.timestamp.formatted(date: .omitted, time: .standard)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
            }
            Text(message.text.isEmpty ? "No text payload" : message.text)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.white.opacity(0.8)).lineSpacing(5)
                .lineLimit(expanded ? nil : 3).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            if expanded {
                HStack(spacing: 8) {
                    Text(message.timestamp.formatted(date: .abbreviated, time: .omitted))
                    Text(message.station)
                    if !message.frequency.isEmpty { Text(message.frequency + " MHz") }
                    if !message.direction.isEmpty { Text(message.direction) }
                }.font(.system(size: 9)).foregroundStyle(Palette.muted)
            }
            if let action { Button(expanded ? "Collapse" : "Details") { action() }.buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(Palette.muted) }
        }.padding(15).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line))
    }
}
struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            Notice(text: "Positions are recorded while Skytrace is running and tracking is active. Retention is configurable in Settings. Aircraft details include any history returned by Airframes.")
            if model.historyRows.isEmpty {
                EmptyViewCard(icon: "clock.arrow.circlepath", title: "Your tracking history starts here", detail: "Keep live tracking running to collect observations. Select an aircraft to inspect or export its saved track.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(model.historyRows, id: \.aircraft.hex) { row in
                            Button { model.select(row.aircraft) } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").foregroundStyle(Palette.accent).frame(width: 26)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(row.aircraft.title).font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        Text(row.aircraft.description.isEmpty ? row.aircraft.type : row.aircraft.description).font(.system(size: 10)).foregroundStyle(Palette.muted)
                                    }
                                    Spacer()
                                    Text("\(row.count.formatted()) observations").font(.system(size: 11)).foregroundStyle(Palette.muted)
                                    Text(row.last.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10, design: .monospaced)).frame(width: 165, alignment: .trailing)
                                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Palette.muted)
                                }.padding(18).background(model.selected?.hex == row.aircraft.hex ? Palette.accent.opacity(0.06) : Palette.panel)
                            }.buttonStyle(.plain)
                        }
                    }.padding(20)
                }
            }
        }
    }
}
struct WatchlistView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            Notice(text: "Select the star in an aircraft’s inspector to save it here. Live availability depends on the selected radar area.")
            if model.watchAircraft.isEmpty {
                EmptyViewCard(icon: "star", title: "Keep an eye on an aircraft", detail: "Open any aircraft on the map or in the database and add it to your watchlist.")
            } else { AircraftTable(aircraft: model.watchAircraft) }
        }
    }
}

#endif
