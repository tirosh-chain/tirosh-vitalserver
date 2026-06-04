// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VitalServerHelper",
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
            targets: ["MacRuntimeControlApp"]
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
            name: "RuntimeWorkflow",
            dependencies: ["Contracts", "Core"]
        ),
        .target(
            name: "RuntimeControl",
            dependencies: ["Contracts"]
        ),
        .target(
            name: "RuntimeControlAPI",
            dependencies: ["RuntimeControl"]
        ),
        .target(
            name: "HostInfrastructure",
            dependencies: ["Contracts", "Core"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "MacHostRuntimeAdapter",
            dependencies: ["Contracts", "RuntimeControl", "Core", "HostInfrastructure"]
        ),
        .executableTarget(
            name: "HostCLI",
            dependencies: ["Contracts", "Core", "RuntimeWorkflow", "HostInfrastructure"]
        ),
        .executableTarget(
            name: "MacRuntimeControlApp",
            dependencies: ["Contracts", "RuntimeControl", "RuntimeControlAPI", "MacHostRuntimeAdapter"]
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
            name: "RuntimeWorkflowTests",
            dependencies: ["Contracts", "Core", "RuntimeWorkflow"]
        ),
        .testTarget(
            name: "RuntimeControlTests",
            dependencies: ["Contracts", "RuntimeControl"]
        ),
        .testTarget(
            name: "RuntimeControlAPITests",
            dependencies: ["Contracts", "RuntimeControl", "RuntimeControlAPI"]
        ),
        .testTarget(
            name: "HostInfrastructureTests",
            dependencies: ["Contracts", "Core", "HostInfrastructure"]
        ),
        .testTarget(
            name: "HostCLITests",
            dependencies: ["Contracts", "Core", "RuntimeWorkflow", "HostCLI"]
        ),
        .testTarget(
            name: "MacRuntimeControlAppTests",
            dependencies: ["Contracts", "RuntimeControl", "MacHostRuntimeAdapter", "MacRuntimeControlApp"]
        )
    ]
)
