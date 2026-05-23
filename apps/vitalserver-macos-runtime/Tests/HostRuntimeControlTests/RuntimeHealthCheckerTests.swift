import Foundation
import RuntimeCore
import RuntimeContracts
import HostRuntimeInfrastructure
@testable import HostRuntimeControl
import XCTest

final class RuntimeHealthCheckerTests: XCTestCase {
    func testSnapshotReadsRuntimeStateThroughPorts() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.vmBin)] = Data()
        fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)] = Data()
        fileStore.files[installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)] = Data()

        let commandRunner = RuntimeCommandRunnerSpy()
        commandRunner.results[Constants.Commands.plistBuddy] = RuntimeProcessResult(
            exitCode: 0,
            stdout: "8080\n",
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

        XCTAssertTrue(snapshot.isHealthy)
        XCTAssertTrue(httpProber.requestedURLs.contains("http://127.0.0.1:8080/ready"))
        XCTAssertEqual(snapshot.vmIP, "192.168.64.2")
        XCTAssertEqual(snapshot.proxyPort, 8080)
        XCTAssertEqual(snapshot.hostProxyHTTP, "200")
        XCTAssertEqual(snapshot.rootfsBase, .present)
        XCTAssertEqual(snapshot.vmDisk, .present)
    }

    func testSnapshotFallsBackToMissingStateAndDefaultProxyPort() {
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

        XCTAssertFalse(snapshot.isHealthy)
        XCTAssertEqual(snapshot.proxyPort, InstallSettings.defaultProxyPort)
        XCTAssertEqual(snapshot.guestHTTP, "200")
        XCTAssertTrue(httpProber.requestedURLs.contains("http://192.168.64.3/ready"))
        XCTAssertTrue(snapshot.failureReasons.contains(.missingVMBin))
        XCTAssertTrue(snapshot.failureReasons.contains(.missingRootfsBase))
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
    var bootstrapResult: GuestBootstrapResultDocument?

    func loadRuntimeState() -> GuestRuntimeStateDocument? {
        runtimeState
    }

    func loadBootstrapResult() -> GuestBootstrapResultDocument? {
        bootstrapResult
    }

    func removeUpdateActivationResult() throws {}
    func writeUpdateActivationRequest(_ request: RuntimeGuestActivationRequest) throws {}
    func loadUpdateActivationResult() -> GuestUpdateActivationResultDocument? { nil }
    func removeDatastoreRepairResult() throws {}
    func writeDatastoreRepairRequest(_ request: RuntimeDatastoreRepairRequest) throws {}
    func loadDatastoreRepairResult() -> DatastoreRepairResultDocument? { nil }
}
