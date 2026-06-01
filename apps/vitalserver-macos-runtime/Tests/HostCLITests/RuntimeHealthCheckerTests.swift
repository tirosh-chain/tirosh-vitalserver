import Foundation
import Core
import Contracts
import HostInfrastructure
@testable import HostCLI
import XCTest

final class RuntimeHealthCheckerTests: XCTestCase {
    func testGuestRuntimeStateObservationReaderKeepsFreshLoadedState() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.modificationDates[installedPaths.runtimeState] = Date(timeIntervalSince1970: 1_800_000_000)
        let guestGateway = RuntimeGuestGatewaySpy()
        guestGateway.runtimeState = GuestRuntimeStateDocument(
            vmIP: "192.168.64.2",
            updatedAt: "2026-05-24T00:00:00Z",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200"
        )
        let reader = RuntimeGuestRuntimeStateObservationReader(
            guestGateway: guestGateway,
            fileStore: fileStore,
            runtimeStateURL: installedPaths.runtimeState,
            staleAfterSeconds: 60,
            now: { Date(timeIntervalSince1970: 1_800_000_030) }
        )

        let observation = reader.read()

        XCTAssertEqual(observation.loadedState?.vmIP, "192.168.64.2")
        XCTAssertEqual(observation.freshState?.vmIP, "192.168.64.2")
        XCTAssertTrue(observation.isPresent)
        XCTAssertTrue(observation.isFresh)
        XCTAssertTrue(observation.failureReasons.isEmpty)
    }

    func testGuestRuntimeStateObservationReaderKeepsLoadedButSuppressesStaleState() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.modificationDates[installedPaths.runtimeState] = Date(timeIntervalSince1970: 1_800_000_000)
        let guestGateway = RuntimeGuestGatewaySpy()
        guestGateway.runtimeState = GuestRuntimeStateDocument(
            vmIP: "192.168.64.2",
            updatedAt: "2026-05-24T00:00:00Z",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200"
        )
        let reader = RuntimeGuestRuntimeStateObservationReader(
            guestGateway: guestGateway,
            fileStore: fileStore,
            runtimeStateURL: installedPaths.runtimeState,
            staleAfterSeconds: 60,
            now: { Date(timeIntervalSince1970: 1_800_000_061) }
        )

        let observation = reader.read()

        XCTAssertEqual(observation.loadedState?.vmIP, "192.168.64.2")
        XCTAssertNil(observation.freshState)
        XCTAssertTrue(observation.isPresent)
        XCTAssertFalse(observation.isFresh)
        XCTAssertTrue(observation.failureReasons.isEmpty)
    }

    func testGuestRuntimeStateObservationReaderReportsLoadedStateMTimeFailure() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        let guestGateway = RuntimeGuestGatewaySpy()
        guestGateway.runtimeState = GuestRuntimeStateDocument(
            vmIP: "192.168.64.2",
            updatedAt: "2026-05-24T00:00:00Z",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200"
        )
        let reader = RuntimeGuestRuntimeStateObservationReader(
            guestGateway: guestGateway,
            fileStore: fileStore,
            runtimeStateURL: installedPaths.runtimeState,
            staleAfterSeconds: 60,
            now: { Date(timeIntervalSince1970: 1_800_000_030) }
        )

        let observation = reader.read()

        XCTAssertEqual(observation.loadedState?.vmIP, "192.168.64.2")
        XCTAssertNil(observation.freshState)
        XCTAssertTrue(observation.isPresent)
        XCTAssertFalse(observation.isFresh)
        XCTAssertEqual(observation.failureReasons, [.guestRuntimeStateInvalid])
    }

    func testSnapshotReadsRuntimeStateThroughPorts() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        fileStore.files[installedPaths.containerLogs] = Data("container logs".utf8)
        fileStore.modificationDates[installedPaths.runtimeState] = Date(timeIntervalSince1970: 1_800_000_000)
        fileStore.modificationDates[installedPaths.containerLogs] = Date(timeIntervalSince1970: 1_800_000_060)

        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(
            exitCode: 0,
            stdout: "8080\n",
            stderr: ""
        )
        commandRunner.results[Constants.Commands.curl] = RuntimeProcessResult(
            exitCode: 0,
            stdout: #"{"activeWebSockets":1,"auditFileWriteFailures":0,"auditStdoutWriteFailures":0,"auditWriteFailures":0,"httpRequests":2,"redisIpWriteFailures":0,"socketIoEventsSeen":3,"socketIoParseFailures":0}"#,
            stderr: ""
        )
        let serviceManager = RuntimeServiceManagerSpy()
        serviceManager.states = [
            .vm: .loaded,
            .proxy: .loaded,
            .watchdog: .loaded,
        ]
        let httpProber = RuntimeHTTPProberSpy()
        httpProber.statuses[Constants.Runtime.proxyHealthURL(port: 8080)] = "200"
        httpProber.statuses[Constants.Runtime.redisUIHealthURL(port: 8080)] = "200"
        httpProber.statuses[Constants.Runtime.swaggerUIHealthURL(port: 8080)] = "200"
        let guestGateway = RuntimeGuestGatewaySpy()
        guestGateway.runtimeState = GuestRuntimeStateDocument(
            vmIP: "192.168.64.2",
            updatedAt: "2026-05-24T00:00:00Z",
            bootID: "boot-current",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            containerServices: [
                RuntimeContainerServiceObservation(
                    service: "audit-proxy",
                    name: "vitalserver-audit-proxy-1",
                    state: "running",
                    health: "healthy",
                    exitCode: 0
                ),
            ]
        )
        guestGateway.bootstrapResult = GuestBootstrapResultDocument(
            schemaVersion: 3,
            bootID: "boot-old",
            operation: .unknown("bootstrap"),
            status: .failed,
            message: "stale bootstrap failure",
            reasonCodes: [.guestBootstrapFailed],
            updatedAt: "2027-01-15T08:00:00Z"
        )

        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber,
            guestGateway: guestGateway
        )

        let snapshot = checker.snapshot()

        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertFalse(snapshot.failureReasons.contains(.guestBootstrapFailed))
        XCTAssertTrue(httpProber.requestedURLs.contains("http://127.0.0.1:8080/ready"))
        XCTAssertEqual(snapshot.containerObservation?.auditProxyHTTP, "200")
        XCTAssertEqual(snapshot.containerObservation?.auditProxyStatus?.socketIoEventsSeen, 3)
        XCTAssertEqual(snapshot.containerObservation?.runtimeStateUpdatedAt, "2026-05-24T00:00:00Z")
        XCTAssertEqual(snapshot.containerObservation?.runtimeStateFileUpdatedAt, "2027-01-15T08:00:00Z")
        XCTAssertEqual(snapshot.containerObservation?.containerLogsPresent, true)
        XCTAssertEqual(snapshot.containerObservation?.containerLogsBytes, 14)
        XCTAssertEqual(snapshot.containerObservation?.containerLogsUpdatedAt, "2027-01-15T08:01:00Z")
        XCTAssertEqual(snapshot.containerObservation?.composeServices.map(\.service), ["audit-proxy"])
        XCTAssertEqual(snapshot.vmIP, "192.168.64.2")
        XCTAssertEqual(snapshot.proxyPort, 8080)
        XCTAssertEqual(snapshot.hostProxyHTTP, "200")
        XCTAssertEqual(snapshot.rootfsBase, .present)
        XCTAssertEqual(snapshot.vmDisk, .present)
    }

    func testSnapshotDoesNotProbeGuestWhenRuntimeStateIsMissing() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[installedPaths.vmIPFile] = Data("192.168.64.3\n".utf8)
        let httpProber = RuntimeHTTPProberSpy()
        httpProber.statuses["http://192.168.64.3/ready"] = "200"
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: RuntimeServiceManagerSpy(),
            commandRunner: RuntimeCommandRunnerSpy(),
            httpProber: httpProber,
            guestGateway: RuntimeGuestGatewaySpy()
        )

        let snapshot = checker.snapshot()

        XCTAssertFalse(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertEqual(snapshot.proxyPort, InstallSettings.defaultProxyPort)
        XCTAssertEqual(snapshot.vmIP, nil)
        XCTAssertEqual(snapshot.guestHTTP, RuntimeHTTPStatusText.missingVMIP)
        XCTAssertFalse(httpProber.requestedURLs.contains("http://192.168.64.3/ready"))
        XCTAssertTrue(snapshot.failureReasons.contains(.missingVMBin))
        XCTAssertTrue(snapshot.failureReasons.contains(.missingRootfsBase))
    }

    func testSnapshotCarriesFreshVMLifecycleWithoutInferringRuntimeState() throws {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        fileStore.files[installedPaths.vmLifecycle] = try JSONEncoder.pretty.encode(RuntimeVMLifecycleDocument(
            state: .bootstrapping,
            startedAt: "2026-05-31T00:00:00Z",
            updatedAt: "2026-05-31T00:00:01Z",
            deadlineAt: "2026-05-31T00:10:00Z"
        ))

        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "80\n", stderr: "")
        let serviceManager = RuntimeServiceManagerSpy()
        serviceManager.states = [.vm: .loaded, .proxy: .loaded, .watchdog: .loaded]
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: RuntimeHTTPProberSpy(),
            guestGateway: RuntimeGuestGatewaySpy(),
            now: { ISO8601DateFormatter().date(from: "2026-05-31T00:05:00Z")! }
        )

        let snapshot = checker.snapshot()

        XCTAssertEqual(snapshot.vmLifecycle?.state, .bootstrapping)
        XCTAssertEqual(snapshot.vmState, .starting)
        XCTAssertFalse(snapshot.failureReasons.contains(.vmLifecycleDocumentStale))
    }

    func testSnapshotReportsExpiredBootLifecycleAsStale() throws {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[installedPaths.vmLifecycle] = try JSONEncoder.pretty.encode(RuntimeVMLifecycleDocument(
            state: .bootstrapping,
            startedAt: "2026-05-31T00:00:00Z",
            updatedAt: "2026-05-31T00:00:01Z",
            deadlineAt: "2026-05-31T00:10:00Z"
        ))
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: RuntimeServiceManagerSpy(),
            commandRunner: RuntimeCommandRunnerSpy(),
            httpProber: RuntimeHTTPProberSpy(),
            guestGateway: RuntimeGuestGatewaySpy(),
            now: { ISO8601DateFormatter().date(from: "2026-05-31T00:11:00Z")! }
        )

        let snapshot = checker.snapshot()

        XCTAssertEqual(snapshot.vmLifecycle?.state, .bootstrapping)
        XCTAssertTrue(snapshot.failureReasons.contains(.vmLifecycleDocumentStale))
    }

    func testSnapshotReportsRuntimeStateMissingGuestHTTPAsInvalid() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        fileStore.modificationDates[installedPaths.runtimeState] = Date(timeIntervalSince1970: 1_800_000_000)

        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "80\n", stderr: "")
        let serviceManager = RuntimeServiceManagerSpy()
        serviceManager.states = [.vm: .loaded, .proxy: .loaded, .watchdog: .loaded]
        let httpProber = RuntimeHTTPProberSpy()
        httpProber.statuses[Constants.Runtime.proxyHealthURL(port: 80)] = "200"
        httpProber.statuses[Constants.Runtime.redisUIHealthURL(port: 80)] = "200"
        httpProber.statuses[Constants.Runtime.swaggerUIHealthURL(port: 80)] = "200"
        let guestGateway = RuntimeGuestGatewaySpy()
        guestGateway.runtimeState = GuestRuntimeStateDocument(
            vmIP: "192.168.64.2",
            updatedAt: "2026-05-24T00:00:00Z",
            guestHTTP: nil,
            redisUIHTTP: "200",
            swaggerUIHTTP: "200"
        )

        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber,
            guestGateway: guestGateway
        )

        let snapshot = checker.snapshot()

        XCTAssertEqual(snapshot.guestHTTP, RuntimeHTTPStatusText.missingGuestHTTP)
        XCTAssertTrue(snapshot.failureReasons.contains(.guestRuntimeStateInvalid))
        XCTAssertTrue(snapshot.failureReasons.contains(.guestHTTP(RuntimeHTTPStatusText.missingGuestHTTP)))
        XCTAssertEqual(snapshot.vmState, .unreachable)
    }

    func testSnapshotReportsGuestRuntimeStateReadFailureAsInvalid() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()

        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "80\n", stderr: "")
        let serviceManager = RuntimeServiceManagerSpy()
        serviceManager.states = [.vm: .loaded, .proxy: .loaded, .watchdog: .loaded]
        let guestGateway = RuntimeGuestGatewaySpy()
        guestGateway.runtimeStateResult = .failed("runtime-state unreadable")

        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: RuntimeHTTPProberSpy(),
            guestGateway: guestGateway
        )

        let snapshot = checker.snapshot()

        XCTAssertNil(snapshot.vmIP)
        XCTAssertEqual(snapshot.guestHTTP, RuntimeHTTPStatusText.missingVMIP)
        XCTAssertTrue(snapshot.failureReasons.contains(.guestRuntimeStateInvalid))
    }

    func testSnapshotReportsInvalidHostProxyPortConfig() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(
            exitCode: 0,
            stdout: "not-a-port\n",
            stderr: ""
        )
        let httpProber = RuntimeHTTPProberSpy()
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: RuntimeFileStoreSpy(),
            serviceManager: RuntimeServiceManagerSpy(),
            commandRunner: commandRunner,
            httpProber: httpProber,
            guestGateway: RuntimeGuestGatewaySpy()
        )

        let snapshot = checker.snapshot()

        XCTAssertEqual(snapshot.proxyPort, InstallSettings.defaultProxyPort)
        XCTAssertTrue(snapshot.failureReasons.contains(.hostProxyConfigInvalid))
        XCTAssertTrue(httpProber.requestedURLs.contains(Constants.Runtime.proxyHealthURL(port: InstallSettings.defaultProxyPort)))
    }

    func testSnapshotDoesNotReportHostProxyConfigInvalidForConfiguredPort() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "8080\n", stderr: "")
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: RuntimeFileStoreSpy(),
            serviceManager: RuntimeServiceManagerSpy(),
            commandRunner: commandRunner,
            httpProber: RuntimeHTTPProberSpy(),
            guestGateway: RuntimeGuestGatewaySpy()
        )

        let snapshot = checker.snapshot()

        XCTAssertEqual(snapshot.proxyPort, 8080)
        XCTAssertFalse(snapshot.failureReasons.contains(.hostProxyConfigInvalid))
    }

    func testSnapshotReportsHostProxyListenerMismatchWhenExpectedProxyPIDIsUnavailable() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.Commands.lsof)] = Data()
        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "8080\n", stderr: "")
        commandRunner.results[Constants.Commands.lsof] = RuntimeProcessResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            nginx 1234 root 10u IPv4 0x01 0t0 TCP *:8080 (LISTEN)
            """,
            stderr: ""
        )
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: RuntimeServiceManagerSpy(),
            commandRunner: commandRunner,
            httpProber: RuntimeHTTPProberSpy(),
            guestGateway: RuntimeGuestGatewaySpy()
        )

        let snapshot = checker.snapshot()

        XCTAssertTrue(snapshot.failureReasons.contains(.hostProxyListenerMismatch(port: 8080, listeners: "nginx-1234")))
        XCTAssertFalse(snapshot.failureReasons.contains(.proxyPortInUse(port: 8080, listeners: "nginx-1234")))
    }

    func testSnapshotDoesNotReportProxyPortFailureForExpectedProxyPID() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.Commands.lsof)] = Data()
        fileStore.files[installedPaths.proxyNginxPID] = Data("1234\n".utf8)
        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "8080\n", stderr: "")
        commandRunner.results[Constants.Commands.lsof] = RuntimeProcessResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            nginx 1234 root 10u IPv4 0x01 0t0 TCP *:8080 (LISTEN)
            """,
            stderr: ""
        )
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: RuntimeServiceManagerSpy(),
            commandRunner: commandRunner,
            httpProber: RuntimeHTTPProberSpy(),
            guestGateway: RuntimeGuestGatewaySpy()
        )

        let snapshot = checker.snapshot()

        XCTAssertFalse(snapshot.failureReasons.contains(.hostProxyListenerMismatch(port: 8080, listeners: "nginx-1234")))
        XCTAssertFalse(snapshot.failureReasons.contains(.proxyPortInUse(port: 8080, listeners: "nginx-1234")))
    }

    func testSnapshotReportsHostProxyListenerScanFailure() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.Commands.lsof)] = Data()
        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "8080\n", stderr: "")
        commandRunner.results[Constants.Commands.lsof] = RuntimeProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "permission denied"
        )
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: RuntimeServiceManagerSpy(),
            commandRunner: commandRunner,
            httpProber: RuntimeHTTPProberSpy(),
            guestGateway: RuntimeGuestGatewaySpy()
        )

        let snapshot = checker.snapshot()

        XCTAssertTrue(snapshot.failureReasons.contains(.hostProxyHTTP("failed")))
        XCTAssertTrue(snapshot.failureReasons.contains(.hostProxyListenerScanFailed(port: 8080, exitCode: 1)))
    }

    func testSnapshotReportsAuditProxyStatusFailure() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "80\n", stderr: "")
        commandRunner.results[Constants.Commands.curl] = RuntimeProcessResult(exitCode: 7, stdout: "", stderr: "failed")
        let serviceManager = RuntimeServiceManagerSpy()
        serviceManager.states = [.vm: .loaded, .proxy: .loaded, .watchdog: .loaded]
        let httpProber = RuntimeHTTPProberSpy()
        httpProber.statuses[Constants.Runtime.proxyHealthURL(port: 80)] = "200"
        httpProber.statuses[Constants.Runtime.redisUIHealthURL(port: 80)] = "200"
        httpProber.statuses[Constants.Runtime.swaggerUIHealthURL(port: 80)] = "200"
        let guestGateway = RuntimeGuestGatewaySpy()
        guestGateway.runtimeState = GuestRuntimeStateDocument(
            vmIP: "192.168.64.2",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200"
        )
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber,
            guestGateway: guestGateway
        )

        let snapshot = checker.snapshot()

        XCTAssertEqual(snapshot.containerObservation?.auditProxyHTTP, "failed")
        XCTAssertTrue(snapshot.failureReasons.contains(.auditProxyHTTP("failed")))
    }

    func testSnapshotReportsInvalidAuditProxyStatusResponse() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "80\n", stderr: "")
        commandRunner.results[Constants.Commands.curl] = RuntimeProcessResult(exitCode: 0, stdout: "{invalid-json", stderr: "")
        let serviceManager = RuntimeServiceManagerSpy()
        serviceManager.states = [.vm: .loaded, .proxy: .loaded, .watchdog: .loaded]
        let httpProber = RuntimeHTTPProberSpy()
        httpProber.statuses[Constants.Runtime.proxyHealthURL(port: 80)] = "200"
        httpProber.statuses[Constants.Runtime.redisUIHealthURL(port: 80)] = "200"
        httpProber.statuses[Constants.Runtime.swaggerUIHealthURL(port: 80)] = "200"
        let guestGateway = RuntimeGuestGatewaySpy()
        guestGateway.runtimeState = GuestRuntimeStateDocument(
            vmIP: "192.168.64.2",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200"
        )
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber,
            guestGateway: guestGateway
        )

        let snapshot = checker.snapshot()

        XCTAssertEqual(snapshot.containerObservation?.auditProxyHTTP, RuntimeHTTPStatusText.invalidResponse)
        XCTAssertNil(snapshot.containerObservation?.auditProxyStatus)
        XCTAssertTrue(snapshot.failureReasons.contains(.auditProxyHTTP(RuntimeHTTPStatusText.invalidResponse)))
    }

    func testSnapshotReportsContainerLogMetadataReadFailure() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[installedPaths.containerLogs] = Data("container logs".utf8)
        fileStore.fileSizeErrors[installedPaths.containerLogs] = CocoaError(.fileReadNoPermission)
        fileStore.modificationDateErrors[installedPaths.containerLogs] = CocoaError(.fileReadNoPermission)
        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "80\n", stderr: "")
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: RuntimeServiceManagerSpy(),
            commandRunner: commandRunner,
            httpProber: RuntimeHTTPProberSpy(),
            guestGateway: RuntimeGuestGatewaySpy()
        )

        let snapshot = checker.snapshot()

        XCTAssertEqual(snapshot.containerObservation?.containerLogsPresent, true)
        XCTAssertNil(snapshot.containerObservation?.containerLogsBytes)
        XCTAssertNil(snapshot.containerObservation?.containerLogsUpdatedAt)
        XCTAssertEqual(
            snapshot.containerObservation?.containerLogsMetadataError,
            "size-read-failed,mtime-read-failed"
        )
    }

    func testSnapshotDoesNotUseStaleRuntimeStateForGuestProbes() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        fileStore.modificationDates[installedPaths.runtimeState] = Date(timeIntervalSince1970: 1_800_000_000)

        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "80\n", stderr: "")
        commandRunner.results[Constants.Commands.curl] = RuntimeProcessResult(exitCode: 7, stdout: "", stderr: "failed")
        let serviceManager = RuntimeServiceManagerSpy()
        serviceManager.states = [.vm: .loaded, .proxy: .loaded, .watchdog: .loaded]
        let httpProber = RuntimeHTTPProberSpy()
        httpProber.statuses[Constants.Runtime.proxyHealthURL(port: 80)] = "failed"
        httpProber.statuses[Constants.Runtime.redisUIHealthURL(port: 80)] = "failed"
        httpProber.statuses[Constants.Runtime.swaggerUIHealthURL(port: 80)] = "failed"
        httpProber.statuses["http://192.168.64.8/ready"] = "failed"
        let guestGateway = RuntimeGuestGatewaySpy()
        guestGateway.runtimeState = GuestRuntimeStateDocument(
            vmIP: "192.168.64.8",
            updatedAt: "2026-05-26T14:52:50Z",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            containerServices: [
                RuntimeContainerServiceObservation(service: "app", state: "running", health: "healthy"),
            ]
        )
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber,
            guestGateway: guestGateway,
            now: { Date(timeIntervalSince1970: 1_800_000_120) }
        )

        let snapshot = checker.snapshot()

        XCTAssertEqual(snapshot.vmIP, nil)
        XCTAssertEqual(snapshot.guestHTTP, RuntimeHTTPStatusText.missingVMIP)
        XCTAssertFalse(httpProber.requestedURLs.contains("http://192.168.64.8/ready"))
        XCTAssertTrue(snapshot.failureReasons.contains(.guestRuntimeStateStale))
        XCTAssertFalse(snapshot.failureReasons.contains(.guestHTTP("failed")))
        XCTAssertEqual(snapshot.containerObservation?.runtimeStateUpdatedAt, nil)
        XCTAssertEqual(snapshot.containerObservation?.runtimeStateFileUpdatedAt, "2027-01-15T08:00:00Z")
        XCTAssertEqual(snapshot.containerObservation?.composeServices, [])
    }

    func testSnapshotReportsUnreadableRuntimeStateMetadataAsInvalid() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()

        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "80\n", stderr: "")
        let serviceManager = RuntimeServiceManagerSpy()
        serviceManager.states = [.vm: .loaded, .proxy: .loaded, .watchdog: .loaded]
        let guestGateway = RuntimeGuestGatewaySpy()
        guestGateway.runtimeState = GuestRuntimeStateDocument(
            vmIP: "192.168.64.8",
            updatedAt: "2026-05-26T14:52:50Z",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200"
        )
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: RuntimeHTTPProberSpy(),
            guestGateway: guestGateway
        )

        let snapshot = checker.snapshot()

        XCTAssertEqual(snapshot.vmState, .stale)
        XCTAssertTrue(snapshot.failureReasons.contains(.guestRuntimeStateStale))
        XCTAssertTrue(snapshot.failureReasons.contains(.guestRuntimeStateInvalid))
        XCTAssertEqual(snapshot.vmIP, nil)
    }

    func testSnapshotDoesNotInferVMDiagnosticErrorsFromLaunchdLogs() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        fileStore.files[installedPaths.centralRuntimeLogsDirectory.appendingPathComponent("launchd.err.log")] = Data(
            #"failed to start VM: The storage device attachment is invalid."#.utf8
        )
        fileStore.files[installedPaths.centralRuntimeLogsDirectory.appendingPathComponent("launchd.out.log")] = Data("""
        EXT4-fs error (device vda1): inode checksum invalid
        EXT4-fs (vda1): Remounting filesystem read-only
        systemd-journald: Failed to write entry: Input/output error
        """.utf8)

        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "80\n", stderr: "")
        commandRunner.results[Constants.Commands.curl] = RuntimeProcessResult(exitCode: 7, stdout: "", stderr: "failed")
        let serviceManager = RuntimeServiceManagerSpy()
        serviceManager.states = [.vm: .loaded, .proxy: .loaded, .watchdog: .loaded]
        let httpProber = RuntimeHTTPProberSpy()
        httpProber.statuses[Constants.Runtime.proxyHealthURL(port: 80)] = "failed"
        httpProber.statuses[Constants.Runtime.redisUIHealthURL(port: 80)] = "failed"
        httpProber.statuses[Constants.Runtime.swaggerUIHealthURL(port: 80)] = "failed"
        httpProber.statuses["http://192.168.64.8/ready"] = "failed"

        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber,
            guestGateway: RuntimeGuestGatewaySpy()
        )

        let snapshot = checker.snapshot()

        XCTAssertEqual(snapshot.vmState, .starting)
        XCTAssertFalse(snapshot.vmErrors.contains(.launchFailed("virtualization")))
        XCTAssertFalse(snapshot.vmErrors.contains(.diskAttachmentInvalid))
        XCTAssertFalse(snapshot.vmErrors.contains(.guestFilesystemError))
        XCTAssertFalse(snapshot.vmErrors.contains(.guestFilesystemReadOnly))
        XCTAssertFalse(snapshot.vmErrors.contains(.guestDiskIO))
    }
}

private final class RuntimeCommandRunnerSpy: RuntimeCommandRunner {
    var results: [String: RuntimeProcessResult] = [:]

    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        results[executable] ?? RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "")
    }

    func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult {
        run(executable, arguments: arguments)
    }
}

private final class RuntimeHTTPProberSpy: RuntimeHTTPProber {
    var statuses: [String: String] = [:]
    var requestedURLs: [String] = []

    func statusCode(url: String) -> String {
        requestedURLs.append(url)
        return statuses[url] ?? "failed"
    }
}

private final class RuntimeServiceManagerSpy: RuntimeServiceManager {
    var states: [RuntimeManagedService: RuntimeServiceState] = [:]

    func state(service: RuntimeManagedService) -> RuntimeServiceState {
        states[service] ?? .notLoaded
    }

    func start(service: RuntimeManagedService, plist: String) {}
    func restart(service: RuntimeManagedService) {}
    func stop(service: RuntimeManagedService) {}

    func setEnabled(service: RuntimeManagedService, enabled: Bool) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}

private final class RuntimeGuestGatewaySpy: RuntimeGuestGateway {
    var runtimeState: GuestRuntimeStateDocument?
    var runtimeStateResult: RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>?
    var bootstrapResult: GuestBootstrapResultDocument?

    func loadRuntimeStateDocument() -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument> {
        if let runtimeStateResult {
            return runtimeStateResult
        }
        return runtimeState.map(RuntimeGuestDocumentLoadResult.loaded) ?? .missing
    }

    func loadBootstrapResultDocument() -> RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument> {
        bootstrapResult.map(RuntimeGuestDocumentLoadResult.loaded) ?? .missing
    }

    func removeUpdateActivationResult() throws {}
    func writeUpdateActivationRequest(_ request: RuntimeGuestActivationRequest) throws {}
    func loadUpdateActivationResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument> { .missing }
    func removeUpdateShutdownResult() throws {}
    func writeUpdateShutdownRequest(_ request: RuntimeGuestShutdownRequest) throws {}
    func loadUpdateShutdownResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument> { .missing }
    func removeDatastoreRepairResult() throws {}
    func writeDatastoreRepairRequest(_ request: RuntimeDatastoreRepairRequest) throws {}
    func loadDatastoreRepairResultDocument() -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument> { .missing }
}
