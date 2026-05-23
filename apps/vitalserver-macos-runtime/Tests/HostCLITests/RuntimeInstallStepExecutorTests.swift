import Core
import Contracts
@testable import HostCLI
import XCTest

final class RuntimeInstallStepExecutorTests: XCTestCase {
    func testExecuteDispatchesInstallStepsToCollaborators() throws {
        let settings = InstallSettings(vitalFilesDirectory: "/vital-files")
        var events: [String] = []
        let executor = RuntimeInstallStepExecutor(
            prepareInstallDirectories: { settings in
                events.append("prepare-directories:\(settings.vitalFilesDirectory)")
            },
            rotateRuntimeLogs: {
                events.append("rotate-logs")
            },
            configureDeployEnvironment: { settings in
                events.append("guest-config:\(settings.vitalFilesDirectory)")
            },
            prepareInstalledExecutables: {
                events.append("executables")
            },
            provisionVMDisk: { settings in
                events.append("disk:\(settings.diskGiB)")
            },
            configureInstalledVMRuntime: { settings in
                events.append("vm-runtime:\(settings.cpuCount)")
            },
            createCloudInitSeed: { settings in
                events.append("cloud-init:\(settings.vmHostname)")
            },
            writeInstalledRuntimeVersion: {
                events.append("version")
            },
            configureInstalledPermissions: { settings in
                events.append("permissions:\(settings.proxyPort)")
            },
            startInstalledServices: { settings in
                events.append("start:\(settings.startAfterInstall)")
            },
            applyStartOnBootPolicy: { settings in
                events.append("boot:\(settings.startOnBoot)")
            },
            cleanupInstallSettings: {
                events.append("cleanup")
            },
            log: { message in
                events.append("log:\(message)")
            }
        )

        for step in RuntimeOperationPlans.install.steps {
            try executor.execute(step, settings: settings)
        }

        XCTAssertEqual(events, [
            "log:install settings loaded",
            "prepare-directories:/vital-files",
            "rotate-logs",
            "guest-config:/vital-files",
            "executables",
            "disk:32",
            "vm-runtime:8",
            "cloud-init:tirosh-vitalserver",
            "version",
            "permissions:80",
            "start:true",
            "boot:true",
            "cleanup",
        ])
    }

    func testRejectsNonInstallStep() {
        let executor = RuntimeInstallStepExecutor(
            prepareInstallDirectories: { _ in },
            rotateRuntimeLogs: {},
            configureDeployEnvironment: { _ in },
            prepareInstalledExecutables: {},
            provisionVMDisk: { _ in },
            configureInstalledVMRuntime: { _ in },
            createCloudInitSeed: { _ in },
            writeInstalledRuntimeVersion: {},
            configureInstalledPermissions: { _ in },
            startInstalledServices: { _ in },
            applyStartOnBootPolicy: { _ in },
            cleanupInstallSettings: {},
            log: { _ in }
        )

        XCTAssertThrowsError(try executor.execute(
            .stopRuntimeServices,
            settings: InstallSettings(vitalFilesDirectory: "/vital-files")
        ))
    }
}
