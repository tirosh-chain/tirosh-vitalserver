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
        .target(
            name: "RuntimeCore"
        ),
        .executableTarget(
            name: "RuntimeOrchestrator",
            dependencies: ["RuntimeCore"]
        ),
        .executableTarget(
            name: "ManagerApp",
            dependencies: ["RuntimeCore"]
        ),
        .testTarget(
            name: "RuntimeCoreTests",
            dependencies: ["RuntimeCore"],
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "ManagerAppTests",
            dependencies: ["ManagerApp"]
        )
    ]
)
