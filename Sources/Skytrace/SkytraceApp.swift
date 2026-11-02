import SwiftUI

#if os(macOS)
import AppKit

@main struct SkytraceApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1080, minHeight: 720)
                .task { await model.start() }
        }
        .defaultSize(width: 1480, height: 940)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh feeds") { Task { await model.refresh() } }.keyboardShortcut("r")
                Button(model.paused ? "Resume tracking" : "Pause tracking") { model.paused.toggle() }.keyboardShortcut("p", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) { Button("Settings…") { model.settingsPresented = true }.keyboardShortcut(",") }
        }
    }
}

#endif

enum Palette {
    static let background = Color(red: 0.043, green: 0.063, blue: 0.09)
    static let sidebar = Color(red: 0.063, green: 0.082, blue: 0.114)
    static let panel = Color(red: 0.082, green: 0.106, blue: 0.141)
    static let line = Color.white.opacity(0.085)
    static let muted = Color(red: 0.55, green: 0.61, blue: 0.69)
    static let accent = Color(red: 0.36, green: 0.87, blue: 0.73)
    static let blue = Color(red: 0.4, green: 0.68, blue: 1)
}
#if os(macOS)
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 218)
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                header
                Rectangle().fill(Palette.line).frame(height: 1)
                if let error = model.storageError { Notice(text: "Local storage: " + error, warning: true) }
                HStack(spacing: 0) {
                    Group {
                        switch model.section {
                        case .live: RadarView()
                        case .database: CatalogView()
                        case .messages: MessagesView()
                        case .history: HistoryView()
                        case .watchlist: WatchlistView()
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if model.selected != nil {
                        Rectangle().fill(Palette.line).frame(width: 1)
                        InspectorView().frame(width: 312)
                    }
                }
            }
        }
        .background(Palette.background)
        .tint(Palette.accent)
        .sheet(isPresented: $model.settingsPresented) { SettingsView() }
        .alert("Export", isPresented: Binding(get: { model.exportNotice != nil }, set: { if !$0 { model.exportNotice = nil } })) {
            Button("OK") { model.exportNotice = nil }
        } message: { Text(model.exportNotice ?? "") }
        .onChange(of: model.section) { _, section in
            if section == .history || section == .watchlist { Task { await model.reloadLists() } }
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "airplane").font(.system(size: 22, weight: .semibold)).foregroundStyle(Palette.accent).rotationEffect(.degrees(-25))
                Text("skytrace").font(.system(size: 24, weight: .bold, design: .rounded)).tracking(-0.6)
            }.padding(.top, 44).padding(.horizontal, 24)
            Text("AIRCRAFT INTELLIGENCE").font(.system(size: 9, weight: .medium)).tracking(1.7).foregroundStyle(Palette.muted).padding(.horizontal, 24).padding(.top, 8)
            Text("WORKSPACE").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Palette.muted).padding(.top, 40).padding(.horizontal, 24).padding(.bottom, 12)
            ForEach(Section.allCases) { section in
                Button { model.section = section } label: {
                    HStack(spacing: 11) {
                        Image(systemName: section.icon).font(.system(size: 15)).frame(width: 20)
                        Text(section.rawValue).font(.system(size: 12, weight: model.section == section ? .semibold : .regular))
                        Spacer(minLength: 0)
                        if section == .watchlist && !model.watches.isEmpty { Text("\(model.watches.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted) }
                    }.foregroundStyle(model.section == section ? Palette.accent : Color.white.opacity(0.7))
                        .padding(.horizontal, 13).padding(.vertical, 13)
                        .background(model.section == section ? Palette.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).padding(.horizontal, 11).padding(.vertical, 2)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack { Circle().fill(model.liveError == nil && model.lastLive != nil && !model.paused ? Palette.accent : .orange).frame(width: 6, height: 6); Text(model.paused ? "Tracking paused" : model.liveError != nil ? "Feed unavailable" : model.lastLive == nil ? "Connecting to feeds" : "Tracking connected").font(.system(size: 11)) }
                Text("ADS-B · adsb.lol\nACARS · Airframes.io").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(5)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.panel, in: RoundedRectangle(cornerRadius: 10)).padding(14)
            Button { model.settingsPresented = true } label: {
                Label("Settings & data sources", systemImage: "slider.horizontal.3").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }.buttonStyle(.plain).padding(.horizontal, 24).padding(.bottom, 24)
        }.background(Palette.sidebar)
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.section.rawValue).font(.system(size: 23, weight: .semibold)).tracking(-0.5)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer()
            if model.liveBusy || model.messageBusy { ProgressView().controlSize(.small).padding(.trailing, 8) }
            Text(Date(), style: .date).font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.trailing, 14)
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise").frame(width: 28, height: 28) }.buttonStyle(.bordered).help("Refresh feeds (⌘R)")
        }.padding(.horizontal, 26).padding(.top, 32).padding(.bottom, 20).background(Palette.background)
    }
    private var subtitle: String {
        switch model.section {
        case .live: return "Follow aircraft across the sky."
        case .database: return "\(model.catalogCount.formatted()) airframe records, available offline."
        case .messages: return "Aircraft communications from the Airframes network."
        case .history: return "Observations saved on this Mac."
        case .watchlist: return "Your aircraft, one place."
        }
    }
}
#endif
struct Notice: View {
    var text: String
    var warning = false
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: warning ? "exclamationmark.triangle" : "info.circle")
            Text(text).textSelection(.enabled)
            Spacer(minLength: 0)
        }.font(.system(size: 11)).foregroundStyle(warning ? Color.orange : Palette.muted).padding(12).background(warning ? Color.orange.opacity(0.07) : Palette.panel)
    }
}
struct EmptyViewCard: View {
    var icon: String
    var title: String
    var detail: String
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 32, weight: .light)).foregroundStyle(Palette.accent.opacity(0.65))
            Text(title).font(.system(size: 17, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).frame(maxWidth: 340)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
    }
}
struct SearchField: View {
    var prompt: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.system(size: 12))
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }.buttonStyle(.plain) }
        }.padding(11).background(Palette.panel, in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.line))
    }
}
struct Tag: View {
    var text: String
    var color: Color = Palette.accent
    var body: some View { Text(text).font(.system(size: 9, weight: .semibold, design: .monospaced)).padding(.horizontal, 6).padding(.vertical, 4).foregroundStyle(color).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 4)) }
}
func valueString(_ value: Double?, suffix: String = "") -> String { value.map { "\(Int($0).formatted())\(suffix)" } ?? "—" }
