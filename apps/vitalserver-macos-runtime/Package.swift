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
            name: "Domain",
            dependencies: ["Contracts"]
        ),
        .target(
            name: "Core",
            dependencies: ["Contracts", "Domain", "Application"]
        ),
        .target(
            name: "Application",
            dependencies: ["Contracts", "Domain"]
        ),
        .target(
            name: "Workflow",
            dependencies: ["Contracts", "Domain", "Application"]
        ),
        .target(
            name: "Infrastructure",
            dependencies: ["Contracts", "Domain", "Application", "Workflow"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "HostAdapters",
            dependencies: ["Contracts", "Domain", "Application", "Workflow"]
        ),
        .target(
            name: "Interfaces",
            dependencies: ["Contracts", "Domain", "Application", "Workflow", "RuntimeControl"]
        ),
        .target(
            name: "Bootstrap",
            dependencies: [
                "Contracts",
                "Domain",
                "Application",
                "Workflow",
                "Infrastructure",
                "HostAdapters",
                "Interfaces",
            ]
        ),
        .target(
            name: "RuntimeControl",
            dependencies: ["Contracts"]
        ),
        .target(
            name: "RuntimeControlAPI",
            dependencies: ["Interfaces"]
        ),
        .target(
            name: "HostInfrastructure",
            dependencies: ["Infrastructure"]
        ),
        .target(
            name: "MacHostRuntimeAdapter",
            dependencies: ["Contracts", "RuntimeControl", "Core", "HostInfrastructure"]
        ),
        .executableTarget(
            name: "HostCLI",
            dependencies: [
                "Contracts",
                "Core",
                "Domain",
                "Application",
                "Workflow",
                "HostInfrastructure",
                "HostAdapters",
                "Interfaces",
                "Bootstrap",
            ]
        ),
        .executableTarget(
            name: "MacRuntimeControlApp",
            dependencies: ["Contracts", "RuntimeControl", "RuntimeControlAPI", "MacHostRuntimeAdapter", "Interfaces"]
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
            name: "DomainTests",
            dependencies: ["Contracts", "Domain"]
        ),
        .testTarget(
            name: "ApplicationTests",
            dependencies: ["Contracts", "Domain", "Application"]
        ),
        .testTarget(
            name: "RuntimeWorkflowTests",
            dependencies: [
                "Contracts",
                "Core",
                "Domain",
                "Application",
                "Workflow",
                "Infrastructure",
                "HostAdapters",
                "Interfaces",
                "Bootstrap",
            ]
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
            dependencies: ["Contracts", "Core", "Workflow", "HostAdapters", "HostCLI"]
        ),
        .testTarget(
            name: "MacRuntimeControlAppTests",
            dependencies: ["Contracts", "RuntimeControl", "MacHostRuntimeAdapter", "MacRuntimeControlApp"]
        )
    ]
)
