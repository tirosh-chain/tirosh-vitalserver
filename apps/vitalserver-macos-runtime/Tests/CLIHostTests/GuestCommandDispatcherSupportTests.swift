import Foundation
import XCTest
import Errors
import Bootstrap

final class GuestCommandDispatcherSupportTests: XCTestCase {
    func testGuestCommandPollerDispatchesAllHostWrittenRequests() throws {
        let poller = try readGuestToolsFile("adapters/inbound/request_file_poller.py")

        XCTAssertTrue(poller.contains("SETTINGS.intervals.command_poll_seconds"))
        XCTAssertTrue(poller.contains("RuntimeFileName.PREPARE_UPDATE_SHUTDOWN_REQUEST"))
        XCTAssertTrue(poller.contains("RuntimeService.PREPARE_UPDATE_SHUTDOWN"))
        XCTAssertTrue(poller.contains("RuntimeFileName.ACTIVATE_UPDATE_REQUEST"))
        XCTAssertTrue(poller.contains("RuntimeService.ACTIVATE_UPDATE"))
        XCTAssertTrue(poller.contains("RuntimeFileName.REPAIR_DATASTORE_REQUEST"))
        XCTAssertTrue(poller.contains("RuntimeService.REPAIR_DATASTORE"))
        XCTAssertTrue(poller.contains("RuntimeFileName.REDIS_BACKUP_REQUEST"))
        XCTAssertTrue(poller.contains("RuntimeService.REDIS_BACKUP"))
        XCTAssertTrue(poller.contains("\"start\", \"--no-block\""))
        XCTAssertFalse(poller.contains("PathExists="))
    }

    func testBootstrapInstallsWrappersAndExplicitSystemdFiles() throws {
        let bootstrap = try readGuestSupportFile("bootstrap.sh")
        let workflow = try readGuestToolsFile("application/bootstrap.py")
        let operations = try readGuestToolsFile("infrastructure/bootstrap_operations.py")

        XCTAssertTrue(bootstrap.contains("install_guest_tools_runtime"))
        XCTAssertTrue(bootstrap.contains("tirosh-guest-tools-install-config"))
        XCTAssertTrue(bootstrap.contains("exec \"${GUEST_TOOLS_VENV}/bin/tirosh-vitalserver-bootstrap\""))
        XCTAssertFalse(bootstrap.contains("install -m 0644 \"${DEPLOY_DIR}/guest-tools.toml\""))
        XCTAssertFalse(bootstrap.contains("tirosh-guest-tools-install-systemd"))
        XCTAssertFalse(bootstrap.contains("systemctl "))
        XCTAssertFalse(bootstrap.contains("docker "))
        XCTAssertTrue(workflow.contains("class GuestBootstrapWorkflow"))
        XCTAssertFalse(workflow.contains("from tirosh_guest_tools.infrastructure"))
        XCTAssertTrue(operations.contains("RuntimeService.COMMAND_POLLER.value"))
        XCTAssertTrue(operations.contains("systemctl(\"enable\", service)"))
        XCTAssertTrue(workflow.contains("def start_guest_background_services(self)"))
        XCTAssertTrue(operations.contains("systemctl(\"start\", RuntimeService.COMMAND_POLLER.value)"))
        XCTAssertTrue(operations.contains("\"tirosh-vitalserver-command-poller\""))
        XCTAssertTrue(operations.contains("\"tirosh-vitalserver-command-poller.service\""))
        let observabilityUnit = try readGuestSupportFile(
            "systemd/tirosh-guest-observability.service"
        )
        let removedInstaller = try guestToolsDirectory()
            .appendingPathComponent("observability/systemd_installer.py")
        XCTAssertTrue(observabilityUnit.contains("tirosh-guest-observed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedInstaller.path))
    }

    func testBootstrapChecksActualPythonVenvCreation() throws {
        let bootstrap = try readGuestSupportFile("bootstrap.sh")
        let operations = try readGuestToolsFile("infrastructure/bootstrap_operations.py")
        let prepareAirgapRootfs = try readGuestSupportFile("prepare-airgap-rootfs.sh")

        XCTAssertTrue(bootstrap.contains("python3 -m venv --clear \"${GUEST_TOOLS_VENV}\""))
        XCTAssertTrue(operations.contains("TemporaryDirectory(prefix=\"tirosh-venv-check-\")"))
        XCTAssertTrue(operations.contains("[\"python3\", \"-m\", \"venv\", str(test_venv)]"))
        XCTAssertFalse(operations.contains("[\"python3\", \"-m\", \"venv\", \"--help\"]"))
        XCTAssertTrue(prepareAirgapRootfs.contains("verify_python_venv"))
        XCTAssertTrue(prepareAirgapRootfs.contains("python3 -m venv \"${test_venv}\""))
    }

    func testBootstrapFailureOverwritesRunningResult() throws {
        let workflow = try readGuestToolsFile("application/bootstrap.py")

        XCTAssertTrue(workflow.contains("result_terminal: bool = False"))
        XCTAssertTrue(workflow.contains("if not self.state.result_terminal"))
        XCTAssertTrue(workflow.contains("\"Guest bootstrap failed before completion.\""))
        XCTAssertTrue(workflow.contains("\"guest-bootstrap-failed\""))
        XCTAssertTrue(workflow.contains("if status in {\"completed\", \"failed\"}"))
        XCTAssertFalse(workflow.contains("BOOTSTRAP_RESULT_WRITTEN"))
    }

    func testBootstrapRunsDockerRuntimeSmokeBeforeComposeUp() throws {
        let workflow = try readGuestToolsFile("application/bootstrap.py")
        let operations = try readGuestToolsFile("infrastructure/bootstrap_operations.py")

        XCTAssertTrue(workflow.contains("DOCKER_SMOKE_IMAGE = \"redis:3.2.12-alpine\""))
        XCTAssertTrue(workflow.contains("def run_docker_runtime_smoke(self)"))
        XCTAssertTrue(operations.contains("\"--network\","))
        XCTAssertTrue(operations.contains("\"seccomp=unconfined\""))
        XCTAssertTrue(workflow.contains("\"guest-bootstrap-docker-runtime-failed\""))
        XCTAssertTrue(workflow.contains("GuestBootstrapStep.PREPARE_RUNTIME_DATA"))
        XCTAssertTrue(workflow.contains("GuestBootstrapStep.START_DOCKER"))
        XCTAssertTrue(operations.contains("systemctl(\"start\", RuntimeService.COMPOSE.value)"))
        assertOrder(
            in: workflow,
            first: "(GuestBootstrapStep.PREPARE_RUNTIME_DATA, self.prepare_runtime_data)",
            second: "(GuestBootstrapStep.START_DOCKER, self.start_docker)"
        )
        assertOrder(
            in: workflow,
            first: "(GuestBootstrapStep.LOAD_DOCKER_IMAGES, self.load_bundled_docker_images)",
            second: "(GuestBootstrapStep.RUN_DOCKER_SMOKE, self.run_docker_runtime_smoke)"
        )
        assertOrder(
            in: workflow,
            first: "(GuestBootstrapStep.RUN_DOCKER_SMOKE, self.run_docker_runtime_smoke)",
            second: "(GuestBootstrapStep.START_COMPOSE, self.start_compose)"
        )
        assertOrder(
            in: workflow,
            first: "(GuestBootstrapStep.START_COMPOSE, self.start_compose)",
            second: "(GuestBootstrapStep.START_CONTAINER_LOGS, self.start_container_logs)"
        )
        XCTAssertFalse(operations.contains("\n/usr/local/bin/tirosh-vitalserver-compose up\n"))
        XCTAssertTrue(operations.contains("\"runtimeBootSmoke\""))
        XCTAssertTrue(operations.contains("runtime boot smoke metadata is missing runtimeBootSmoke"))
        XCTAssertTrue(operations.contains("runtime boot smoke enabled flag must be explicit boolean"))
    }

    func testRuntimeComposeDisablesContainerSeccompForAppleVirtualizationGuestKernel() throws {
        let compose = try readGuestSupportFile("compose.yaml")

        XCTAssertEqual(
            compose.components(separatedBy: "seccomp=unconfined").count - 1,
            8
        )
    }

    func testDockerRuntimeSmokeRunsWithoutUnsupportedBPFJITSysctlGuard() throws {
        let bootstrap = try readGuestSupportFile("bootstrap.sh")
        let workflow = try readGuestToolsFile("application/bootstrap.py")
        let operations = try readGuestToolsFile("infrastructure/bootstrap_operations.py")
        let prepareAirgapRootfs = try readGuestSupportFile("prepare-airgap-rootfs.sh")

        XCTAssertFalse(Constants.BootAssets.commandLine.contains("bpf_jit_enable"))
        XCTAssertTrue(Constants.BootAssets.commandLine.contains("seccomp=0"))
        XCTAssertFalse(bootstrap.contains("BPF_JIT_SYSCTL_FILE"))
        XCTAssertFalse(bootstrap.contains("net.core.bpf_jit_enable"))
        XCTAssertFalse(bootstrap.contains("sysctl -w net.core.bpf_jit_enable"))
        XCTAssertTrue(workflow.contains("def start_docker(self)"))
        XCTAssertTrue(operations.contains("systemctl(\"enable\", \"--now\", \"docker\")"))
        XCTAssertTrue(operations.contains("RuntimeService.CONTAINER_LOGS.value"))
        XCTAssertTrue(operations.contains("systemctl(\"enable\", service)"))
        XCTAssertTrue(operations.contains("systemctl(\"start\", RuntimeService.CONTAINER_LOGS.value)"))
        XCTAssertFalse(operations.contains("systemctl(\"enable\", \"--now\", RuntimeService.CONTAINER_LOGS.value)"))
        XCTAssertFalse(prepareAirgapRootfs.contains("BPF_JIT_SYSCTL_FILE"))
        XCTAssertFalse(prepareAirgapRootfs.contains("net.core.bpf_jit_enable"))
        XCTAssertFalse(prepareAirgapRootfs.contains("sysctl -w net.core.bpf_jit_enable"))
        XCTAssertFalse(prepareAirgapRootfs.contains("\"bpfJIT\""))
        XCTAssertFalse(prepareAirgapRootfs.contains("run_docker_runtime_smoke"))
        XCTAssertFalse(prepareAirgapRootfs.contains("run_compose_runtime_smoke"))
        XCTAssertTrue(prepareAirgapRootfs.contains("tirosh-vitalserver-rootfs-smoke"))
    }

    func testPrepareAirgapRootfsDelegatesRootfsSmokeToGuestTools() throws {
        let prepareAirgapRootfs = try readGuestSupportFile("prepare-airgap-rootfs.sh")

        XCTAssertTrue(prepareAirgapRootfs.contains("RUNTIME_MANIFEST_FILE=\"${RUNTIME_DIR}/rootfs-runtime-manifest.json\""))
        XCTAssertTrue(prepareAirgapRootfs.contains("busybox-static"))
        XCTAssertTrue(prepareAirgapRootfs.contains("install_guest_tools_for_rootfs_smoke"))
        XCTAssertTrue(prepareAirgapRootfs.contains("tirosh-vitalserver-rootfs-smoke"))
        XCTAssertTrue(prepareAirgapRootfs.contains("update_apt_indexes()"))
        XCTAssertTrue(prepareAirgapRootfs.contains("ROOTFS_STAGE=\"apt-index-update\""))
        XCTAssertTrue(prepareAirgapRootfs.contains("update_apt_indexes\n  record_apt_plan"))
        XCTAssertFalse(prepareAirgapRootfs.contains("docker run --rm --network none"))
        XCTAssertFalse(prepareAirgapRootfs.contains("docker compose --project-name"))
        XCTAssertTrue(prepareAirgapRootfs.contains("\"runId\": manifest[\"runId\"]"))
        XCTAssertTrue(prepareAirgapRootfs.contains("ready_path.write_text"))
    }

    func testGuestCommandFailuresClearRequestFilesAfterWritingFailureResult() throws {
        let activation = try readGuestToolsFile("application/update_activation.py")
        let shutdown = try readGuestToolsFile("application/update_shutdown.py")
        let repair = try readGuestToolsFile("application/redis_repair.py")

        XCTAssertTrue(activation.contains("REQUEST_FILE.unlink(missing_ok=True)"))
        XCTAssertTrue(shutdown.contains("write_result"))
        XCTAssertTrue(shutdown.contains("REQUEST_FILE.unlink(missing_ok=True)"))
        XCTAssertTrue(repair.contains("REQUEST_FILE.unlink(missing_ok=True)"))
    }

    func testReleaseSyncTargetsGuestToolsInfrastructureAndUseCases() throws {
        let syncRelease = try readRuntimeSupportFile("Build/sync-release.py")

        XCTAssertTrue(syncRelease.contains("\"packages/vitalserver-guest-tools/src/tirosh_guest_tools/infrastructure\""))
        XCTAssertTrue(syncRelease.contains("\"bootstrap_operations.py\""))
        XCTAssertTrue(syncRelease.contains("\"packages/vitalserver-guest-tools/src/tirosh_guest_tools/application\""))
        XCTAssertTrue(syncRelease.contains("\"redis_repair.py\""))
        XCTAssertFalse(syncRelease.contains("tirosh_guest_tools/redis/repair.py"))
    }

    func testVMShutdownTimeoutMigrationReloadsLoadedLaunchdJob() throws {
        let migration = try readRuntimeSupportFile("Build/migrations/004-refresh-vm-shutdown-timeouts")

        XCTAssertTrue(migration.contains("<key>ExitTimeOut</key>"))
        XCTAssertTrue(migration.contains("<integer>900</integer>"))
        XCTAssertTrue(migration.contains("launchctl print \"system/${vm_label}\""))
        XCTAssertTrue(migration.contains("launchctl bootout \"system/${vm_label}\""))
        XCTAssertTrue(migration.contains("VM launchd service unloaded so updated ExitTimeOut is used on next start"))
    }

    func testPostinstallDelegatesInstallProvisionWithoutStatusFallback() throws {
        let postinstall = try readRuntimeSupportFile("Packaging/postinstall.template")

        XCTAssertTrue(postinstall.contains("\"${vm_bin}\" runtime install-provision"))
        XCTAssertFalse(postinstall.contains("\"${vm_bin}\" runtime install &"))
        XCTAssertFalse(postinstall.contains("runtime_status="))
        XCTAssertFalse(postinstall.contains("log_runtime_install_status"))
        XCTAssertFalse(postinstall.contains("runtime install progress"))
        XCTAssertFalse(postinstall.contains("runtime install timed out"))
        XCTAssertFalse(postinstall.contains("kill -KILL \"${pid}\""))
        XCTAssertFalse(postinstall.contains("postinstall_timeout_seconds=300"))
        XCTAssertFalse(postinstall.contains("\"${vm_bin}\" runtime uninstall --clean"))
        XCTAssertFalse(postinstall.contains("postinstall failure cleanup blocked"))
        XCTAssertTrue(postinstall.contains("\"${vm_bin}\" runtime stop-services"))
        XCTAssertTrue(postinstall.contains("launchctl bootout \"system/${label}\""))
        XCTAssertTrue(postinstall.contains("rm -rf \"${path}\""))
        XCTAssertTrue(postinstall.contains("postinstall failure cleanup refused unsafe path"))
        XCTAssertFalse(postinstall.contains("pkgutil --forget"))
        XCTAssertFalse(postinstall.contains("pgrep -f"))
    }

    func testPreinstallDelegatesFreshInstallStateCheckToCLIHost() throws {
        let preinstall = try readRuntimeSupportFile("Packaging/preinstall")

        XCTAssertTrue(preinstall.contains("preflight_bin=\"${script_dir}/vitalserver-vm-preinstall\""))
        XCTAssertTrue(preinstall.contains("\"${preflight_bin}\" runtime preinstall-check"))
        XCTAssertTrue(preinstall.contains("pkg install supports fresh installs only"))
        XCTAssertTrue(preinstall.contains("Remove the existing install first, then run the pkg again."))
        XCTAssertTrue(preinstall.contains("sudo /usr/local/bin/tirosh-vitalserver-uninstall --clean"))
        XCTAssertTrue(preinstall.contains("make dist/uninstall/dev VM_UNINSTALL_ARGS=--clean"))
        XCTAssertTrue(preinstall.contains("printf \"%s\\n\" \"${preflight_output}\" >&2"))
        XCTAssertFalse(preinstall.contains("pkgutil --pkg-info"))
        XCTAssertFalse(preinstall.contains("launchctl print"))
        XCTAssertFalse(preinstall.contains("lsof -nP"))
        XCTAssertFalse(preinstall.contains("plutil -extract"))
        XCTAssertFalse(preinstall.contains("[[ -e"))
    }

    func testUninstallWaitsForStoppedStateBeforeRemovingRuntimeFiles() throws {
        let uninstall = try readRuntimeSupportFile("Packaging/uninstall.template")

        XCTAssertTrue(uninstall.contains("command=(\"${vm_bin}\" \"runtime\" \"uninstall\")"))
        XCTAssertTrue(uninstall.contains("command+=(\"--clean\")"))
        XCTAssertTrue(uninstall.contains("command+=(\"--force-clean-uninstaller\")"))
        XCTAssertTrue(uninstall.contains("vm_home=\"${VM_HOME}\""))
        XCTAssertTrue(uninstall.contains("VITALSERVER_VM_HOME=\"${vm_home}\" \"${command[@]}\""))
        XCTAssertTrue(uninstall.contains("step=remove-uninstaller status=started"))
        XCTAssertFalse(uninstall.contains("/usr/bin/python3"))
        XCTAssertFalse(uninstall.contains("launchctl bootout"))
        XCTAssertFalse(uninstall.contains("rm -rf"))
    }

    func testGuestToolsBackThinWrappersAndSystemdFiles() throws {
        let bootstrap = try readGuestSupportFile("bootstrap.sh")
        let guestSupport = try guestSupportDirectory()
        let systemInstall = try readGuestToolsFile("infrastructure/system_install.py")

        XCTAssertTrue(bootstrap.contains("python3 -m venv --clear \"${GUEST_TOOLS_VENV}\""))
        XCTAssertTrue(
            bootstrap.contains(
                "\"${GUEST_TOOLS_VENV}/bin/pip\" install --no-index --no-deps \"${wheel}\""
            )
        )
        XCTAssertTrue(bootstrap.contains("tirosh-vitalserver-bootstrap"))
        XCTAssertTrue(systemInstall.contains("RuntimeCommand.GUEST_OBSERVED"))
        XCTAssertTrue(systemInstall.contains("RuntimeCommand.RUNTIME_STATE"))
        XCTAssertTrue(systemInstall.contains("RuntimeCommand.VITALSERVER_RUNTIME_BOOT_SMOKE"))
        XCTAssertTrue(systemInstall.contains("RuntimeCommand.VITALSERVER_RUNTIME_DATA_PREPARE"))
        XCTAssertTrue(systemInstall.contains("RuntimeCommand.VITALSERVER_ACTIVATE_UPDATE"))
        XCTAssertTrue(systemInstall.contains("RuntimeCommand.VITALSERVER_BOOTSTRAP"))
        let activationUseCase = try readGuestToolsFile("application/update_activation.py")
        let shutdownUseCase = try readGuestToolsFile("application/update_shutdown.py")
        XCTAssertTrue(activationUseCase.contains("ObservationPhase.ACTIVATION_PRE"))
        XCTAssertTrue(activationUseCase.contains("ObservationPhase.ACTIVATION_POST"))
        XCTAssertTrue(activationUseCase.contains("ObservationPhase.ACTIVATION_FAILURE"))
        XCTAssertTrue(shutdownUseCase.contains("ObservationPhase.SHUTDOWN_PRE_STOP"))
        XCTAssertTrue(shutdownUseCase.contains("ObservationPhase.SHUTDOWN_POST_SYNC"))
        XCTAssertTrue(shutdownUseCase.contains("ObservationPhase.SHUTDOWN_POWEROFF_REQUESTED"))
        XCTAssertTrue(shutdownUseCase.contains("ObservationPhase.SHUTDOWN_FAILURE"))
        let wrapper = try readGuestSupportFile("bin/tirosh-vitalserver-compose")
        let runtimeBootSmokeWrapper = try readGuestSupportFile("bin/tirosh-vitalserver-runtime-boot-smoke")
        let service = try readGuestSupportFile("systemd/tirosh-vitalserver-compose.service")
        let activationService = try readGuestSupportFile("systemd/tirosh-vitalserver-activate-update.service")
        let testkitService = try readGuestSupportFile("systemd/tirosh-vitalserver-testkit.service")
        XCTAssertTrue(wrapper.contains("exec /opt/tirosh/guest-tools/venv/bin/"))
        XCTAssertTrue(runtimeBootSmokeWrapper.contains("tirosh-vitalserver-runtime-boot-smoke"))
        XCTAssertTrue(service.contains("ExecStart=/usr/local/bin/tirosh-vitalserver-compose up"))
        XCTAssertTrue(service.contains("TimeoutStopSec=45"))
        XCTAssertTrue(
            activationService.contains(
                "Conflicts=tirosh-vitalserver-compose.service tirosh-vitalserver-testkit.service"
            )
        )
        XCTAssertTrue(testkitService.contains("After=docker.service network-online.target tirosh-vitalserver-compose.service"))
        XCTAssertFalse(testkitService.contains("Wants=network-online.target tirosh-vitalserver-compose.service"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: guestSupport.appendingPathComponent("guest-tools.toml").path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: try guestToolsDirectory()
                    .appendingPathComponent("resources/guest-tools.toml")
                    .path
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: guestSupport.appendingPathComponent("bin").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: guestSupport.appendingPathComponent("systemd").path))
    }

    private func readGuestSupportFile(_ relativePath: String) throws -> String {
        let fileURL = try guestSupportDirectory().appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func readRuntimeSupportFile(_ relativePath: String) throws -> String {
        let fileURL = try guestSupportDirectory()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func readGuestToolsFile(_ relativePath: String) throws -> String {
        let fileURL = try guestToolsDirectory().appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func guestSupportDirectory() throws -> URL {
        var current = URL(fileURLWithPath: #filePath)
        while current.path != "/" {
            let candidate = current
                .appendingPathComponent("apps/vitalserver-macos-runtime/Support/Guest")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            current.deleteLastPathComponent()
        }
        throw NSError(domain: "GuestCommandDispatcherSupportTests", code: 1)
    }

    private func guestToolsDirectory() throws -> URL {
        var current = URL(fileURLWithPath: #filePath)
        while current.path != "/" {
            let candidate = current
                .appendingPathComponent("packages/vitalserver-guest-tools/src/tirosh_guest_tools")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            current.deleteLastPathComponent()
        }
        throw NSError(domain: "GuestCommandDispatcherSupportTests", code: 2)
    }

    private func assertOrder(
        in text: String,
        first: String,
        second: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let firstRange = text.range(of: first) else {
            XCTFail("missing first marker: \(first)", file: file, line: line)
            return
        }
        guard let secondRange = text.range(of: second) else {
            XCTFail("missing second marker: \(second)", file: file, line: line)
            return
        }
        XCTAssertLessThan(firstRange.lowerBound, secondRange.lowerBound, file: file, line: line)
    }
}
