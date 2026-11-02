#if os(macOS)
import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var radius = 200
    @State private var regionName = ""
    @State private var status: String?
    @AppStorage("retention") private var retention = 90
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Settings & data sources").font(.system(size: 22, weight: .semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            Form {
                SwiftUI.Section("Airframes.io") {
                    SecureField("API key", text: $key)
                    HStack {
                        Button("Save key") { do { try model.saveKey(key); status = "API key saved to macOS Keychain." } catch { status = error.localizedDescription } }
                        Button("Test connection") {
                            Task {
                                do { _ = try await FeedClient(apiKey: key.trimmingCharacters(in: .whitespacesAndNewlines)).messages(); status = "Airframes connection succeeded." }
                                catch { status = error.localizedDescription }
                            }
                        }
                        Link("API access", destination: URL(string: "https://docs.airframes.io/api/authentication/")!)
                    }
                    Text("Public endpoints may work without a key. Account permissions and rate limits determine available data. Keys are stored in Keychain.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                SwiftUI.Section("Radar coverage") {
                    TextField("Area name", text: $regionName)
                    TextField("Latitude (−90 to 90)", text: $latitude)
                    TextField("Longitude (−180 to 180)", text: $longitude)
                    Picker("Radius", selection: $radius) { ForEach([25, 50, 100, 200, 250], id: \.self) { Text("\($0) nautical miles").tag($0) } }
                    Button("Apply area") {
                        guard let lat = Double(latitude), let lon = Double(longitude), lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180 else { status = "Enter a latitude from −90 to 90 and a longitude from −180 to 180."; return }
                        model.setRegion(.init(name: regionName.trimmingCharacters(in: .whitespaces).isEmpty ? "Custom area" : regionName, latitude: lat, longitude: lon, radius: radius))
                        status = "Radar area updated."
                    }
                }
                SwiftUI.Section("Local storage") {
                    Picker("Keep observations & messages", selection: $retention) { Text("30 days").tag(30); Text("90 days").tag(90); Text("1 year").tag(365) }
                    Text("Retention is applied on launch. Data is collected only while the app is open. Changing the retention period does not restore expired data.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Button("Open data folder") { NSWorkspace.shared.open(Database.dataDirectory) }
                }
                SwiftUI.Section("Sources & coverage") {
                    Text("Aircraft catalog: \(model.catalogCount.formatted()) records downloaded on \(model.catalogDate). The catalog is a bundled snapshot; rebuild with an updated source to refresh it.").font(.system(size: 11))
                    HStack { Link("Mictronics / tar1090-db", destination: URL(string: "https://github.com/wiedehopf/tar1090-db")!); Link("adsb.lol · ODbL", destination: URL(string: "https://www.adsb.lol/about")!); Link("Airframes", destination: URL(string: "https://docs.airframes.io/api/")!) }.font(.system(size: 11))
                    Text("Receiver coverage varies. Some records lack aircraft details or history. Live ADS-B polls every 10 seconds; recent ACARS polls every 30 seconds.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }.formStyle(.grouped)
            if let status { Text(status).font(.system(size: 11)).foregroundStyle(Palette.accent).textSelection(.enabled) }
        }.padding(24).frame(width: 620, height: 750).background(Palette.background)
        .onAppear { key = model.apiKey; latitude = String(model.region.latitude); longitude = String(model.region.longitude); radius = model.region.radius; regionName = model.region.name }
    }
}

#endif
