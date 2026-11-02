// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Skytrace", platforms: [.macOS(.v14), .iOS(.v17)], products: [.executable(name: "Skytrace", targets: ["Skytrace"])], targets: [.systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"), .executableTarget(name: "Skytrace", dependencies: ["CSQLite"], resources: [.copy("Resources/catalog.sqlite")]), .testTarget(name: "SkytraceTests", dependencies: ["Skytrace"])])
