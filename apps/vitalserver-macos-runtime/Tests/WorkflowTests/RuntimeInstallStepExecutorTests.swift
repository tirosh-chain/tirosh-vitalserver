import Application
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
            executeStepPlan: { plan, settings in
                try executeInstallStepPlan(plan, settings: settings) { event in
                    events.append(event)
                }
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
            executeStepPlan: { plan, _ in
                try executeUnsupportedInstallStepPlan(plan)
            }
        )

        XCTAssertThrowsError(try executor.execute(
            .stopRuntimeServices,
            settings: TestInstallSettings(vitalFilesDirectory: "/vital-files")
        )) { error in
            XCTAssertEqual(String(describing: error), "unsupported command: install step stop-runtime-services")
        }
    }
}

private func executeInstallStepPlan(
    _ plan: InstallRuntimeStepExecutionPlan,
    settings: TestInstallSettings,
    append: (String) -> Void
) throws {
    switch plan {
    case .log(let message):
        append("log:\(message)")
    case .prepareInstallDirectories:
        append("prepare-directories:\(settings.vitalFilesDirectory)")
    case .rotateRuntimeLogs:
        append("rotate-logs")
    case .configureDeployEnvironment:
        append("guest-config:\(settings.vitalFilesDirectory)")
    case .prepareInstalledExecutables:
        append("executables")
    case .provisionVMDisk:
        append("disk:\(settings.diskGiB)")
    case .configureInstalledVMRuntime:
        append("vm-runtime:\(settings.cpuCount)")
    case .createCloudInitSeed:
        append("cloud-init:\(settings.vmHostname)")
    case .writeInstalledRuntimeVersion:
        append("version")
    case .configureInstalledPermissions:
        append("permissions:\(settings.proxyPort)")
    case .startInstalledServices:
        append("start:\(settings.startAfterInstall)")
    case .applyStartOnBootPolicy:
        append("boot:\(settings.startOnBoot)")
    case .waitInstallRuntimeHealth:
        let policy = RuntimeServiceRestartPolicy(
            restartVM: settings.startAfterInstall,
            restartGuestLogSync: settings.startAfterInstall,
            restartProxy: settings.startAfterInstall,
            restartWatchdog: settings.startAfterInstall
        )
        append("wait-health:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)")
    case .cleanupInstallSettings:
        append("cleanup")
    case .unsupported(let message):
        throw RuntimeInstallStepExecutionError(message)
    }
}

private func executeUnsupportedInstallStepPlan(_ plan: InstallRuntimeStepExecutionPlan) throws {
    switch plan {
    case .unsupported(let message):
        throw RuntimeInstallStepExecutionError(message)
    case .log,
         .prepareInstallDirectories,
         .rotateRuntimeLogs,
         .configureDeployEnvironment,
         .prepareInstalledExecutables,
         .provisionVMDisk,
         .configureInstalledVMRuntime,
         .createCloudInitSeed,
         .writeInstalledRuntimeVersion,
         .configureInstalledPermissions,
         .startInstalledServices,
         .applyStartOnBootPolicy,
         .waitInstallRuntimeHealth,
         .cleanupInstallSettings:
        return
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
