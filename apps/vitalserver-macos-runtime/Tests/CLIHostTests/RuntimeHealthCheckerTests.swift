import Foundation
import Bootstrap
import Application
import Contracts
import Domain
import OutboundAdapters
import InboundAdapters
@testable import CLIHost
import XCTest
import Errors

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
        XCTAssertNil(observation.readIssue)
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
        XCTAssertNil(observation.readIssue)
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
        guard case .metadataReadFailed(let message) = observation.readIssue else {
            XCTFail("Expected metadataReadFailed read issue")
            return
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testGuestRuntimeStateObservationReaderPreservesMissingAsNotFresh() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let reader = RuntimeGuestRuntimeStateObservationReader(
            guestGateway: RuntimeGuestGatewaySpy(),
            fileStore: RuntimeFileStoreSpy(),
            runtimeStateURL: installedPaths.runtimeState,
            staleAfterSeconds: 60,
            now: { Date(timeIntervalSince1970: 1_800_000_030) }
        )

        let observation = reader.read()

        XCTAssertNil(observation.loadedState)
        XCTAssertNil(observation.freshState)
        XCTAssertFalse(observation.isPresent)
        XCTAssertFalse(observation.isFresh)
        XCTAssertNil(observation.readIssue)
    }

    func testGuestRuntimeStateObservationReaderPreservesReadFailureAsInvalidNotFresh() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let guestGateway = RuntimeGuestGatewaySpy()
        guestGateway.runtimeStateResult = .failed("runtime-state unreadable")
        let reader = RuntimeGuestRuntimeStateObservationReader(
            guestGateway: guestGateway,
            fileStore: RuntimeFileStoreSpy(),
            runtimeStateURL: installedPaths.runtimeState,
            staleAfterSeconds: 60,
            now: { Date(timeIntervalSince1970: 1_800_000_030) }
        )

        let observation = reader.read()

        XCTAssertNil(observation.loadedState)
        XCTAssertNil(observation.freshState)
        XCTAssertFalse(observation.isPresent)
        XCTAssertFalse(observation.isFresh)
        XCTAssertEqual(observation.readIssue, .loadFailed("runtime-state unreadable"))
    }

    func testSnapshotReadsRuntimeStateThroughPorts() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        fileStore.files[installedPaths.runtimeState] = Data("{}".utf8)
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
                    service: "recorder-ingress",
                    name: "vitalserver-recorder-ingress-1",
                    state: "running",
                    health: "healthy",
                    exitCode: 0
                ),
            ],
            vitalDBObservation: healthyVitalDBObservation()
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

        let snapshot = healthSnapshot(from: checker)

        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertFalse(snapshot.failureReasons.contains(.guestBootstrapFailed))
        XCTAssertTrue(httpProber.requestedURLs.contains("http://127.0.0.1:8080/ready"))
        XCTAssertEqual(snapshot.containerObservation?.recorderIngressHTTP, "200")
        XCTAssertEqual(snapshot.containerObservation?.recorderIngressStatus?.socketIoEventsSeen, 3)
        XCTAssertNil(snapshot.containerObservation?.recorderIngressStatusReadError)
        XCTAssertEqual(snapshot.containerObservation?.runtimeStateUpdatedAt, "2026-05-24T00:00:00Z")
        XCTAssertEqual(snapshot.containerObservation?.runtimeStateFileUpdatedAt, "2027-01-15T08:00:00Z")
        XCTAssertNil(snapshot.containerObservation?.runtimeStateFileMetadataError)
        XCTAssertEqual(snapshot.containerObservation?.containerLogsPresent, true)
        XCTAssertEqual(snapshot.containerObservation?.containerLogsBytes, 14)
        XCTAssertEqual(snapshot.containerObservation?.containerLogsUpdatedAt, "2027-01-15T08:01:00Z")
        XCTAssertEqual(snapshot.containerObservation?.composeServices.map(\.service), ["recorder-ingress"])
        XCTAssertEqual(snapshot.containerObservation?.composeServicesReadState, .loaded)
        XCTAssertNil(snapshot.containerObservation?.composeServicesReadError)
        XCTAssertEqual(snapshot.vmIP, "192.168.64.2")
        XCTAssertEqual(snapshot.proxyPort, 8080)
        XCTAssertEqual(snapshot.hostProxyHTTP, "200")
        XCTAssertEqual(snapshot.rootfsBase, .present)
        XCTAssertEqual(snapshot.vmDisk, .present)
    }

    func testSnapshotPreservesExecutableInspectionFailures() {
        let fixture = healthyRuntimeFixture(guestHTTP: "200")
        fixture.fileStore.fileStates[Constants.InstallPaths.vmBin] = .inspectFailed("permission denied")
        fixture.fileStore.fileStates[Constants.InstallPaths.proxyRun] = .inspectFailed("permission denied")

        let snapshot = healthSnapshot(from: fixture.checker)

        XCTAssertEqual(snapshot.vmExecutable, .inspectFailed("permission denied"))
        XCTAssertEqual(snapshot.proxyExecutable, .inspectFailed("permission denied"))
        XCTAssertEqual(snapshot.vmState, .notInstalled)
        XCTAssertTrue(snapshot.failureReasons.contains(.missingVMBin))
        XCTAssertTrue(snapshot.failureReasons.contains(.missingProxyRunner))
    }

    func testSnapshotPreservesArtifactInspectionFailures() {
        let fixture = healthyRuntimeFixture(guestHTTP: "200")
        let rootfsBase = fixture.installedPaths.runtimeDirectory
            .appendingPathComponent(Constants.Artifacts.rootfsBase)
        let vmDisk = fixture.installedPaths.runtimeDirectory
            .appendingPathComponent(Constants.BootAssets.disk)
        fixture.fileStore.fileStates[rootfsBase.path] = .inspectFailed("rootfs permission denied")
        fixture.fileStore.fileStates[vmDisk.path] = .inspectFailed("vm disk permission denied")

        let snapshot = healthSnapshot(from: fixture.checker)

        XCTAssertEqual(snapshot.rootfsBase, .inspectFailed("rootfs permission denied"))
        XCTAssertEqual(snapshot.vmDisk, .inspectFailed("vm disk permission denied"))
        XCTAssertEqual(snapshot.vmState, .failed)
        XCTAssertTrue(snapshot.failureReasons.contains(.missingRootfsBase))
        XCTAssertTrue(snapshot.failureReasons.contains(.missingVMDisk))
    }

    func testSnapshotReportsMissingVitalDBObservationFromFreshRuntimeState() {
        let fixture = healthyRuntimeFixture(guestHTTP: "200")
        fixture.guestGateway.runtimeState = GuestRuntimeStateDocument(
            vmIP: "192.168.64.2",
            updatedAt: "2026-05-24T00:00:00Z",
            bootID: "boot-current",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            containerServices: []
        )

        let snapshot = healthSnapshot(from: fixture.checker)

        XCTAssertEqual(snapshot.failureReasons, [.vitalDBObservationMissing])
        XCTAssertNil(snapshot.vitalDBObservation)
        XCTAssertFalse(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
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

        let snapshot = healthSnapshot(from: checker)

        XCTAssertFalse(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertNil(snapshot.proxyPort)
        XCTAssertEqual(snapshot.vmIP, nil)
        XCTAssertEqual(snapshot.guestHTTP, RuntimeHTTPStatusText.missingVMIP)
        XCTAssertFalse(httpProber.requestedURLs.contains("http://192.168.64.3/ready"))
        XCTAssertFalse(httpProber.requestedURLs.contains(Constants.Runtime.proxyHealthURL(port: RuntimeInstallSettings.defaultProxyPort)))
        XCTAssertEqual(snapshot.containerObservation?.composeServicesReadState, .missing)
        XCTAssertEqual(snapshot.containerObservation?.composeServicesReadError, "guest-runtime-state-missing")
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

        let snapshot = healthSnapshot(from: checker)

        XCTAssertEqual(snapshot.vmLifecycle?.state, .bootstrapping)
        XCTAssertEqual(snapshot.vmState, .starting)
        XCTAssertTrue(snapshot.vmErrors.contains(.runtimeStateMissing))
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

        let snapshot = healthSnapshot(from: checker)

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

        let snapshot = healthSnapshot(from: checker)

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

        let snapshot = healthSnapshot(from: checker)

        XCTAssertNil(snapshot.vmIP)
        XCTAssertEqual(snapshot.guestHTTP, RuntimeHTTPStatusText.missingVMIP)
        XCTAssertTrue(snapshot.failureReasons.contains(.guestRuntimeStateInvalid))
    }

    func testSnapshotReportsMissingBootstrapResultWhenGuestHTTPFailsOutsideBootstrapLifecycle() {
        let fixture = healthyRuntimeFixture(guestHTTP: "failed")
        let checker = RuntimeHealthChecker(
            installedPaths: fixture.installedPaths,
            fileStore: fixture.fileStore,
            serviceManager: fixture.serviceManager,
            commandRunner: fixture.commandRunner,
            httpProber: fixture.httpProber,
            guestGateway: fixture.guestGateway
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertTrue(snapshot.vmErrors.contains(.guestBootstrapResultMissing))
        XCTAssertTrue(snapshot.failureReasons.contains(.guestBootstrapResultMissing))
        XCTAssertEqual(snapshot.vmState, .unreachable)
    }

    func testSnapshotReportsUnavailableBootstrapResultWhenGuestHTTPFails() {
        let fixture = healthyRuntimeFixture(guestHTTP: "failed")
        fixture.guestGateway.bootstrapResultResult = .failed("permission denied")
        let checker = RuntimeHealthChecker(
            installedPaths: fixture.installedPaths,
            fileStore: fixture.fileStore,
            serviceManager: fixture.serviceManager,
            commandRunner: fixture.commandRunner,
            httpProber: fixture.httpProber,
            guestGateway: fixture.guestGateway
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertTrue(snapshot.vmErrors.contains(.guestBootstrapResultUnavailable))
        XCTAssertTrue(snapshot.failureReasons.contains(.guestBootstrapResultUnavailable))
        XCTAssertEqual(snapshot.vmState, .unreachable)
    }

    func testSnapshotDoesNotReportMissingBootstrapResultWhileLifecycleIsBootstrapping() throws {
        let fixture = healthyRuntimeFixture(guestHTTP: RuntimeHTTPStatusText.bootstrapPending)
        fixture.fileStore.files[fixture.installedPaths.vmLifecycle] = try JSONEncoder.pretty.encode(RuntimeVMLifecycleDocument(
            state: .bootstrapping,
            startedAt: "2026-05-31T00:00:00Z",
            updatedAt: "2026-05-31T00:00:01Z",
            deadlineAt: "2026-05-31T00:10:00Z"
        ))
        let checker = RuntimeHealthChecker(
            installedPaths: fixture.installedPaths,
            fileStore: fixture.fileStore,
            serviceManager: fixture.serviceManager,
            commandRunner: fixture.commandRunner,
            httpProber: fixture.httpProber,
            guestGateway: fixture.guestGateway,
            now: { ISO8601DateFormatter().date(from: "2026-05-31T00:05:00Z")! }
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertFalse(snapshot.vmErrors.contains(.guestBootstrapResultMissing))
        XCTAssertFalse(snapshot.failureReasons.contains(.guestBootstrapResultMissing))
        XCTAssertEqual(snapshot.vmState, .starting)
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

        let snapshot = healthSnapshot(from: checker)

        XCTAssertNil(snapshot.proxyPort)
        XCTAssertEqual(snapshot.hostProxyHTTP, RuntimeHTTPStatusText.missingProxyPort)
        XCTAssertEqual(snapshot.redisUIHTTP, RuntimeHTTPStatusText.missingProxyPort)
        XCTAssertEqual(snapshot.swaggerUIHTTP, RuntimeHTTPStatusText.missingProxyPort)
        XCTAssertEqual(snapshot.containerObservation?.recorderIngressHTTP, RuntimeHTTPStatusText.missingProxyPort)
        XCTAssertEqual(snapshot.containerObservation?.recorderIngressStatusReadError, RuntimeHTTPStatusText.missingProxyPort)
        XCTAssertTrue(snapshot.failureReasons.contains(.hostProxyConfigInvalid))
        XCTAssertFalse(httpProber.requestedURLs.contains(Constants.Runtime.proxyHealthURL(port: RuntimeInstallSettings.defaultProxyPort)))
    }

    func testSnapshotPreservesHostProxyPortReadFailureState() {
        let cases: [(RuntimeProcessResult, RuntimeProxyPortReadState)] = [
            (
                RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "Entry, :EnvironmentVariables:VITALSERVER_PROXY_PORT, Does Not Exist"),
                .commandFailed(
                    exitCode: 1,
                    reason: "exitCode=1 stderr=Entry, :EnvironmentVariables:VITALSERVER_PROXY_PORT, Does Not Exist"
                )
            ),
            (
                RuntimeProcessResult(exitCode: 0, stdout: "\n", stderr: ""),
                .empty
            ),
            (
                RuntimeProcessResult(exitCode: 0, stdout: "not-a-port\n", stderr: ""),
                .invalid("not-a-port")
            ),
            (
                RuntimeProcessResult(exitCode: 0, stdout: "70000\n", stderr: ""),
                .outOfRange(70000)
            ),
            (
                RuntimeProcessResult(exitCode: 2, stdout: "", stderr: "permission denied"),
                .commandFailed(exitCode: 2, reason: "exitCode=2 stderr=permission denied")
            ),
        ]

        for (result, expectedState) in cases {
            let fixture = healthyRuntimeFixture(guestHTTP: "200")
            fixture.commandRunner.results[Constants.Commands.plistBuddy] = result

            let snapshot = healthSnapshot(from: fixture.checker)

            XCTAssertEqual(snapshot.proxyPortReadState, expectedState)
            XCTAssertNil(snapshot.proxyPort)
            XCTAssertTrue(snapshot.failureReasons.contains(.hostProxyConfigInvalid))
            XCTAssertEqual(snapshot.hostProxyHTTP, RuntimeHTTPStatusText.missingProxyPort)
        }
    }

    func testSnapshotReportsMissingHostProxyPortConfigFromPlistPathState() {
        let fixture = healthyRuntimeFixture(guestHTTP: "200")
        let plistPath = RuntimeManagedServicePaths.launchDaemonPlist(.proxy)
        fixture.fileStore.files.removeValue(forKey: URL(fileURLWithPath: plistPath))
        fixture.fileStore.pathStates[plistPath] = .missing
        fixture.commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "permission denied"
        )

        let snapshot = healthSnapshot(from: fixture.checker)

        XCTAssertEqual(
            snapshot.proxyPortReadState,
            .missing("proxy launchd plist missing path=\(plistPath)")
        )
        XCTAssertTrue(snapshot.failureReasons.contains(.hostProxyConfigInvalid))
    }

    func testSnapshotDoesNotInferMissingHostProxyPortConfigFromCommandOutput() {
        let fixture = healthyRuntimeFixture(guestHTTP: "200")
        fixture.commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "Entry, :EnvironmentVariables:VITALSERVER_PROXY_PORT, Does Not Exist"
        )

        let snapshot = healthSnapshot(from: fixture.checker)

        XCTAssertEqual(
            snapshot.proxyPortReadState,
            .commandFailed(
                exitCode: 1,
                reason: "exitCode=1 stderr=Entry, :EnvironmentVariables:VITALSERVER_PROXY_PORT, Does Not Exist"
            )
        )
        XCTAssertTrue(snapshot.failureReasons.contains(.hostProxyConfigInvalid))
    }

    func testSnapshotReportsHostProxyPortConfigPathInspectionFailure() {
        let fixture = healthyRuntimeFixture(guestHTTP: "200")
        let plistPath = RuntimeManagedServicePaths.launchDaemonPlist(.proxy)
        fixture.fileStore.pathStates[plistPath] = .inspectFailed("permission denied")
        fixture.commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "read failed"
        )

        let snapshot = healthSnapshot(from: fixture.checker)

        XCTAssertEqual(
            snapshot.proxyPortReadState,
            .commandFailed(
                exitCode: 1,
                reason: "exitCode=1 stderr=read failed plistPathInspectionFailed path=\(plistPath) reason=permission denied"
            )
        )
        XCTAssertTrue(snapshot.failureReasons.contains(.hostProxyConfigInvalid))
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

        let snapshot = healthSnapshot(from: checker)

        XCTAssertEqual(snapshot.proxyPort, 8080)
        XCTAssertEqual(snapshot.proxyPortReadState, .loaded(8080))
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

        let snapshot = healthSnapshot(from: checker)

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

        let snapshot = healthSnapshot(from: checker)

        XCTAssertFalse(snapshot.failureReasons.contains(.hostProxyListenerMismatch(port: 8080, listeners: "nginx-1234")))
        XCTAssertFalse(snapshot.failureReasons.contains(.proxyPortInUse(port: 8080, listeners: "nginx-1234")))
    }

    func testProxyNginxPIDReadKeepsMissingEmptyLoadedAndReadFailureDistinct() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: RuntimeServiceManagerSpy(),
            commandRunner: RuntimeCommandRunnerSpy(),
            httpProber: RuntimeHTTPProberSpy(),
            guestGateway: RuntimeGuestGatewaySpy()
        )

        XCTAssertEqual(checker.readInstalledProxyNginxPID(), .missing)

        fileStore.files[installedPaths.proxyNginxPID] = Data("\n".utf8)
        XCTAssertEqual(checker.readInstalledProxyNginxPID(), .empty)

        fileStore.files[installedPaths.proxyNginxPID] = Data("1234\n".utf8)
        XCTAssertEqual(checker.readInstalledProxyNginxPID(), .loaded("1234"))

        fileStore.readDataErrors[installedPaths.proxyNginxPID] = CocoaError(.fileReadNoPermission)
        guard case .readFailed = checker.readInstalledProxyNginxPID() else {
            return XCTFail("expected proxy nginx PID read failure")
        }

        fileStore.pathStates[installedPaths.proxyNginxPID.path] = .inspectFailed("permission denied")
        XCTAssertEqual(
            checker.readInstalledProxyNginxPID(),
            .readFailed("proxy nginx PID path inspection failed path=\(installedPaths.proxyNginxPID.path) reason=permission denied")
        )

        fileStore.pathStates[installedPaths.proxyNginxPID.path] = .directory
        XCTAssertEqual(
            checker.readInstalledProxyNginxPID(),
            .readFailed("proxy nginx PID path state is unexpected path=\(installedPaths.proxyNginxPID.path) state=directory")
        )
    }

    func testSnapshotReportsHostProxyListenerScanUnavailableWhenLsofIsMissing() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "8080\n", stderr: "")
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: RuntimeServiceManagerSpy(),
            commandRunner: commandRunner,
            httpProber: RuntimeHTTPProberSpy(),
            guestGateway: RuntimeGuestGatewaySpy()
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertTrue(snapshot.failureReasons.contains(.hostProxyListenerScanUnavailable))
    }

    func testSnapshotReportsHostProxyListenerScanInspectionFailureSeparatelyFromUnavailable() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.fileStates[Constants.Commands.lsof] = .inspectFailed("permission denied")
        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "8080\n", stderr: "")
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: RuntimeServiceManagerSpy(),
            commandRunner: commandRunner,
            httpProber: RuntimeHTTPProberSpy(),
            guestGateway: RuntimeGuestGatewaySpy()
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertTrue(snapshot.failureReasons.contains(
            .hostProxyListenerScanInspectionFailed("path=\(Constants.Commands.lsof) reason=permission denied")
        ))
        XCTAssertFalse(snapshot.failureReasons.contains(.hostProxyListenerScanUnavailable))
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

        let snapshot = healthSnapshot(from: checker)

        XCTAssertTrue(snapshot.failureReasons.contains(.hostProxyHTTP("failed")))
        XCTAssertTrue(snapshot.failureReasons.contains(.hostProxyListenerScanFailed(port: 8080, exitCode: 1)))
    }

    func testSnapshotTreatsOnlyEmptyLsofExitOneAsNoListeners() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.Commands.lsof)] = Data()
        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "8080\n", stderr: "")
        commandRunner.results[Constants.Commands.lsof] = RuntimeProcessResult(
            exitCode: 1,
            stdout: "",
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

        let snapshot = healthSnapshot(from: checker)

        XCTAssertFalse(snapshot.failureReasons.contains(.hostProxyListenerScanFailed(port: 8080, exitCode: 1)))
    }

    func testSnapshotReportsEmptyUnexpectedLsofExitAsScanFailure() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.Commands.lsof)] = Data()
        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "8080\n", stderr: "")
        commandRunner.results[Constants.Commands.lsof] = RuntimeProcessResult(
            exitCode: 2,
            stdout: "",
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

        let snapshot = healthSnapshot(from: checker)

        XCTAssertTrue(snapshot.failureReasons.contains(.hostProxyListenerScanFailed(port: 8080, exitCode: 2)))
    }

    func testSnapshotReportsHostProxyListenerScanFailureWhenOutputCannotBeDecoded() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.Commands.lsof)] = Data()
        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "8080\n", stderr: "")
        commandRunner.results[Constants.Commands.lsof] = RuntimeProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "",
            outputIssues: [
                RuntimeCommandOutputIssue(stream: .stdout, message: "lsof stdout is not valid UTF-8"),
            ]
        )
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: RuntimeServiceManagerSpy(),
            commandRunner: commandRunner,
            httpProber: RuntimeHTTPProberSpy(),
            guestGateway: RuntimeGuestGatewaySpy()
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertTrue(snapshot.failureReasons.contains(.hostProxyHTTP("failed")))
        XCTAssertTrue(snapshot.failureReasons.contains(.hostProxyListenerScanFailed(port: 8080, exitCode: 1)))
    }

    func testSnapshotReportsHostProxyListenerScanFailureWhenLsofOutputIsMalformed() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.Commands.lsof)] = Data()
        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "8080\n", stderr: "")
        commandRunner.results[Constants.Commands.lsof] = RuntimeProcessResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            malformed
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

        let snapshot = healthSnapshot(from: checker)

        XCTAssertTrue(snapshot.failureReasons.contains(.hostProxyListenerScanFailed(port: 8080, exitCode: 0)))
        XCTAssertFalse(snapshot.failureReasons.contains(.hostProxyListenerMismatch(port: 8080, listeners: "malformed")))
    }

    func testSnapshotReportsRecorderIngressStatusFailure() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        fileStore.modificationDates[installedPaths.runtimeState] = Date()
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

        let snapshot = healthSnapshot(from: checker)

        XCTAssertEqual(snapshot.containerObservation?.recorderIngressHTTP, "failed")
        XCTAssertEqual(snapshot.containerObservation?.recorderIngressStatusReadState, .commandFailed)
        XCTAssertTrue(snapshot.containerObservation?.recorderIngressStatusReadError?.hasPrefix("command-failed-7 ") == true)
        XCTAssertEqual(snapshot.containerObservation?.composeServicesReadState, .missing)
        XCTAssertEqual(snapshot.containerObservation?.composeServices, [])
        XCTAssertEqual(snapshot.containerObservation?.composeServicesReadError, "container-services-missing")
        XCTAssertTrue(snapshot.failureReasons.contains(.recorderIngressHTTP("failed")))
    }

    func testSnapshotReportsInvalidRecorderIngressStatusResponse() throws {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[URL(fileURLWithPath: RuntimeManagedServicePaths.launchDaemonPlist(.proxy))] = Data()
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

        let snapshot = healthSnapshot(from: checker)

        XCTAssertEqual(snapshot.containerObservation?.recorderIngressHTTP, RuntimeHTTPStatusText.invalidResponse)
        XCTAssertEqual(snapshot.containerObservation?.recorderIngressStatusReadState, .invalidResponse)
        XCTAssertNil(snapshot.containerObservation?.recorderIngressStatus)
        let readError = try XCTUnwrap(snapshot.containerObservation?.recorderIngressStatusReadError)
        XCTAssertTrue(readError.hasPrefix("decode-failed reason="))
        XCTAssertTrue(readError.contains("dataCorrupted"))
        XCTAssertTrue(snapshot.failureReasons.contains(.recorderIngressHTTP(RuntimeHTTPStatusText.invalidResponse)))
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

        let snapshot = healthSnapshot(from: checker)

        XCTAssertEqual(snapshot.containerObservation?.containerLogsPresent, true)
        XCTAssertNil(snapshot.containerObservation?.containerLogsBytes)
        XCTAssertNil(snapshot.containerObservation?.containerLogsUpdatedAt)
        XCTAssertTrue(snapshot.containerObservation?.containerLogsMetadataError?.contains("size-read-failed reason=") == true)
        XCTAssertTrue(snapshot.containerObservation?.containerLogsMetadataError?.contains("mtime-read-failed reason=") == true)
    }

    func testSnapshotReportsContainerLogPathInspectionFailure() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.pathStates[installedPaths.containerLogs.path] = .inspectFailed("permission denied")
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

        let snapshot = healthSnapshot(from: checker)

        XCTAssertEqual(snapshot.containerObservation?.containerLogsPresent, false)
        XCTAssertNil(snapshot.containerObservation?.containerLogsBytes)
        XCTAssertNil(snapshot.containerObservation?.containerLogsUpdatedAt)
        XCTAssertEqual(
            snapshot.containerObservation?.containerLogsMetadataError,
            "container logs path inspection failed path=\(installedPaths.containerLogs.path) reason=permission denied"
        )
    }

    func testSnapshotDoesNotUseStaleRuntimeStateForGuestProbes() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        fileStore.files[installedPaths.runtimeState] = Data("{}".utf8)
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

        let snapshot = healthSnapshot(from: checker)

        XCTAssertEqual(snapshot.vmIP, nil)
        XCTAssertEqual(snapshot.guestHTTP, RuntimeHTTPStatusText.missingVMIP)
        XCTAssertFalse(httpProber.requestedURLs.contains("http://192.168.64.8/ready"))
        XCTAssertTrue(snapshot.failureReasons.contains(.guestRuntimeStateStale))
        XCTAssertFalse(snapshot.failureReasons.contains(.guestHTTP("failed")))
        XCTAssertEqual(snapshot.containerObservation?.runtimeStateUpdatedAt, nil)
        XCTAssertEqual(snapshot.containerObservation?.runtimeStateFileUpdatedAt, "2027-01-15T08:00:00Z")
        XCTAssertNil(snapshot.containerObservation?.runtimeStateFileMetadataError)
        XCTAssertEqual(snapshot.containerObservation?.composeServicesReadState, .stale)
        XCTAssertEqual(snapshot.containerObservation?.composeServices, [])
        XCTAssertEqual(snapshot.containerObservation?.composeServicesReadError, "guest-runtime-state-stale")
    }

    func testSnapshotReportsUnreadableRuntimeStateMetadataAsInvalid() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        fileStore.files[installedPaths.runtimeState] = Data("{}".utf8)
        fileStore.modificationDateErrors[installedPaths.runtimeState] = CocoaError(.fileReadNoPermission)

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

        let snapshot = healthSnapshot(from: checker)

        XCTAssertEqual(snapshot.vmState, .unreachable)
        XCTAssertFalse(snapshot.failureReasons.contains(.guestRuntimeStateStale))
        XCTAssertTrue(snapshot.failureReasons.contains(.guestRuntimeStateInvalid))
        XCTAssertEqual(snapshot.vmIP, nil)
        XCTAssertTrue(
            snapshot.containerObservation?.runtimeStateFileMetadataError?
                .contains("mtime-read-failed path=\(installedPaths.runtimeState.path)") == true
        )
        XCTAssertEqual(snapshot.containerObservation?.composeServicesReadState, .invalid)
        XCTAssertEqual(snapshot.containerObservation?.composeServicesReadError, "guest-runtime-state-invalid")
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

        let snapshot = healthSnapshot(from: checker)

        XCTAssertEqual(snapshot.vmState, .unreachable)
        XCTAssertTrue(snapshot.vmErrors.contains(.runtimeStateMissing))
        XCTAssertFalse(snapshot.vmErrors.contains(.launchFailed("virtualization")))
        XCTAssertFalse(snapshot.vmErrors.contains(.diskAttachmentInvalid))
        XCTAssertFalse(snapshot.vmErrors.contains(.guestFilesystemError))
        XCTAssertFalse(snapshot.vmErrors.contains(.guestFilesystemReadOnly))
        XCTAssertFalse(snapshot.vmErrors.contains(.guestDiskIO))
    }

    func testRuntimeStateFileMetadataReadIsExplicitlyNotReadWhenGuestRuntimeStateIsMissing() {
        let fixture = healthyRuntimeFixture(guestHTTP: "200")
        fixture.guestGateway.runtimeState = nil

        let reads = fixture.checker.observationReads()
        let observation = EvaluateRuntimeHealthUseCase().observation(from: reads)

        XCTAssertEqual(reads.runtimeStateFileModifiedAt.readState, .notRead)
        XCTAssertNil(reads.runtimeStateFileModifiedAt.updatedAt)
        XCTAssertNil(reads.runtimeStateFileModifiedAt.readError)
        XCTAssertEqual(observation.containerObservation.observedValue?.runtimeStateFileMetadataReadState, .notRead)
        XCTAssertNil(observation.containerObservation.observedValue?.runtimeStateFileUpdatedAt)
        XCTAssertNil(observation.containerObservation.observedValue?.runtimeStateFileMetadataError)
    }

    func testSnapshotReportsGuestDiskHealthFromRuntimeStateContract() {
        let fixture = healthyRuntimeFixture(guestHTTP: "200")
        fixture.guestGateway.runtimeState = GuestRuntimeStateDocument(
            vmIP: "192.168.64.2",
            updatedAt: "2026-05-24T00:00:00Z",
            bootID: "boot-current",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            diskHealth: GuestDiskHealthDocument(
                rootFilesystemReadOnly: true,
                kernelErrors: [
                    "EXT4-fs error (device vda1): checksum invalid",
                    "systemd-journald: Failed to write entry: Input/output error",
                ]
            ),
            vitalDBObservation: healthyVitalDBObservation()
        )

        let snapshot = healthSnapshot(from: fixture.checker)

        XCTAssertEqual(snapshot.vmState, .failed)
        XCTAssertTrue(snapshot.vmErrors.contains(.guestFilesystemReadOnly))
        XCTAssertTrue(snapshot.vmErrors.contains(.guestFilesystemError))
        XCTAssertTrue(snapshot.vmErrors.contains(.guestDiskIO))
    }

    private func healthyRuntimeFixture(guestHTTP: String) -> RuntimeHealthCheckerFixture {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[URL(fileURLWithPath: RuntimeManagedServicePaths.launchDaemonPlist(.proxy))] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        fileStore.modificationDates[installedPaths.runtimeState] = Date(timeIntervalSince1970: 1_800_000_000)

        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(
            exitCode: 0,
            stdout: "80\n",
            stderr: ""
        )
        commandRunner.results[Constants.Commands.curl] = RuntimeProcessResult(
            exitCode: 0,
            stdout: #"{"activeWebSockets":0,"auditFileWriteFailures":0,"auditStdoutWriteFailures":0,"auditWriteFailures":0,"httpRequests":0,"redisIpWriteFailures":0,"socketIoEventsSeen":0,"socketIoParseFailures":0}"#,
            stderr: ""
        )

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
            bootID: "boot-current",
            guestHTTP: guestHTTP,
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            vitalDBObservation: healthyVitalDBObservation()
        )

        return RuntimeHealthCheckerFixture(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber,
            guestGateway: guestGateway
        )
    }
}

private func healthyVitalDBObservation() -> VitalDBObservationDocument {
    VitalDBObservationDocument(
        observedAt: "2026-05-24T00:00:00Z",
        ready: true,
        recorderOnlineThresholdSeconds: 120
    )
}

private func healthSnapshot(from checker: RuntimeHealthChecker) -> RuntimeHealthSnapshot {
    let useCase = EvaluateRuntimeHealthUseCase()
    return useCase.snapshot(observation: useCase.observation(from: checker.observationReads()))
}

private struct RuntimeHealthCheckerFixture {
    let installedPaths: InstalledRuntimePaths
    let fileStore: RuntimeFileStoreSpy
    let serviceManager: RuntimeServiceManagerSpy
    let commandRunner: RuntimeCommandRunnerSpy
    let httpProber: RuntimeHTTPProberSpy
    let guestGateway: RuntimeGuestGatewaySpy

    var checker: RuntimeHealthChecker {
        RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber,
            guestGateway: guestGateway
        )
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

    func start(service: RuntimeManagedService, plist: String) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func restart(service: RuntimeManagedService) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func stop(service: RuntimeManagedService) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func setEnabled(service: RuntimeManagedService, enabled: Bool) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}

private final class RuntimeGuestGatewaySpy: RuntimeGuestGateway {
    var runtimeState: GuestRuntimeStateDocument?
    var runtimeStateResult: RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>?
    var bootstrapResult: GuestBootstrapResultDocument?
    var bootstrapResultResult: RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument>?

    func loadRuntimeStateDocument() -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument> {
        if let runtimeStateResult {
            return runtimeStateResult
        }
        return runtimeState.map(RuntimeGuestDocumentLoadResult.loaded) ?? .missing
    }

    func loadBootstrapResultDocument() -> RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument> {
        if let bootstrapResultResult {
            return bootstrapResultResult
        }
        return bootstrapResult.map(RuntimeGuestDocumentLoadResult.loaded) ?? .missing
    }

    func removeUpdateActivationResult() throws {}
    func writeUpdateActivationRequest(_ request: RuntimeGuestActivationRequest) throws {}
    func loadUpdateActivationResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument> { .missing }
    func removeUpdateShutdownResult() throws {}
    func clearUpdateShutdownPreparation() throws {}
    func writeUpdateShutdownRequest(_ request: RuntimeGuestShutdownRequest) throws {}
    func loadUpdateShutdownResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument> { .missing }
    func removeDatastoreRepairResult() throws {}
    func writeDatastoreRepairRequest(_ request: RuntimeDatastoreRepairRequest) throws {}
    func loadDatastoreRepairResultDocument() -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument> { .missing }
}
