// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TypeVoice",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.7"),
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm.git", from: "5.90.0"),
    ],
    targets: [
        .executableTarget(
            name: "TypeVoice",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
            ],
            path: "Sources/TypeVoice",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
