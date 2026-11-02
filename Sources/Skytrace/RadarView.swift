#if os(macOS)
import SwiftUI
import MapKit

struct RadarView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var satellite = false
    @State private var showLabels = true
    var filtered: [Position] {
        model.positions.filter { search.isEmpty || [$0.title, $0.registration, $0.hex, $0.type].joined(separator: " ").localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                HStack(spacing: 7) {
                    Circle().fill(model.paused ? .orange : model.liveError == nil ? Palette.accent : .orange).frame(width: 6, height: 6)
                    Text(model.paused ? "PAUSED" : model.liveError != nil ? "OFFLINE" : model.lastLive == nil ? "CONNECTING" : "LIVE RADAR").font(.system(size: 9, weight: .bold)).tracking(1.3)
                }.foregroundStyle(Palette.accent)
                HStack(spacing: 5) { Text("\(model.positions.count)").fontWeight(.semibold).foregroundStyle(.white); Text("aircraft").foregroundStyle(Palette.muted) }.font(.system(size: 11))
                Spacer()
                Menu {
                    ForEach(TrackingRegion.presets) { r in Button(r.name) { model.setRegion(r) } }
                    Divider()
                    Button("Custom area…") { model.settingsPresented = true }
                } label: { Label(model.region.name, systemImage: "location.circle").font(.system(size: 11)) }.menuStyle(.borderlessButton).fixedSize()
                Text("\(model.region.radius) NM").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                Button { model.paused.toggle() } label: { Image(systemName: model.paused ? "play.fill" : "pause.fill").font(.system(size: 10)) }.buttonStyle(.plain).help("Pause or resume automatic refresh")
            }.padding(.horizontal, 22).padding(.vertical, 15)
            if let e = model.liveError { Notice(text: e + " Last received positions remain visible; they may be stale.", warning: true) }
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    SearchField(prompt: "Callsign, registration, type…", text: $search).padding(12)
                    HStack { Text("AIRCRAFT"); Spacer(); Text("ALT / SPEED") }.font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(Palette.muted).padding(.horizontal, 18).padding(.vertical, 11)
                    Divider().overlay(Palette.line)
                    if filtered.isEmpty {
                        EmptyViewCard(icon: "airplane", title: model.liveBusy ? "Finding aircraft" : "No aircraft", detail: search.isEmpty ? "No recent positions in this area. Try another region or refresh." : "Try another callsign or registration.")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filtered) { p in
                                    Button { model.selectPosition(p) } label: { positionRow(p) }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        if let date = model.lastLive { Text("Updated \(date.formatted(date: .omitted, time: .standard))") } else { Text("Waiting for ADS-B feed") }
                    }.font(.system(size: 9)).foregroundStyle(Palette.muted).padding(12).frame(maxWidth: .infinity).background(Palette.sidebar)
                }.frame(width: 265).background(Palette.background)
                Rectangle().fill(Palette.line).frame(width: 1)
                map
            }
        }
    }
    private func positionRow(_ p: Position) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "airplane").rotationEffect(.degrees(p.heading - 90)).font(.system(size: 13)).foregroundStyle(model.selected?.hex == p.hex ? Palette.accent : Palette.blue).frame(width: 23)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) { Text(p.title).font(.system(size: 12, weight: .semibold, design: .monospaced)); if model.watches.contains(p.hex) { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(Palette.accent) } }
                Text([p.registration, p.type].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 3)
            VStack(alignment: .trailing, spacing: 5) {
                Text(p.onGround ? "GROUND" : valueString(p.altitude, suffix: " ft")).font(.system(size: 10, design: .monospaced))
                Text(valueString(p.speed, suffix: " kt")).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
            }
        }.padding(.horizontal, 15).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
            .background(model.selected?.hex == p.hex ? Palette.accent.opacity(0.07) : .clear)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
    private var map: some View {
        Map(position: $model.mapPosition) {
            MapCircle(center: .init(latitude: model.region.latitude, longitude: model.region.longitude), radius: Double(model.region.radius) * 1852).foregroundStyle(Palette.accent.opacity(0.025)).stroke(Palette.accent.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 6]))
            if !model.track.isEmpty {
                // Split discontinuities so observation gaps never become invented flight paths.
                ForEach(Array(trackSegments.enumerated()), id: \.offset) { _, segment in
                    MapPolyline(coordinates: segment.map(\.coordinate)).stroke(Palette.accent.opacity(0.9), lineWidth: 2.5)
                }
            }
            ForEach(filtered) { p in
                Annotation(p.title, coordinate: p.coordinate, anchor: .center) {
                    Button { model.selectPosition(p) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "airplane").font(.system(size: model.selected?.hex == p.hex ? 23 : 17, weight: .semibold))
                                .rotationEffect(.degrees(p.heading - 90))
                                .foregroundStyle(model.selected?.hex == p.hex ? Palette.accent : Palette.blue)
                                .shadow(color: .black.opacity(0.8), radius: 3)
                            if showLabels {
                                Text(p.title).font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 5).padding(.vertical, 3).foregroundStyle(.white)
                                    .background(Palette.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                            }
                        }.padding(4).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("\(p.title) · \(valueString(p.altitude, suffix: " ft"))")
                }.annotationTitles(.hidden)
            }
        }
        .mapStyle(satellite ? .imagery(elevation: .flat) : .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls { MapCompass(); MapScaleView(); MapZoomStepper() }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 8) {
                Image(systemName: "scope").foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.region.name.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2)
                    Text(String(format: "%.2f°, %.2f° · %d NM", model.region.latitude, model.region.longitude, model.region.radius)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
                }
            }.padding(13).background(Palette.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 8)).padding(16)
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 12) {
                Button { model.centerMap() } label: { Label("Center area", systemImage: "scope") }
                Toggle("Labels", isOn: $showLabels).toggleStyle(.checkbox)
                Toggle("Satellite", isOn: $satellite).toggleStyle(.checkbox)
            }.font(.system(size: 10)).padding(11).background(Palette.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 7)).padding(.leading, 16).padding(.bottom, 32)
        }
    }
    private var trackSegments: [[TrackPoint]] {
        var segments: [[TrackPoint]] = []
        for p in model.track {
            if let previous = segments.last?.last, p.timestamp.timeIntervalSince(previous.timestamp) <= 120, abs(p.longitude - previous.longitude) < 180 {
                segments[segments.count - 1].append(p)
            } else { segments.append([p]) }
        }
        return segments.filter { $0.count > 1 }
    }
}

#endif
