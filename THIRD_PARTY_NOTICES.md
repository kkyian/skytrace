# Third-party data and platform notices

The root LICENSE dedicates the original Skytrace application code and build scripts under the Unlicense. It does not change ownership or terms for third-party data, services, software, or system symbols.

## Aircraft metadata

The catalog downloader obtains the aircraft snapshot distributed by [wiedehopf/tar1090-db](https://github.com/wiedehopf/tar1090-db), which credits the database maintained by Mictronics. Upstream contributors retain their rights. The downloaded catalog is generated locally and excluded from Git. Its use or redistribution is not granted by Skytrace's Unlicense. Refer to upstream terms before redistributing it, including inside app binaries.

## ADS-B positions

Live positions come from [adsb.lol](https://www.adsb.lol/about). Its API data is published under ODbL 1.0. Applicable attribution and database-license requirements remain in effect for collected tracks, exports, and derived databases.

## Airframes messages and history

Data is provided by [Airframes.io](https://airframes.io) and its community of feeders. The [API's attribution and licensing terms](https://docs.airframes.io/api/licensing/) and account access limits apply. Bulk redistribution or commercial use beyond an account tier may require an arrangement with Airframes. No ACARS archive, account API key, or private feed is included in this repository.

## Apple platforms and artwork

SwiftUI, MapKit, Security, platform SDKs, and SF Symbols are supplied by Apple under Apple's applicable terms. Map imagery retains Apple's map attribution. The supplied app artwork is generated using an Apple system airplane symbol; the original icon-generation code is under the Unlicense, but Apple's rights and applicable symbol-usage terms are not changed by that license.

## SQLite

The app links to the platform SQLite library; it does not vendor a separate SQLite implementation. The CSQLite shim includes the system sqlite3 header. [SQLite's public-domain notice](https://www.sqlite.org/copyright.html) describes its licensing.
