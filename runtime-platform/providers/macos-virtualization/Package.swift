// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacOSVirtualizationProvider",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MacOSVirtualizationProvider", targets: ["MacOSVirtualizationProvider"]),
        .executable(name: "macos-virtual-machine-command-cli", targets: ["MacOSVirtualMachineCommandCLI"]),
        .executable(name: "macos-virtual-machine-supervisor", targets: ["MacOSVirtualMachineSupervisor"])
    ],
    targets: [
        .target(name: "MacOSVirtualizationProvider"),
        .executableTarget(
            name: "MacOSVirtualMachineCommandCLI",
            dependencies: ["MacOSVirtualizationProvider"]
        ),
        .executableTarget(
            name: "MacOSVirtualMachineSupervisor",
            dependencies: ["MacOSVirtualizationProvider"]
        ),
        .testTarget(
            name: "MacOSVirtualizationProviderTests",
            dependencies: ["MacOSVirtualizationProvider"]
        )
    ]
)
