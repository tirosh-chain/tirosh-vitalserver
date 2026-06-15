import Application
import Contracts
import Foundation
import XCTest
import Errors

final class RuntimeInstallVMRuntimeConfiguratorTests: XCTestCase {
    func testConfigureLoadsExistingConfigAppliesInstallInputClearsBridgeForSharedNetworkAndWritesConfig() throws {
        let events = EventLog()
        let configURL = URL(fileURLWithPath: "/runtime/config/vm.json")
        let configurator = makeConfigurator(
            configURL: configURL,
            configPathState: .file,
            loadedConfig: TestVMConfig(
                installCPUCount: 2,
                installMemoryMiB: 2048,
                installNetworkMode: .bridged,
                installBridgedInterface: "en0",
                installPreventSystemSleep: nil,
                installSSHAuthorizedKeys: nil
            ),
            defaultConfig: TestVMConfig(),
            events: events
        )

        try configurator.configure(input: input(networkMode: .shared))

        XCTAssertEqual(events.values, [
            "mkdir:/runtime:true",
            "mkdir:/vital-files:true",
            "load:/runtime/config/vm.json",
            "defaults",
            "encode:cpu=4 memory=8192 mode=shared bridge=nil shared=/data vital=/custom-vital sleep=false keys=1 defaults=true",
            "mkdir:/runtime/config:true",
            "write:/runtime/config/vm.json:cpu=4 memory=8192 mode=shared bridge=nil shared=/data vital=/custom-vital sleep=false keys=1 defaults=true",
        ])
    }

    func testConfigureUsesDefaultConfigWhenConfigFileIsAbsentAndPreservesBridgeForBridgedNetwork() throws {
        let events = EventLog()
        let configURL = URL(fileURLWithPath: "/runtime/config/vm.json")
        let configurator = makeConfigurator(
            configURL: configURL,
            configPathState: .missing,
            loadedConfig: TestVMConfig(),
            defaultConfig: TestVMConfig(
                installCPUCount: 1,
                installMemoryMiB: 1024,
                installNetworkMode: .shared,
                installBridgedInterface: "en1",
                installPreventSystemSleep: true,
                installSSHAuthorizedKeys: nil
            ),
            events: events
        )

        try configurator.configure(input: input(networkMode: .bridged))

        XCTAssertFalse(events.values.contains("load:/runtime/config/vm.json"))
        XCTAssertTrue(events.values.contains(
            "encode:cpu=4 memory=8192 mode=bridged bridge=en1 shared=/data vital=/custom-vital sleep=false keys=1 defaults=true"
        ))
    }

    func testConfigureFailsInsteadOfCreatingDefaultConfigWhenConfigInspectionFails() throws {
        let events = EventLog()
        let configURL = URL(fileURLWithPath: "/runtime/config/vm.json")
        let configurator = makeConfigurator(
            configURL: configURL,
            configPathState: .inspectFailed("permission denied"),
            loadedConfig: TestVMConfig(),
            defaultConfig: TestVMConfig(),
            events: events
        )

        XCTAssertThrowsError(try configurator.configure(input: input(networkMode: .shared))) { error in
            XCTAssertEqual(
                error as? RuntimeInstallVMRuntimeConfigurationError,
                .configInspectionFailed(path: configURL.path, reason: "permission denied")
            )
        }
        XCTAssertFalse(events.values.contains { $0.hasPrefix("encode:") })
        XCTAssertFalse(events.values.contains { $0.hasPrefix("write:") })
    }

    func testConfigureFailsWhenConfigPathIsDirectoryInsteadOfUsingDefaultConfig() throws {
        let events = EventLog()
        let configURL = URL(fileURLWithPath: "/runtime/config/vm.json")
        let configurator = makeConfigurator(
            configURL: configURL,
            configPathState: .directory,
            loadedConfig: TestVMConfig(),
            defaultConfig: TestVMConfig(),
            events: events
        )

        XCTAssertThrowsError(try configurator.configure(input: input(networkMode: .shared))) { error in
            XCTAssertEqual(
                error as? RuntimeInstallVMRuntimeConfigurationError,
                .unexpectedConfigPathState(path: configURL.path, state: RuntimePathState.directory.rawValue)
            )
        }
        XCTAssertFalse(events.values.contains("load:/runtime/config/vm.json"))
        XCTAssertFalse(events.values.contains { $0.hasPrefix("write:") })
    }

    private func makeConfigurator(
        configURL: URL,
        configPathState: RuntimePathState,
        loadedConfig: TestVMConfig,
        defaultConfig: TestVMConfig,
        events: EventLog
    ) -> RuntimeInstallVMRuntimeConfigurator<TestVMConfig> {
        RuntimeInstallVMRuntimeConfigurator(
            context: RuntimeInstallVMRuntimeConfigurationContext(
                configURL: configURL,
                requiredDirectories: [
                    URL(fileURLWithPath: "/runtime"),
                    URL(fileURLWithPath: "/vital-files"),
                ]
            ),
            operations: RuntimeInstallVMRuntimeConfigurationOperations(
                createDirectory: { url, withIntermediateDirectories in
                    events.append("mkdir:\(url.path):\(withIntermediateDirectories)")
                },
                configPathState: { url in
                    XCTAssertEqual(url, configURL)
                    return configPathState
                },
                loadConfig: { url in
                    events.append("load:\(url.path)")
                    return loadedConfig
                },
                defaultConfig: {
                    defaultConfig
                },
                ensureRuntimeDefaults: { config in
                    events.append("defaults")
                    config.runtimeDefaultsApplied = true
                },
                encodeConfig: { config in
                    let encoded = Self.summary(config)
                    events.append("encode:\(encoded)")
                    return Data(encoded.utf8)
                },
                writeData: { data, url, _ in
                    events.append("write:\(url.path):\(String(decoding: data, as: UTF8.self))")
                }
            )
        )
    }

    private func input(networkMode: TestNetworkMode) -> RuntimeInstallVMRuntimeConfigurationInput<TestNetworkMode> {
        RuntimeInstallVMRuntimeConfigurationInput(
            cpuCount: 4,
            memoryGiB: 8,
            networkMode: networkMode,
            sharedNetworkMode: .shared,
            dataDirectoryPath: "/data",
            sharedDirectoryTag: "tirosh",
            sharedDirectoryGuestMountPath: "/mnt/tirosh",
            vitalFilesDirectoryPath: "/custom-vital",
            vitalFilesDirectoryTag: "vital-files",
            vitalFilesDirectoryGuestMountPath: "/mnt/vital-files",
            preventSystemSleep: false,
            sshAuthorizedKeys: ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEexample operator@example.test"]
        )
    }

    private static func summary(_ config: TestVMConfig) -> String {
        [
            "cpu=\(config.installCPUCount)",
            "memory=\(config.installMemoryMiB)",
            "mode=\(config.installNetworkMode.rawValue)",
            "bridge=\(config.installBridgedInterface ?? "nil")",
            "shared=\(config.sharedDirectory?.hostPath ?? "nil")",
            "vital=\(config.vitalFilesDirectory?.hostPath ?? "nil")",
            "sleep=\(config.installPreventSystemSleep.map(String.init) ?? "nil")",
            "keys=\(config.installSSHAuthorizedKeys?.count ?? -1)",
            "defaults=\(config.runtimeDefaultsApplied)",
        ].joined(separator: " ")
    }

    private final class EventLog {
        private(set) var values: [String] = []

        func append(_ value: String) {
            values.append(value)
        }
    }
}

private enum TestNetworkMode: String, Equatable {
    case shared
    case bridged
}

private struct TestVMConfig: RuntimeInstallMutableVMRuntimeConfiguration {
    var installCPUCount: Int = 0
    var installMemoryMiB: UInt64 = 0
    var installNetworkMode: TestNetworkMode = .shared
    var installBridgedInterface: String?
    var installPreventSystemSleep: Bool?
    var installSSHAuthorizedKeys: [String]?
    var sharedDirectory: RuntimeSharedDirectoryConfiguration?
    var vitalFilesDirectory: RuntimeSharedDirectoryConfiguration?
    var runtimeDefaultsApplied = false

    mutating func setInstallSharedDirectory(_ directory: RuntimeSharedDirectoryConfiguration) {
        sharedDirectory = directory
    }

    mutating func setInstallVitalFilesDirectory(_ directory: RuntimeSharedDirectoryConfiguration) {
        vitalFilesDirectory = directory
    }
}
