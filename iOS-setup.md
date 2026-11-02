# Skytrace for iPhone and iPad

Skytrace now includes an iOS app target for iOS 17 and later, with a shared codebase for the macOS and iOS apps.

## Run from Xcode

1. Clone the repository, run `python3 scripts/update-catalog.py`, and open `Skytrace-iOS.xcodeproj` in Xcode.
2. Select the **Skytrace-iOS** scheme.
3. For a simulator, choose an installed iPhone or iPad simulator and press Run. If there are no simulator runtimes, install an iOS runtime in Xcode’s platform/components settings.
4. For an iPhone or iPad, connect the device, select it as the run destination, and choose your development team under **Signing & Capabilities**. Change the bundle identifier if your team requires a unique one. Xcode must have a compatible iOS SDK and provisioning support for the device.
5. Run the app. Device installation may also require enabling Developer Mode and trusting the development profile on the device.

No Airframes API key is bundled. Public requests may work without one; enter your own key in the app’s Settings when required by your account’s access tier.

A signed IPA, TestFlight upload, and App Store publication are not included. They require your Apple signing credentials and the relevant distribution setup. The unsigned device build is a compilation check, not an installable download.

## Mobile features

The tab bar contains Radar, Aircraft, ACARS, History, and Watchlist. It works on iPhone and iPad, including iPad multitasking widths.

- **Radar** uses Apple Maps, with region presets, a custom coordinate/radius setting, map style selection, a center-area control, and an aircraft list. Tap an aircraft or its list row to open the details sheet. Automatic ADS-B requests run every 10 seconds while the app is active.
- **Aircraft** searches the same bundled 623,216-record catalog as the Mac app, with 100 results per page. Records and available fields have the same source limitations.
- **ACARS** supports recent messages, local filtering, link-type filters, date-based Airframes archive searches, older result pages, and CSV export using the system Files picker. Recent requests run every 30 seconds while active. Polling does not capture the entire firehose.
- **Aircraft details** show live telemetry, saved observations, available Airframes flight history, recent messages, a watchlist star, and track export. Show track closes the sheet and displays saved observations on the radar. Long observation gaps remain disconnected.
- **History and Watchlist** are saved locally between launches. They are separate from the Mac app’s data and do not sync between devices. Settings stores the API key in the device Keychain.

Automatic polling pauses when the app is inactive or in the background. The app does not request the device’s location and does not record flights while closed. Retention is applied on launch, with the same 30-day, 90-day, and 1-year options as macOS.

## Command-line builds

From the repository root on a Mac with Xcode:

```sh
./scripts/build-ios.sh simulator
./scripts/build-ios.sh device
```

Both scripts disable code signing for compilation checks. Use Xcode’s signing setup for a physical device or distribution. The simulator build supports arm64 and x86_64 simulator architectures; the device release build supports arm64.

The macOS package remains available through `swift test` and `scripts/build-app.sh`. `MobileViews.swift` is compiled only on iOS; desktop views and AppKit exports are compiled only on macOS. Models, provider clients, persistence, catalog, and aircraft selection are shared.

## Validation and remaining checks

The app compiles successfully for the iOS Simulator SDK and the physical iOS device SDK. Twelve shared data, provider, and persistence tests pass on macOS after the platform changes. The bundled catalog, iPhone/iPad device-family settings, and exported resource paths were checked in the build products.

The development build was signed and installed on a physical iPhone. Automatic launch was blocked pending developer trust on that device, so mobile interface flows and device Keychain behavior have not yet been verified at runtime. No simulator runtime was available during validation. The iOS 17 deployment target was compile-checked using the installed iOS 27.2 SDK; older OS versions have not been run. Before distributing the app, run it on your target devices and check map selection, aircraft-list selection, archive pagination, CSV export from both messages and the details sheet, watchlist persistence after relaunch, and background/foreground transitions.

Provider coverage and licensing are unchanged. See the main README for sources, data limitations, and attribution.
