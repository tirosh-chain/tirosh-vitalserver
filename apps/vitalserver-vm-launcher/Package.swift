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
            targets: ["HostRuntimeControl"]
        ),
        .executable(
            name: "VitalServerHelper",
            targets: ["VitalServerHelperApp"]
        )
    ],
    targets: [
        .target(
            name: "RuntimeCore"
        ),
        .target(
            name: "RuntimeControl",
            dependencies: ["RuntimeCore"]
        ),
        .target(
            name: "HostRuntimeInfrastructure",
            dependencies: ["RuntimeCore"]
        ),
        .executableTarget(
            name: "HostRuntimeControl",
            dependencies: ["RuntimeCore", "HostRuntimeInfrastructure"]
        ),
        .executableTarget(
            name: "VitalServerHelperApp",
            dependencies: ["RuntimeControl", "RuntimeCore", "HostRuntimeInfrastructure"]
        ),
        .testTarget(
            name: "RuntimeCoreTests",
            dependencies: ["RuntimeCore"],
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "HostRuntimeInfrastructureTests",
            dependencies: ["RuntimeCore", "HostRuntimeInfrastructure"]
        ),
        .testTarget(
            name: "HostRuntimeControlTests",
            dependencies: ["RuntimeCore", "HostRuntimeControl"]
        ),
        .testTarget(
            name: "VitalServerHelperAppTests",
            dependencies: ["RuntimeControl", "VitalServerHelperApp"]
        )
    ]
)
