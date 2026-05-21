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
        .target(
            name: "RuntimeInfrastructure",
            dependencies: ["RuntimeCore"]
        ),
        .executableTarget(
            name: "RuntimeOrchestrator",
            dependencies: ["RuntimeCore", "RuntimeInfrastructure"]
        ),
        .executableTarget(
            name: "ManagerApp",
            dependencies: ["RuntimeCore", "RuntimeInfrastructure"]
        ),
        .testTarget(
            name: "RuntimeCoreTests",
            dependencies: ["RuntimeCore"],
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "RuntimeInfrastructureTests",
            dependencies: ["RuntimeCore", "RuntimeInfrastructure"]
        ),
        .testTarget(
            name: "RuntimeOrchestratorTests",
            dependencies: ["RuntimeCore", "RuntimeOrchestrator"]
        ),
        .testTarget(
            name: "ManagerAppTests",
            dependencies: ["ManagerApp"]
        )
    ]
)
