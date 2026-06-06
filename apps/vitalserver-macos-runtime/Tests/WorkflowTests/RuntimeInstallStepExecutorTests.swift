import Contracts
import Domain
import Workflow
import XCTest
import Errors

final class RuntimeInstallStepExecutorTests: XCTestCase {
    func testExecuteDispatchesInstallStepsToCollaborators() throws {
        let settings = TestInstallSettings(vitalFilesDirectory: "/vital-files")
        var events: [String] = []
        let executor = RuntimeInstallStepExecutor<TestInstallSettings>(
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
            runtimeServiceRestartPolicy: { settings in
                RuntimeServiceRestartPolicy(
                    restartVM: settings.startAfterInstall,
                    restartGuestLogSync: settings.startAfterInstall,
                    restartProxy: settings.startAfterInstall,
                    restartWatchdog: settings.startAfterInstall
                )
            },
            waitForHealth: { policy in
                events.append("wait-health:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)")
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
            "wait-health:true:true:true",
            "cleanup",
        ])
    }

    func testRejectsNonInstallStep() {
        let executor = RuntimeInstallStepExecutor<TestInstallSettings>(
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
            runtimeServiceRestartPolicy: { _ in
                RuntimeServiceRestartPolicy(
                    restartVM: false,
                    restartGuestLogSync: false,
                    restartProxy: false,
                    restartWatchdog: false
                )
            },
            waitForHealth: { _ in },
            cleanupInstallSettings: {},
            log: { _ in }
        )

        XCTAssertThrowsError(try executor.execute(
            .stopRuntimeServices,
            settings: TestInstallSettings(vitalFilesDirectory: "/vital-files")
        )) { error in
            XCTAssertEqual(String(describing: error), "unsupported command: install step stop-runtime-services")
        }
    }
}

private struct TestInstallSettings {
    var vitalFilesDirectory: String
    var diskGiB: Int = 32
    var cpuCount: Int = 8
    var vmHostname: String = "tirosh-vitalserver"
    var proxyPort: Int = 80
    var startAfterInstall: Bool = true
    var startOnBoot: Bool = true
}
