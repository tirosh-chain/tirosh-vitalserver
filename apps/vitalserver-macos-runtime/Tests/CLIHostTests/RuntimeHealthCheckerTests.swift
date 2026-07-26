import Foundation
import Bootstrap
import Application
import Contracts
import Domain
import OutboundAdapters
import InboundAdapters
import RuntimeControl
@testable import CLIHost
import XCTest
import Errors

final class RuntimeHealthCheckerTests: XCTestCase {
    func testSnapshotReadsRuntimeStateThroughPorts() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        fileStore.files[installedPaths.runtimeObservation] = Data("{}".utf8)
        fileStore.files[installedPaths.containerLogs] = Data("container logs".utf8)
        fileStore.modificationDates[installedPaths.runtimeObservation] = Date(timeIntervalSince1970: 1_800_000_000)
        fileStore.modificationDates[installedPaths.containerLogs] = Date(timeIntervalSince1970: 1_800_000_060)

        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(
            exitCode: 0,
            stdout: "8080\n",
            stderr: ""
        )
        commandRunner.results[Constants.Commands.curl] = RuntimeProcessResult(
            exitCode: 0,
            stdout: #"{"activeWebSockets":1,"activeRecorderConnections":0,"recorders":[],"auditFileWriteFailures":0,"auditStdoutWriteFailures":0,"auditWriteFailures":0,"failureLogWriteFailures":0,"httpRequests":2,"redisIpWriteFailures":0,"redisIpVerifyFailures":0,"redisIpVerifyMismatches":0,"socketIoEventsSeen":3,"socketIoParseFailures":0}"#,
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
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber,
            guestAddressProvider: stubGuestAddressProvider(
                read: .loaded(address: "192.168.64.2", source: .platformAgent)
            ),
            guestControlGateway: {
                RuntimeGuestControlGatewaySpy(
                    services: ["recorder-ingress"],
                    statuses: [
                        "recorder-ingress": RuntimeGuestControlServiceStatus(
                            service: "recorder-ingress",
                            state: "running",
                            health: "healthy",
                            observedAt: "2026-07-01T00:00:00Z"
                        ),
                    ],
                    vitalDBObservationRead: RuntimeGuestControlVitalDBObservationRead(
                        state: .loaded,
                        observation: healthyVitalDBObservation()
                    ),
                    recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult(
                        readState: .loaded,
                        httpStatus: "200",
                        document: RuntimeRecorderIngressStatusDocument(socketIoEventsSeen: 3),
                        readError: nil
                    )
                )
            }
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertFalse(snapshot.failureReasons.contains(.guestBootstrapFailed))
        XCTAssertTrue(httpProber.requestedURLs.contains("http://127.0.0.1:8080/ready"))
        XCTAssertEqual(snapshot.guestAddressRead, .loaded(address: "192.168.64.2", source: .platformAgent))
        XCTAssertEqual(snapshot.vmIP, "192.168.64.2")
        XCTAssertEqual(snapshot.proxyPort, 8080)
        XCTAssertEqual(snapshot.hostProxyHTTP, "200")
        XCTAssertEqual(snapshot.rootfsBase, .present)
        XCTAssertEqual(snapshot.vmDisk, .present)
    }

    func testSnapshotDoesNotReadVMIPFromRuntimeStateWhenVMIPFileIsAbsent() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        fileStore.files[installedPaths.runtimeObservation] = Data(#"{"vmIP":"192.168.64.203"}"#.utf8)

        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(
            exitCode: 0,
            stdout: "80\n",
            stderr: ""
        )
        let serviceManager = RuntimeServiceManagerSpy()
        serviceManager.states = [.vm: .loaded, .proxy: .loaded, .watchdog: .loaded]
        let httpProber = RuntimeHTTPProberSpy()
        httpProber.statuses[Constants.Runtime.proxyHealthURL(port: 80)] = "200"
        httpProber.statuses[Constants.Runtime.redisUIHealthURL(port: 80)] = "200"
        httpProber.statuses[Constants.Runtime.swaggerUIHealthURL(port: 80)] = "200"

        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber,
            guestAddressProvider: stubGuestAddressProvider(
                read: .missing("Guest address resource missing")
            ),
            guestControlGateway: {
                RuntimeGuestControlGatewaySpy(
                    services: ["app"],
                    statuses: ["app": RuntimeGuestControlServiceStatus(
                        service: "app",
                        state: "running",
                        health: "healthy",
                        observedAt: "2026-07-01T00:00:00Z"
                    )],
                    vitalDBObservationRead: RuntimeGuestControlVitalDBObservationRead(
                        state: .loaded,
                        observation: healthyVitalDBObservation()
                    ),
                    readyStatus: "ready"
                )
            }
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertNil(snapshot.vmIP)
        XCTAssertEqual(snapshot.guestAddressRead.state, .missing)
        XCTAssertTrue(snapshot.guestAddressRead.reason?.contains("Guest address resource missing") == true)
        XCTAssertEqual(snapshot.guestHTTP, RuntimeHTTPStatusText.notRead)
        XCTAssertFalse(snapshot.failureReasons.contains(.guestHTTP(RuntimeHTTPStatusText.missingVMIP)))
        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
    }

    func testSnapshotPreservesInvalidGuestAddressRead() {
        let fixture = healthyRuntimeFixture(
            guestHTTP: "200",
            guestAddressRead: .invalid("Guest address resource invalid")
        )

        let snapshot = healthSnapshot(from: fixture.checker)

        XCTAssertEqual(snapshot.guestAddressRead.state, .invalid)
        XCTAssertTrue(snapshot.guestAddressRead.reason?.contains("Guest address resource invalid") == true)
        XCTAssertNil(snapshot.vmIP)
        XCTAssertEqual(snapshot.guestHTTP, RuntimeHTTPStatusText.notRead)
        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertEqual(fixture.guestControlGateway.readyCount, 0)
        XCTAssertEqual(fixture.guestControlGateway.stackStatusCount, 0)
    }

    func testSnapshotPreservesGuestAddressReadFailure() {
        let fixture = healthyRuntimeFixture(
            guestHTTP: "200",
            guestAddressRead: .readFailed("Guest address resource read failed")
        )

        let snapshot = healthSnapshot(from: fixture.checker)

        XCTAssertEqual(snapshot.guestAddressRead.state, .readFailed)
        XCTAssertTrue(snapshot.guestAddressRead.reason?.contains("Guest address resource read failed") == true)
        XCTAssertNil(snapshot.vmIP)
        XCTAssertEqual(snapshot.guestHTTP, RuntimeHTTPStatusText.notRead)
        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertEqual(fixture.guestControlGateway.readyCount, 0)
        XCTAssertEqual(fixture.guestControlGateway.stackStatusCount, 0)
    }

    func testSnapshotPreservesMissingVitalDBObservationFromGuestControlReadWithoutRuntimeFailure() {
        let fixture = healthyRuntimeFixture(guestHTTP: "200")
        let guestControlGateway = RuntimeGuestControlGatewaySpy(
            services: ["app"],
            statuses: [
                "app": RuntimeGuestControlServiceStatus(
                    service: "app",
                    state: "running",
                    health: "healthy",
                    observedAt: "2026-07-01T00:00:00Z"
                ),
            ],
            vitalDBObservationRead: RuntimeGuestControlVitalDBObservationRead(
                state: .unavailable,
                readError: "VitalDB observation read model is empty."
            ),
            recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult(
                readState: .loaded,
                httpStatus: "200",
                document: RuntimeRecorderIngressStatusDocument(),
                readError: nil
            )
        )

        let snapshot = healthSnapshot(from: fixture.checker(guestControlGateway: { guestControlGateway }))

        XCTAssertFalse(snapshot.failureReasons.containsVitalDBObservationFailure)
        XCTAssertNil(snapshot.vitalDBObservation)
        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
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

    func testSnapshotDoesNotReportMissingVitalDBObservationFromFreshRuntimeState() {
        let fixture = healthyRuntimeFixture(guestHTTP: "200")

        let snapshot = healthSnapshot(from: fixture.checker)

        XCTAssertFalse(snapshot.failureReasons.containsVitalDBObservationFailure)
        XCTAssertNil(snapshot.vitalDBObservation)
        XCTAssertTrue(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
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
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertFalse(RuntimeHealthSnapshotPolicy.isHealthy(snapshot))
        XCTAssertNil(snapshot.proxyPort)
        XCTAssertEqual(snapshot.vmIP, nil)
        XCTAssertEqual(snapshot.guestHTTP, RuntimeHTTPStatusText.notRead)
        XCTAssertFalse(httpProber.requestedURLs.contains("http://192.168.64.3/ready"))
        XCTAssertFalse(httpProber.requestedURLs.contains(Constants.Runtime.proxyHealthURL(port: RuntimeInstallSettings.defaultProxyPort)))
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
        let vmLifecycle = RuntimeVMLifecycleDocument(
            state: .bootstrapping,
            startedAt: "2026-05-31T00:00:00Z",
            updatedAt: "2026-05-31T00:00:01Z",
            deadlineAt: "2026-05-31T00:10:00Z"
        )

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
            guestAddressProvider: stubGuestAddressProvider(
                read: .missing("Guest address resource missing")
            ),
            vmLifecycleResourceReader: StubRuntimeVMLifecycleResourceReader(resource: .loaded(vmLifecycle)),
            now: { ISO8601DateFormatter().date(from: "2026-05-31T00:05:00Z")! }
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertEqual(snapshot.vmLifecycle?.state, .bootstrapping)
        XCTAssertEqual(snapshot.vmState, .starting)
        XCTAssertFalse(snapshot.vmErrors.contains(.unknown("vm-runtime-state-missing")))
        XCTAssertFalse(snapshot.failureReasons.contains(.vmLifecycleDocumentStale))
    }

    func testSnapshotReportsExpiredBootLifecycleAsStale() throws {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        let vmLifecycle = RuntimeVMLifecycleDocument(
            state: .bootstrapping,
            startedAt: "2026-05-31T00:00:00Z",
            updatedAt: "2026-05-31T00:00:01Z",
            deadlineAt: "2026-05-31T00:10:00Z"
        )
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: RuntimeServiceManagerSpy(),
            commandRunner: RuntimeCommandRunnerSpy(),
            httpProber: RuntimeHTTPProberSpy(),
            guestAddressProvider: stubGuestAddressProvider(
                read: .missing("Guest address resource missing")
            ),
            vmLifecycleResourceReader: StubRuntimeVMLifecycleResourceReader(resource: .loaded(vmLifecycle)),
            now: { ISO8601DateFormatter().date(from: "2026-05-31T00:11:00Z")! }
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertEqual(snapshot.vmLifecycle?.state, .bootstrapping)
        XCTAssertTrue(snapshot.failureReasons.contains(.vmLifecycleDocumentStale))
    }

    func testSnapshotDoesNotPromoteRuntimeStateMissingGuestHTTPToCurrentHealth() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        fileStore.modificationDates[installedPaths.runtimeObservation] = Date(timeIntervalSince1970: 1_800_000_000)

        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "80\n", stderr: "")
        let serviceManager = RuntimeServiceManagerSpy()
        serviceManager.states = [.vm: .loaded, .proxy: .loaded, .watchdog: .loaded]
        let httpProber = RuntimeHTTPProberSpy()
        httpProber.statuses[Constants.Runtime.proxyHealthURL(port: 80)] = "200"
        httpProber.statuses[Constants.Runtime.redisUIHealthURL(port: 80)] = "200"
        httpProber.statuses[Constants.Runtime.swaggerUIHealthURL(port: 80)] = "200"
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertEqual(snapshot.guestHTTP, RuntimeHTTPStatusText.notRead)
        XCTAssertFalse(snapshot.failureReasons.contains(.unknown("guest-runtime-state-invalid")))
        XCTAssertFalse(snapshot.failureReasons.contains(.guestHTTP(RuntimeHTTPStatusText.missingGuestHTTP)))
        XCTAssertEqual(snapshot.vmState, .running)
    }

    func testSnapshotKeepsGuestRuntimeStateReadFailureOutOfCurrentHealth() {
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

        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: RuntimeHTTPProberSpy(),
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertNil(snapshot.vmIP)
        XCTAssertEqual(snapshot.guestHTTP, RuntimeHTTPStatusText.notRead)
        XCTAssertFalse(snapshot.failureReasons.contains(.unknown("guest-runtime-state-invalid")))
    }

    func testSnapshotUsesGuestControlReadinessInsteadOfRuntimeStateWhenGatewayIsAvailable() {
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
        let guestControlGateway = RuntimeGuestControlGatewaySpy(
            services: ["app"],
            statuses: [
                "app": RuntimeGuestControlServiceStatus(
                    service: "app",
                    state: "running",
                    health: "healthy",
                    observedAt: "2026-07-01T00:00:00Z"
                ),
            ]
        )

        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: RuntimeHTTPProberSpy(),
            guestAddressProvider: stubGuestAddressProvider(
                read: .loaded(address: "192.168.64.44", source: .platformAgent)
            ),
            guestControlGateway: { guestControlGateway }
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertEqual(snapshot.vmIP, "192.168.64.44")
        XCTAssertEqual(snapshot.guestHTTP, "200")
        XCTAssertFalse(snapshot.failureReasons.contains(.unknown("guest-runtime-state-invalid")))
        XCTAssertEqual(guestControlGateway.readyCount, 1)
        XCTAssertEqual(guestControlGateway.stackStatusCount, 0)
        XCTAssertEqual(guestControlGateway.resourceRequests, [])
    }

    func testSnapshotUsesBootstrappingLifecycleWithoutBootstrapResultFileInput() throws {
        let fixture = healthyRuntimeFixture(guestHTTP: RuntimeHTTPStatusText.bootstrapPending)
        let vmLifecycle = RuntimeVMLifecycleDocument(
            state: .bootstrapping,
            startedAt: "2026-05-31T00:00:00Z",
            updatedAt: "2026-05-31T00:00:01Z",
            deadlineAt: "2026-05-31T00:10:00Z"
        )
        let checker = RuntimeHealthChecker(
            installedPaths: fixture.installedPaths,
            fileStore: fixture.fileStore,
            serviceManager: fixture.serviceManager,
            commandRunner: fixture.commandRunner,
            httpProber: fixture.httpProber,
            vmLifecycleResourceReader: StubRuntimeVMLifecycleResourceReader(resource: .loaded(vmLifecycle)),
            now: { ISO8601DateFormatter().date(from: "2026-05-31T00:05:00Z")! }
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertEqual(snapshot.vmState, .starting)
    }

    func testSnapshotPreservesInvalidHostProxyPortConfigAsReadStateOnly() {
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
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertNil(snapshot.proxyPort)
        XCTAssertEqual(snapshot.hostProxyHTTP, RuntimeHTTPStatusText.missingProxyPort)
        XCTAssertEqual(snapshot.redisUIHTTP, RuntimeHTTPStatusText.missingProxyPort)
        XCTAssertEqual(snapshot.swaggerUIHTTP, RuntimeHTTPStatusText.missingProxyPort)
        XCTAssertEqual(snapshot.proxyPortReadState, .invalid("not-a-port"))
        XCTAssertFalse(snapshot.failureReasons.contains(.hostProxyConfigInvalid))
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
            XCTAssertFalse(snapshot.failureReasons.contains(.hostProxyConfigInvalid))
            XCTAssertEqual(snapshot.hostProxyHTTP, RuntimeHTTPStatusText.missingProxyPort)
        }
    }

    func testSnapshotPreservesMissingHostProxyPortConfigFromPlistPathStateAsReadStateOnly() {
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
        XCTAssertFalse(snapshot.failureReasons.contains(.hostProxyConfigInvalid))
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
        XCTAssertFalse(snapshot.failureReasons.contains(.hostProxyConfigInvalid))
    }

    func testSnapshotPreservesHostProxyPortConfigPathInspectionFailureAsReadStateOnly() {
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
        XCTAssertFalse(snapshot.failureReasons.contains(.hostProxyConfigInvalid))
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
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertTrue(snapshot.failureReasons.contains(.hostProxyListenerScanFailed(port: 8080, exitCode: 0)))
        XCTAssertFalse(snapshot.failureReasons.contains(.hostProxyListenerMismatch(port: 8080, listeners: "malformed")))
    }

    func testSnapshotKeepsGuestRecorderIngressStatusFailureAsDiagnosticsEvidence() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        fileStore.modificationDates[installedPaths.runtimeObservation] = Date()
        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "80\n", stderr: "")
        let serviceManager = RuntimeServiceManagerSpy()
        serviceManager.states = [.vm: .loaded, .proxy: .loaded, .watchdog: .loaded]
        let httpProber = RuntimeHTTPProberSpy()
        httpProber.statuses[Constants.Runtime.proxyHealthURL(port: 80)] = "200"
        httpProber.statuses[Constants.Runtime.redisUIHealthURL(port: 80)] = "200"
        httpProber.statuses[Constants.Runtime.swaggerUIHealthURL(port: 80)] = "200"
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber,
            guestControlGateway: {
                RuntimeGuestControlGatewaySpy(
                    services: ["recorder-ingress"],
                    statuses: [
                        "recorder-ingress": RuntimeGuestControlServiceStatus(
                            service: "recorder-ingress",
                            state: "running",
                            health: "healthy",
                            observedAt: "2026-07-01T00:00:00Z"
                        ),
                    ],
                    vitalDBObservationRead: RuntimeGuestControlVitalDBObservationRead(
                        state: .loaded,
                        observation: healthyVitalDBObservation()
                    ),
                    recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult(
                        readState: .readFailed,
                        httpStatus: RuntimeHTTPStatusText.failed,
                        document: nil,
                        readError: "guestControl=timeout"
                    )
                )
            }
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertFalse(snapshot.failureReasons.contains(.recorderIngressHTTP("failed")))
    }

    func testSnapshotKeepsInvalidRecorderIngressStatusResponseAsDiagnosticsEvidence() throws {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[URL(fileURLWithPath: RuntimeManagedServicePaths.launchDaemonPlist(.proxy))] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(exitCode: 0, stdout: "80\n", stderr: "")
        let serviceManager = RuntimeServiceManagerSpy()
        serviceManager.states = [.vm: .loaded, .proxy: .loaded, .watchdog: .loaded]
        let httpProber = RuntimeHTTPProberSpy()
        httpProber.statuses[Constants.Runtime.proxyHealthURL(port: 80)] = "200"
        httpProber.statuses[Constants.Runtime.redisUIHealthURL(port: 80)] = "200"
        httpProber.statuses[Constants.Runtime.swaggerUIHealthURL(port: 80)] = "200"
        let checker = RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber,
            guestControlGateway: {
                RuntimeGuestControlGatewaySpy(
                    services: ["recorder-ingress"],
                    statuses: [
                        "recorder-ingress": RuntimeGuestControlServiceStatus(
                            service: "recorder-ingress",
                            state: "running",
                            health: "healthy",
                            observedAt: "2026-07-01T00:00:00Z"
                        ),
                    ],
                    vitalDBObservationRead: RuntimeGuestControlVitalDBObservationRead(
                        state: .loaded,
                        observation: healthyVitalDBObservation()
                    ),
                    recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult(
                        readState: .invalidResponse,
                        httpStatus: RuntimeHTTPStatusText.invalidResponse,
                        document: nil,
                        readError: "guestControl=invalidResponse"
                    )
                )
            }
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertFalse(snapshot.failureReasons.contains(.recorderIngressHTTP(RuntimeHTTPStatusText.invalidResponse)))
    }

    func testSnapshotDoesNotUseStaleRuntimeStateForGuestProbes() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        fileStore.files[installedPaths.runtimeObservation] = Data("{}".utf8)
        fileStore.modificationDates[installedPaths.runtimeObservation] = Date(timeIntervalSince1970: 1_800_000_000)

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
            now: { Date(timeIntervalSince1970: 1_800_000_120) }
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertEqual(snapshot.vmIP, nil)
        XCTAssertEqual(snapshot.guestHTTP, RuntimeHTTPStatusText.notRead)
        XCTAssertFalse(httpProber.requestedURLs.contains("http://192.168.64.8/ready"))
        XCTAssertFalse(snapshot.failureReasons.contains(.unknown("guest-runtime-state-stale")))
        XCTAssertFalse(snapshot.failureReasons.contains(.guestHTTP("failed")))
    }

    func testSnapshotKeepsUnreadableRuntimeStateMetadataOutOfCurrentHealth() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        fileStore.files[installedPaths.runtimeObservation] = Data("{}".utf8)
        fileStore.modificationDateErrors[installedPaths.runtimeObservation] = CocoaError(.fileReadNoPermission)

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
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertEqual(snapshot.vmState, .running)
        XCTAssertFalse(snapshot.failureReasons.contains(.unknown("guest-runtime-state-stale")))
        XCTAssertFalse(snapshot.failureReasons.contains(.unknown("guest-runtime-state-invalid")))
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
        )

        let snapshot = healthSnapshot(from: checker)

        XCTAssertEqual(snapshot.vmState, .running)
        XCTAssertFalse(snapshot.vmErrors.contains(.unknown("vm-runtime-state-missing")))
        XCTAssertFalse(snapshot.vmErrors.contains(.launchFailed("virtualization")))
        XCTAssertFalse(snapshot.vmErrors.contains(.diskAttachmentInvalid))
        XCTAssertFalse(snapshot.vmErrors.contains(.guestFilesystemError))
        XCTAssertFalse(snapshot.vmErrors.contains(.guestFilesystemReadOnly))
        XCTAssertFalse(snapshot.vmErrors.contains(.guestDiskIO))
    }

    func testSnapshotDoesNotReportGuestDiskHealthFromRuntimeStateContract() {
        let fixture = healthyRuntimeFixture(guestHTTP: "200")

        let snapshot = healthSnapshot(from: fixture.checker)

        XCTAssertFalse(snapshot.vmErrors.contains(.guestFilesystemReadOnly))
        XCTAssertFalse(snapshot.vmErrors.contains(.guestFilesystemError))
        XCTAssertFalse(snapshot.vmErrors.contains(.guestDiskIO))
    }

    private func healthyRuntimeFixture(
        guestHTTP: String,
        guestAddressRead: RuntimeGuestAddressReadResult = .loaded(
            address: "192.168.64.2",
            source: .platformAgent
        )
    ) -> RuntimeHealthCheckerFixture {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[URL(fileURLWithPath: RuntimeManagedServicePaths.launchDaemonPlist(.proxy))] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()
        fileStore.modificationDates[installedPaths.runtimeObservation] = Date(timeIntervalSince1970: 1_800_000_000)

        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(
            exitCode: 0,
            stdout: "80\n",
            stderr: ""
        )
        commandRunner.results[Constants.Commands.curl] = RuntimeProcessResult(
            exitCode: 0,
            stdout: #"{"activeWebSockets":0,"activeRecorderConnections":0,"recorders":[],"auditFileWriteFailures":0,"auditStdoutWriteFailures":0,"auditWriteFailures":0,"failureLogWriteFailures":0,"httpRequests":0,"redisIpWriteFailures":0,"redisIpVerifyFailures":0,"redisIpVerifyMismatches":0,"socketIoEventsSeen":0,"socketIoParseFailures":0}"#,
            stderr: ""
        )

        let serviceManager = RuntimeServiceManagerSpy()
        serviceManager.states = [.vm: .loaded, .proxy: .loaded, .watchdog: .loaded]

        let httpProber = RuntimeHTTPProberSpy()
        httpProber.statuses[Constants.Runtime.proxyHealthURL(port: 80)] = "200"
        httpProber.statuses[Constants.Runtime.redisUIHealthURL(port: 80)] = "200"
        httpProber.statuses[Constants.Runtime.swaggerUIHealthURL(port: 80)] = "200"

        return RuntimeHealthCheckerFixture(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber,
            guestControlGateway: RuntimeGuestControlGatewaySpy(
                services: ["app"],
                statuses: [
                    "app": RuntimeGuestControlServiceStatus(
                        service: "app",
                        state: "running",
                        health: "healthy",
                        observedAt: "2026-07-01T00:00:00Z"
                    ),
                ],
                readyStatus: guestHTTP == "200" ? "ready" : guestHTTP
            ),
            guestAddressRead: guestAddressRead
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

private func stubGuestAddressProvider(read: RuntimeGuestAddressReadResult) -> any RuntimeGuestAddressProvider {
    StubRuntimeGuestAddressProvider(read: read)
}

private struct StubRuntimeGuestAddressProvider: RuntimeGuestAddressProvider {
    let read: RuntimeGuestAddressReadResult

    func readGuestAddress() -> RuntimeGuestAddressReadResult {
        read
    }
}

private struct StubRuntimeVMLifecycleResourceReader: RuntimeVMLifecycleResourceReading {
    let resource: RuntimeVMLifecycleResourceState

    func loadVMLifecycleResource() -> RuntimeVMLifecycleResourceState {
        resource
    }
}

private struct RuntimeHealthCheckerFixture {
    let installedPaths: InstalledRuntimePaths
    let fileStore: RuntimeFileStoreSpy
    let serviceManager: RuntimeServiceManagerSpy
    let commandRunner: RuntimeCommandRunnerSpy
    let httpProber: RuntimeHTTPProberSpy
    let guestControlGateway: RuntimeGuestControlGatewaySpy
    let guestAddressRead: RuntimeGuestAddressReadResult

    var checker: RuntimeHealthChecker {
        checker(guestControlGateway: { [guestControlGateway] in guestControlGateway })
    }

    func checker(
        guestControlGateway: (@Sendable () throws -> any RuntimeGuestControlGateway)?
    ) -> RuntimeHealthChecker {
        RuntimeHealthChecker(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber,
            guestAddressProvider: stubGuestAddressProvider(read: guestAddressRead),
            guestControlGateway: guestControlGateway
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

private final class RuntimeGuestControlGatewaySpy: RuntimeGuestControlGateway, @unchecked Sendable {
    private let services: [String]
    private let statuses: [String: RuntimeGuestControlServiceStatus]
    private let resources: [String: RuntimeGuestServiceResource]
    private let resourceFailures: [String: Error]
    private let vitalDBObservationRead: RuntimeGuestControlVitalDBObservationRead
    private let recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult?
    var readyStatus = "ready"
    var readyCount = 0
    var listServicesCount = 0
    var stackStatusCount = 0
    var statusRequests: [String] = []
    var resourceRequests: [String] = []
    var recorderIngressStatusCount = 0

    init(
        services: [String],
        statuses: [String: RuntimeGuestControlServiceStatus],
        resources: [String: RuntimeGuestServiceResource] = [:],
        resourceFailures: [String: Error] = [:],
        vitalDBObservationRead: RuntimeGuestControlVitalDBObservationRead = RuntimeGuestControlVitalDBObservationRead(
            state: .unavailable
        ),
        recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult? = nil,
        readyStatus: String = "ready"
    ) {
        self.services = services
        self.statuses = statuses
        self.resources = resources
        self.resourceFailures = resourceFailures
        self.vitalDBObservationRead = vitalDBObservationRead
        self.recorderIngressStatusRead = recorderIngressStatusRead
        self.readyStatus = readyStatus
    }

    func ready() throws -> RuntimeGuestControlReadiness {
        readyCount += 1
        return RuntimeGuestControlReadiness(status: readyStatus)
    }

    func listServices() throws -> RuntimeGuestControlServiceList {
        listServicesCount += 1
        return RuntimeGuestControlServiceList(services: services)
    }

    func stackStatus() throws -> RuntimeGuestControlStackStatus {
        stackStatusCount += 1
        return RuntimeGuestControlStackStatus(
            state: "loaded",
            observedAt: "2026-07-01T00:00:00Z",
            services: services.map { service in
                statuses[service] ?? RuntimeGuestControlServiceStatus(
                    service: service,
                    state: "absent",
                    health: "not_reported",
                    observedAt: "2026-07-01T00:00:00Z"
                )
            }
        )
    }

    func serviceStatus(_ service: String) throws -> RuntimeGuestControlServiceStatus {
        statusRequests.append(service)
        guard let status = statuses[service] else {
            throw RuntimeGuestControlGatewaySpyError.missingStatus(service)
        }
        return status
    }

    func serviceResource(_ service: String) throws -> RuntimeGuestServiceResource {
        resourceRequests.append(service)
        if let failure = resourceFailures[service] {
            throw failure
        }
        if let resource = resources[service] {
            return resource
        }
        guard let status = statuses[service] else {
            throw RuntimeGuestControlGatewaySpyError.missingStatus(service)
        }
        return RuntimeGuestServiceResource(
            service: service,
            spec: RuntimeGuestServiceSpec(state: "configured", desiredState: "running"),
            status: RuntimeGuestServiceStatusRead(
                state: "loaded",
                observedState: status.state,
                observedAt: status.observedAt,
                serviceStatus: status
            ),
            conditions: []
        )
    }

    func recorderIngressStatus() throws -> RuntimeRecorderIngressStatusReadResult {
        recorderIngressStatusCount += 1
        guard let recorderIngressStatusRead else {
            throw RuntimeGuestControlGatewaySpyError.missingStatus("recorder-ingress-status")
        }
        return recorderIngressStatusRead
    }

    func startService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        operation(service: service, command: .start)
    }

    func stopService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        operation(service: service, command: .stop)
    }

    func restartService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        operation(service: service, command: .restart)
    }

    func reconcileServices() throws -> RuntimeGuestControlServiceOperation {
        operation(service: "guest-stack", command: .reconcile)
    }

    func operation(_ operationId: String) throws -> RuntimeGuestControlServiceOperation {
        RuntimeGuestControlServiceOperation(
            operationId: operationId,
            service: "app",
            command: .restart,
            state: .completed,
            createdAt: "2026-07-01T00:00:00Z",
            updatedAt: "2026-07-01T00:00:00Z"
        )
    }

    func latestVitalDBObservation() throws -> RuntimeGuestControlVitalDBObservationRead {
        vitalDBObservationRead
    }

    private func operation(
        service: String,
        command: RuntimeGuestControlServiceCommand
    ) -> RuntimeGuestControlServiceOperation {
        RuntimeGuestControlServiceOperation(
            operationId: "op-\(service)-\(command.rawValue)",
            service: service,
            command: command,
            state: .completed,
            createdAt: "2026-07-01T00:00:00Z",
            updatedAt: "2026-07-01T00:00:00Z"
        )
    }
}

private enum RuntimeGuestControlGatewaySpyError: Error, CustomStringConvertible {
    case missingStatus(String)

    var description: String {
        switch self {
        case .missingStatus(let service):
            return "missing status for service \(service)"
        }
    }
}

private extension [RuntimeFailureReason] {
    var containsVitalDBObservationFailure: Bool {
        contains { reason in
            reason.rawValue.hasPrefix("vitaldb-observation-")
        }
    }
}
