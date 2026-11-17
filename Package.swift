// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MediKas",
    defaultLocalization: "nl",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Automatische updates via GitHub Releases (zie README → Releases).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "MediKas",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/MediKas",
            // Sparkle.framework wordt door build.sh in Contents/Frameworks gezet.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
