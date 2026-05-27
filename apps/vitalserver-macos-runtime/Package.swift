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
            name: "RuntimeControl",
            dependencies: ["Contracts", "Core"]
        ),
        .target(
            name: "RuntimeControlAPI",
            dependencies: ["RuntimeControl", "Core"]
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
            dependencies: ["Contracts", "Core", "HostInfrastructure"]
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
            name: "RuntimeControlTests",
            dependencies: ["Contracts", "Core", "RuntimeControl"]
        ),
        .testTarget(
            name: "RuntimeControlAPITests",
            dependencies: ["Core", "RuntimeControl", "RuntimeControlAPI"]
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
            name: "MacRuntimeControlAppTests",
            dependencies: ["Contracts", "RuntimeControl", "MacHostRuntimeAdapter", "MacRuntimeControlApp"]
        )
    ]
)
