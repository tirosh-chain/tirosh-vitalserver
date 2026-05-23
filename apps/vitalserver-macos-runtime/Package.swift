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
            name: "RuntimeContracts"
        ),
        .target(
            name: "RuntimeCore",
            dependencies: ["RuntimeContracts"]
        ),
        .target(
            name: "RuntimeControl",
            dependencies: ["RuntimeContracts"]
        ),
        .target(
            name: "HostRuntimeInfrastructure",
            dependencies: ["RuntimeContracts", "RuntimeCore"]
        ),
        .target(
            name: "RuntimeControlAdapter",
            dependencies: ["RuntimeContracts", "RuntimeControl", "RuntimeCore", "HostRuntimeInfrastructure"]
        ),
        .executableTarget(
            name: "HostRuntimeControl",
            dependencies: ["RuntimeContracts", "RuntimeCore", "HostRuntimeInfrastructure"]
        ),
        .executableTarget(
            name: "VitalServerHelperApp",
            dependencies: ["RuntimeContracts", "RuntimeControl", "RuntimeCore", "RuntimeControlAdapter"]
        ),
        .testTarget(
            name: "RuntimeContractsTests",
            dependencies: ["RuntimeContracts"],
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "RuntimeCoreTests",
            dependencies: ["RuntimeContracts", "RuntimeCore"]
        ),
        .testTarget(
            name: "RuntimeControlTests",
            dependencies: ["RuntimeContracts", "RuntimeControl"]
        ),
        .testTarget(
            name: "HostRuntimeInfrastructureTests",
            dependencies: ["RuntimeContracts", "RuntimeCore", "HostRuntimeInfrastructure"]
        ),
        .testTarget(
            name: "HostRuntimeControlTests",
            dependencies: ["RuntimeContracts", "RuntimeCore", "HostRuntimeControl"]
        ),
        .testTarget(
            name: "VitalServerHelperAppTests",
            dependencies: ["RuntimeContracts", "RuntimeControl", "RuntimeControlAdapter", "VitalServerHelperApp"]
        )
    ]
)
