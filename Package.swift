// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LidSwitch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LidSwitch", targets: ["LidSwitch"])
    ],
    targets: [
        .target(
            name: "CLidSwitch",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-Wall", "-Wextra", "-Werror"])
            ],
            linkerSettings: [
                .linkedFramework("CoreGraphics")
            ]
        ),
        .target(name: "LidSwitchCore"),
        .executableTarget(
            name: "LidSwitch",
            dependencies: ["CLidSwitch", "LidSwitchCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "LidSwitchCoreTests",
            dependencies: ["LidSwitchCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
