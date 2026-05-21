// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TiroshVitalServerRuntime",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "vitalserver-vm",
            targets: ["RuntimeOrchestrator"]
        ),
        .executable(
            name: "TiroshVitalServerApp",
            targets: ["ManagerApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "RuntimeOrchestrator"
        ),
        .executableTarget(
            name: "ManagerApp"
        )
    ]
)
