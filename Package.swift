// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowserPicker",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BrowserPicker", targets: ["BrowserPicker"])],
    targets: [
        .target(name: "PickerCore"),
        .executableTarget(name: "BrowserPicker", dependencies: ["PickerCore"]),
        .testTarget(name: "PickerCoreTests", dependencies: ["PickerCore"])
    ]
)
