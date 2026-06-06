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
            targets: ["CLIHost"]
        ),
        .executable(
            name: "VitalServerHelper",
            targets: ["MacControlPanelHost"]
        )
    ],
    targets: [
        .target(
            name: "Contracts",
            path: "Sources/Contracts/Shared"
        ),
        .target(
            name: "Errors",
            dependencies: ["Contracts"],
            path: "Sources/Errors"
        ),
        .target(
            name: "Domain",
            dependencies: ["Contracts", "Errors"]
        ),
        .target(
            name: "Application",
            dependencies: ["Contracts", "Errors", "Domain"]
        ),
        .target(
            name: "Workflow",
            dependencies: ["Contracts", "Errors", "Domain", "Application"]
        ),
        .target(
            name: "InboundAdapters",
            dependencies: ["Contracts", "Errors", "Domain", "Application", "Workflow", "RuntimeControl"],
            path: "Sources/Adapters/Inbound"
        ),
        .target(
            name: "OutboundAdapters",
            dependencies: ["Contracts", "Errors", "Domain", "Application", "Workflow", "RuntimeControl"],
            path: "Sources/Adapters/Outbound",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "Bootstrap",
            dependencies: [
                "Contracts",
                "Errors",
                "Domain",
                "Application",
                "Workflow",
                "InboundAdapters",
                "OutboundAdapters",
            ]
        ),
        .target(
            name: "RuntimeControl",
            dependencies: ["Contracts", "Errors"],
            path: "Sources/Contracts/RuntimeControl"
        ),
        .executableTarget(
            name: "CLIHost",
            dependencies: [
                "Contracts",
                "Errors",
                "Domain",
                "Application",
                "Workflow",
                "InboundAdapters",
                "OutboundAdapters",
                "Bootstrap",
            ],
            path: "Sources/Hosts/CLI"
        ),
        .executableTarget(
            name: "MacControlPanelHost",
            dependencies: ["Contracts", "Errors", "RuntimeControl", "InboundAdapters", "OutboundAdapters"],
            path: "Sources/Hosts/MacControlPanel"
        ),
        .testTarget(
            name: "ErrorsTests",
            dependencies: ["Contracts", "Errors"]
        ),
        .testTarget(
            name: "ContractsTests",
            dependencies: ["Contracts"],
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "DomainTests",
            dependencies: ["Contracts", "Errors", "Domain", "Application"]
        ),
        .testTarget(
            name: "ApplicationTests",
            dependencies: ["Contracts", "Errors", "Domain", "Application"]
        ),
        .testTarget(
            name: "WorkflowTests",
            dependencies: [
                "Contracts",
                "Errors",
                "Domain",
                "Application",
                "Workflow",
                "InboundAdapters",
                "OutboundAdapters",
                "Bootstrap",
            ]
        ),
        .testTarget(
            name: "ArchitectureBoundaryTests",
            dependencies: [
                "Contracts",
                "Errors",
                "Domain",
                "Application",
                "Workflow",
                "InboundAdapters",
                "OutboundAdapters",
                "Bootstrap",
            ]
        ),
        .testTarget(
            name: "RuntimeControlTests",
            dependencies: ["Contracts", "Errors", "RuntimeControl"]
        ),
        .testTarget(
            name: "InboundAdaptersTests",
            dependencies: ["Contracts", "Errors", "RuntimeControl", "InboundAdapters"]
        ),
        .testTarget(
            name: "OutboundAdaptersTests",
            dependencies: ["Contracts", "Errors", "Domain", "Application", "Workflow", "RuntimeControl", "OutboundAdapters"]
        ),
        .testTarget(
            name: "CLIHostTests",
            dependencies: [
                "Contracts",
                "Errors",
                "Domain",
                "Application",
                "Workflow",
                "InboundAdapters",
                "OutboundAdapters",
                "Bootstrap",
                "CLIHost",
            ]
        ),
        .testTarget(
            name: "MacControlPanelHostTests",
            dependencies: ["Contracts", "Errors", "RuntimeControl", "InboundAdapters", "OutboundAdapters", "MacControlPanelHost"]
        )
    ]
)
