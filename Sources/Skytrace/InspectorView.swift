import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = "Overview"
    var body: some View {
        if let aircraft = model.selected {
            VStack(spacing: 0) {
                HStack {
                    Text("AIRCRAFT DETAILS").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Palette.muted)
                    Spacer()
                    Button { model.closeInspector() } label: { Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(Palette.muted) }.buttonStyle(.plain)
                }.padding(19)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(model.selectedPosition?.title ?? aircraft.title).font(.system(size: 25, weight: .semibold, design: .monospaced)).tracking(-0.8)
                                Text(aircraft.registration.isEmpty ? aircraft.hex.uppercased() : aircraft.registration).font(.system(size: 12)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Button { model.toggleWatch(aircraft.hex) } label: {
                                Image(systemName: model.watches.contains(aircraft.hex) ? "star.fill" : "star").font(.system(size: 17)).foregroundStyle(Palette.accent)
                            }.buttonStyle(.plain).help("Toggle watchlist")
                        }
                        HStack(spacing: 7) {
                            if !aircraft.type.isEmpty { Tag(text: aircraft.type) }
                            if let p = model.selectedPosition {
                                Tag(text: Date().timeIntervalSince(p.observed) > 60 ? "STALE POSITION" : p.onGround ? "ON GROUND" : "AIRBORNE", color: Date().timeIntervalSince(p.observed) > 60 ? .orange : Palette.blue)
                            } else { Tag(text: "NO LOCAL LIVE POSITION", color: Palette.muted) }
                        }
                        if !aircraft.description.isEmpty { Text(aircraft.description).font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true) }
                        if !aircraft.owner.isEmpty { Text(aircraft.owner).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true) }
                        Picker("Details", selection: $tab) { Text("Overview").tag("Overview"); Text("History").tag("History"); Text("ACARS").tag("ACARS") }.pickerStyle(.segmented).labelsHidden()
                        if tab == "Overview" { overview(aircraft) }
                        else if tab == "History" { history }
                        else { radio }
                        if model.detailBusy { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Loading Airframes records…").font(.system(size: 10)).foregroundStyle(Palette.muted) } }
                        if let error = model.detailError { Notice(text: error, warning: true).clipShape(RoundedRectangle(cornerRadius: 6)) }
                        Button { model.select(aircraft) } label: { Label("Reload aircraft details", systemImage: "arrow.clockwise") }.font(.system(size: 10)).disabled(model.detailBusy)
                        Text("Catalog: Mictronics / tar1090-db\nLive positions: adsb.lol\nMessages & flight history: Airframes.io").font(.system(size: 9)).foregroundStyle(Palette.muted).lineSpacing(5)
                    }.padding(.horizontal, 19).padding(.bottom, 24)
                }
            }.background(Palette.sidebar)
            .onChange(of: aircraft.hex) { _, _ in tab = "Overview" }
        }
    }
    private func overview(_ aircraft: Aircraft) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let p = model.selectedPosition {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 18) {
                    metric("ALTITUDE", p.onGround ? "Ground" : valueString(p.altitude, suffix: " ft"))
                    metric("GROUND SPEED", valueString(p.speed, suffix: " kt"))
                    metric("HEADING", valueString(p.heading, suffix: "°"))
                    metric("VERTICAL RATE", valueString(p.verticalRate, suffix: " ft/m"))
                }.padding(16).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                detail("Position", String(format: "%.4f, %.4f", p.latitude, p.longitude))
                detail("Squawk", p.squawk.isEmpty ? "—" : p.squawk)
                detail("Observed", p.observed.formatted(date: .omitted, time: .standard))
                Button { model.focusSelected() } label: { Label("Locate on radar", systemImage: "scope").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            detail("ICAO hex", aircraft.hex.uppercased())
            detail("Registration", aircraft.registration.isEmpty ? "Unknown" : aircraft.registration)
            detail("Aircraft type", aircraft.type.isEmpty ? "Unknown" : aircraft.type)
            detail("Build year", aircraft.year.isEmpty ? "Not supplied" : aircraft.year)
            detail("Saved track", "\(model.track.count.formatted()) points")
            Text("Aircraft details can be missing or out of date in community records.").font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("SAVED OBSERVATIONS").font(.system(size: 9, weight: .semibold)).tracking(1.1).foregroundStyle(Palette.muted)
            if let first = model.track.first, let last = model.track.last {
                detail("First shown", first.timestamp.formatted(date: .abbreviated, time: .shortened))
                detail("Latest", last.timestamp.formatted(date: .abbreviated, time: .shortened))
                detail("Positions", "\(model.track.count.formatted())")
                HStack {
                    Button("Show track") { model.focusSelected() }
                    Button("Export CSV") { model.exportTrack() }
                }.font(.system(size: 11))
                Text("Up to 5,000 latest saved positions are shown. Lines connect observations no more than two minutes apart.").font(.system(size: 10)).foregroundStyle(Palette.muted)
            } else { Text("No positions saved for this aircraft yet.").font(.system(size: 11)).foregroundStyle(Palette.muted) }
            Divider().overlay(Palette.line)
            Text("AIRFRAMES FLIGHT HISTORY").font(.system(size: 9, weight: .semibold)).tracking(1.1).foregroundStyle(Palette.muted)
            if model.flights.isEmpty {
                Text(model.detailMessage ?? "Waiting for Airframes history.").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            ForEach(model.flights) { f in
                VStack(alignment: .leading, spacing: 8) {
                    Text(f.callsign.isEmpty ? "Flight \(f.id)" : f.callsign).font(.system(size: 12, weight: .semibold, design: .monospaced))
                    HStack { Text(f.departure.isEmpty ? "Unknown" : f.departure); Image(systemName: "arrow.right"); Text(f.destination.isEmpty ? "Unknown" : f.destination) }.font(.system(size: 11))
                    Text([f.status, FeedParser.date(f.date)?.formatted(date: .abbreviated, time: .shortened) ?? f.date].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 9)).foregroundStyle(Palette.muted)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Palette.panel, in: RoundedRectangle(cornerRadius: 7))
            }
            Text("History reflects provider coverage; it is not a complete ownership or maintenance log.").font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }
    private var radio: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT AIRFRAME MESSAGES").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Palette.muted)
            if model.aircraftMessages.isEmpty { Text("No messages returned for this aircraft.").font(.system(size: 11)).foregroundStyle(Palette.muted) }
            ForEach(model.aircraftMessages) { m in
                VStack(alignment: .leading, spacing: 9) {
                    HStack { Tag(text: m.label.isEmpty ? "—" : m.label); Text(m.sourceType.uppercased()).font(.system(size: 9)).foregroundStyle(Palette.blue); Spacer(); Text(m.timestamp.formatted(date: .omitted, time: .shortened)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted) }
                    Text(m.text.isEmpty ? "No text payload" : m.text).font(.system(size: 10, design: .monospaced)).lineSpacing(4).textSelection(.enabled)
                    Text(m.timestamp.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 9)).foregroundStyle(Palette.muted)
                }.padding(11).background(Palette.panel, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(label).font(.system(size: 8, weight: .medium)).tracking(0.6).foregroundStyle(Palette.muted); Text(value).font(.system(size: 16, weight: .medium, design: .monospaced)) }
    }
    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) { Text(label).foregroundStyle(Palette.muted); Spacer(minLength: 8); Text(value).multilineTextAlignment(.trailing).textSelection(.enabled) }.font(.system(size: 11))
    }
}
