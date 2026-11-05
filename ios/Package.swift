// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Essenapp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "Essenapp",
            targets: ["Essenapp"]
        ),
        .library(name: "EssenappShare", targets: ["EssenappShare"]),
        .library(name: "EssenappWidget", targets: ["EssenappWidget"]),
    ],
    targets: [
        .target(
            name: "Essenapp",
            dependencies: ["EssenappShareUI"],
            resources: [.process("Resources")]
        ),
        // Oberfläche der Teilen-Erweiterung; die App nutzt sie für „Link einfügen“ und die Demo-Screenshots (E58).
        .target(name: "EssenappShareUI"),
        // Teilen-Erweiterung (Instagram-Import, Feature 5). Anmeldung der App über die App Group (E102).
        // -ObjC: ShareViewController wird nur per Name (Info.plist) geladen; ohne das Flag wirft der Linker
        // den Code weg, die Erweiterung hat kein __text und zsign kann nicht signieren.
        .target(name: "EssenappShare", dependencies: ["EssenappShareUI"], linkerSettings: [.unsafeFlags(["-Xlinker", "-ObjC"])]),
        // Widget „Heute“ + Live-Aktivität (65/37). xtool linkt Erweiterungen mit -e _NSExtensionMain, das ruft das
        // @main-WidgetBundle auf – ohne -u _main wirft der Linker es weg (leere .appex, xtool #313/PR #393, E83).
        .target(name: "EssenappWidget", dependencies: ["EssenappShareUI"], linkerSettings: [.unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_main"])]),
    ]
)
