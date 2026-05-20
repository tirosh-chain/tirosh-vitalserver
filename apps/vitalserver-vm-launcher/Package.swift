// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VitalServerVMLauncher",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "vitalserver-vm",
            targets: ["VitalServerVMLauncher"]
        ),
        .executable(
            name: "TiroshVitalServerApp",
            targets: ["TiroshVitalServerApp"]
        ),
        .executable(
            name: "TiroshVitalServerInstallerApp",
            targets: ["TiroshVitalServerInstallerApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "VitalServerVMLauncher"
        ),
        .executableTarget(
            name: "TiroshVitalServerApp"
        ),
        .executableTarget(
            name: "TiroshVitalServerInstallerApp"
        )
    ]
)
