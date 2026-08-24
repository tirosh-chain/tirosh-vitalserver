// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VitalServerHelper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "vitalserver-vm",
            targets: ["CLIHost"]
        ),
        .executable(
            name: "VitalServerHelper",
            targets: ["MacControlPanelHost"]
        ),
        .library(
            name: "MacPlatformAgent",
            targets: ["MacPlatformAgent"]
        ),
        .executable(
            name: "vitalserver-platform-agent",
            targets: ["MacPlatformAgentService"]
        ),
        .executable(
            name: "vitalserver-update-runner",
            targets: ["UpdateRunnerHost"]
        ),
        .executable(
            name: "vitalserver-update-handoff-supervisor",
            targets: ["UpdateHandoffSupervisorHost"]
        ),
        .executable(
            name: "vitalserver-container-layer-effect-executor",
            targets: ["ContainerLayerEffectExecutorHost"]
        ),
        .executable(
            name: "vitalserver-guest-runtime-layer-effect-executor",
            targets: ["GuestRuntimeLayerEffectExecutorHost"]
        ),
        .executable(
            name: "vitalserver-host-installation-manager",
            targets: ["HostInstallationManagerHost"]
        ),
        .executable(
            name: "vitalserver-host-platform-layer-effect-executor",
            targets: ["HostPlatformLayerEffectExecutorHost"]
        ),
        .executable(
            name: "vitalserver-troubleshooting-reset-for-reinstall",
            targets: ["TroubleshootingResetForReinstall"]
        ),
        .executable(
            name: "vitalserver-troubleshooting-upstream-redis-save",
            targets: ["TroubleshootingUpstreamRedisSave"]
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
            dependencies: ["Contracts"]
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
            dependencies: ["Contracts", "Errors", "Application", "RuntimeControl"],
            path: "Sources/Adapters/Inbound",
            resources: [
                .process("RuntimeControlAPI/DevConsole/RuntimeControlDevConsole.html")
            ]
        ),
        .target(
            name: "OutboundAdapters",
            dependencies: ["Contracts", "Errors", "Application", "RuntimeControl"],
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
                "RuntimeControl",
                "InboundAdapters",
                "OutboundAdapters",
                "Bootstrap",
            ],
            path: "Sources/Hosts/CLI"
        ),
        .executableTarget(
            name: "MacControlPanelHost",
            dependencies: ["Contracts", "Errors", "RuntimeControl", "InboundAdapters", "OutboundAdapters", "MacPlatformAgent"],
            path: "Sources/Hosts/MacControlPanel"
        ),
        .target(
            name: "MacPlatformAgent",
            dependencies: ["Contracts", "Errors", "Domain", "Application", "RuntimeControl", "InboundAdapters", "OutboundAdapters"],
            path: "Sources/Hosts/MacPlatformAgent"
        ),
        .executableTarget(
            name: "MacPlatformAgentService",
            dependencies: ["MacPlatformAgent"],
            path: "Sources/Hosts/MacPlatformAgentService"
        ),
        .executableTarget(
            name: "UpdateRunnerHost",
            dependencies: [
                "Contracts",
                "Application",
                "Workflow",
                "OutboundAdapters",
            ],
            path: "Sources/Hosts/UpdateRunner"
        ),
        .executableTarget(
            name: "UpdateHandoffSupervisorHost",
            dependencies: [
                "Contracts",
                "Application",
                "Workflow",
                "OutboundAdapters",
            ],
            path: "Sources/Hosts/UpdateHandoffSupervisor"
        ),
        .target(
            name: "UpdateLayerEffectExecutor",
            dependencies: ["Contracts", "Domain"],
            path: "Sources/Hosts/UpdateLayerEffectExecutor"
        ),
        .executableTarget(
            name: "ContainerLayerEffectExecutorHost",
            dependencies: ["UpdateLayerEffectExecutor"],
            path: "Sources/Hosts/ContainerLayerEffectExecutor"
        ),
        .executableTarget(
            name: "GuestRuntimeLayerEffectExecutorHost",
            dependencies: ["UpdateLayerEffectExecutor"],
            path: "Sources/Hosts/GuestRuntimeLayerEffectExecutor"
        ),
        .executableTarget(
            name: "HostInstallationManagerHost",
            dependencies: [
                "Contracts",
                "Domain",
                "Application",
                "Workflow",
                "OutboundAdapters",
            ],
            path: "Sources/Hosts/HostInstallationManager"
        ),
        .executableTarget(
            name: "HostPlatformLayerEffectExecutorHost",
            dependencies: ["Contracts", "Domain"],
            path: "Sources/Hosts/HostPlatformLayerEffectExecutor"
        ),
        .executableTarget(
            name: "TroubleshootingResetForReinstall",
            path: "Sources/Hosts/Troubleshooting/ResetForReinstall"
        ),
        .executableTarget(
            name: "TroubleshootingUpstreamRedisSave",
            path: "Sources/Hosts/Troubleshooting/UpstreamRedisSave"
        ),
        .testTarget(
            name: "ErrorsTests",
            dependencies: ["Contracts", "Errors"]
        ),
        .testTarget(
            name: "ContractsTests",
            dependencies: ["Contracts", "Errors"],
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
            dependencies: ["Contracts", "Errors", "Application", "RuntimeControl", "InboundAdapters"]
        ),
        .testTarget(
            name: "OutboundAdaptersTests",
            dependencies: ["Contracts", "Errors", "Domain", "Application", "RuntimeControl", "OutboundAdapters"]
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
            name: "UpdateRunnerHostTests",
            dependencies: ["UpdateRunnerHost"]
        ),
        .testTarget(
            name: "UpdateHandoffSupervisorHostTests",
            dependencies: [
                "Contracts",
                "Workflow",
                "OutboundAdapters",
                "UpdateHandoffSupervisorHost",
            ]
        ),
        .testTarget(
            name: "UpdateLayerEffectExecutorTests",
            dependencies: ["Contracts", "UpdateLayerEffectExecutor"]
        ),
        .testTarget(
            name: "HostPlatformLayerEffectExecutorHostTests",
            dependencies: [
                "Contracts",
                "HostPlatformLayerEffectExecutorHost",
            ]
        ),
        .testTarget(
            name: "MacControlPanelHostTests",
            dependencies: ["Contracts", "Errors", "RuntimeControl", "InboundAdapters", "OutboundAdapters", "MacPlatformAgent", "MacControlPanelHost"]
        ),
        .testTarget(
            name: "MacPlatformAgentTests",
            dependencies: ["RuntimeControl", "OutboundAdapters", "MacPlatformAgent"]
        )
    ]
)
