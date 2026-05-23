// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TiroshVitalServerHelper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "vitalserver-vm",
            targets: ["HostCLI"]
        ),
        .executable(
            name: "VitalServerHelper",
            targets: ["MacManagerApp"]
        )
    ],
    targets: [
        .target(
            name: "Contracts"
        ),
        .target(
            name: "Core",
            dependencies: ["Contracts"]
        ),
        .target(
            name: "Management",
            dependencies: ["Contracts"]
        ),
        .target(
            name: "HostInfrastructure",
            dependencies: ["Contracts", "Core"]
        ),
        .target(
            name: "LocalManagement",
            dependencies: ["Contracts", "Management", "Core", "HostInfrastructure"]
        ),
        .executableTarget(
            name: "HostCLI",
            dependencies: ["Contracts", "Core", "HostInfrastructure"]
        ),
        .executableTarget(
            name: "MacManagerApp",
            dependencies: ["Contracts", "Management", "LocalManagement"]
        ),
        .testTarget(
            name: "ContractsTests",
            dependencies: ["Contracts"],
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Contracts", "Core"]
        ),
        .testTarget(
            name: "ManagementTests",
            dependencies: ["Contracts", "Management"]
        ),
        .testTarget(
            name: "HostInfrastructureTests",
            dependencies: ["Contracts", "Core", "HostInfrastructure"]
        ),
        .testTarget(
            name: "HostCLITests",
            dependencies: ["Contracts", "Core", "HostCLI"]
        ),
        .testTarget(
            name: "MacManagerAppTests",
            dependencies: ["Contracts", "Management", "LocalManagement", "MacManagerApp"]
        )
    ]
)
