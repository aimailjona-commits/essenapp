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
            resources: [.process("Resources")]
        ),
        // Teilen-Erweiterung (Instagram-Import, Feature 5). Ohne App Group – Login über Kopplungscode (A1).
        .target(name: "EssenappShare"),
    ]
)
