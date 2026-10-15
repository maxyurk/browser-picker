// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowserPicker",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BrowserPicker", targets: ["BrowserPicker"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "PickerCore"),
        .executableTarget(name: "BrowserPicker", dependencies: ["PickerCore", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [
            .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
        ]),
        .testTarget(name: "PickerCoreTests", dependencies: ["PickerCore"])
    ]
)
