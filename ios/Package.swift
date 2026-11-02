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
    ],
    targets: [
        .target(
            name: "Essenapp",
            dependencies: ["EssenappShareUI"],
            resources: [.process("Resources")]
        ),
        // Oberfläche der Teilen-Erweiterung; die App nutzt sie für „Link einfügen“ und die Demo-Screenshots (E58).
        .target(name: "EssenappShareUI"),
        // Teilen-Erweiterung (Instagram-Import, Feature 5). Ohne App Group – Login über Kopplungscode (A1).
        // -ObjC: ShareViewController wird nur per Name (Info.plist) geladen; ohne das Flag wirft der Linker
        // den Code weg, die Erweiterung hat kein __text und zsign kann nicht signieren.
        .target(name: "EssenappShare", dependencies: ["EssenappShareUI"], linkerSettings: [.unsafeFlags(["-Xlinker", "-ObjC"])]),
    ]
)
