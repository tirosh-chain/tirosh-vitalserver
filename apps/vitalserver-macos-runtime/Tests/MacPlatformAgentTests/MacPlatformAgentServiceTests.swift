import Application
import Contracts
import Foundation
@testable import Errors
@testable import MacPlatformAgent
import OutboundAdapters
import RuntimeControl
import XCTest

final class MacPlatformAgentServiceTests: XCTestCase {
    @MainActor
    func testHeadlessServiceFailsWhenHostStateDatabaseIsMissing() throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("platform-agent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: productRoot) }
        try FileManager.default.createDirectory(at: productRoot, withIntermediateDirectories: true)
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)

        XCTAssertThrowsError(try MacPlatformAgentService.live(
            installedPaths: installedPaths,
            servesDevConsole: false,
            port: 0,
            automationToken: "test-token"
        )) { error in
            XCTAssertEqual(
                error as? RuntimeHostStateStoreStartupError,
                .missing(path: installedPaths.runtimeStateDatabase.path)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: installedPaths.runtimeStateDatabase.path))
    }

    @MainActor
    func testHeadlessServiceFailsWhenHostStateDatabaseIsCorrupt() throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("platform-agent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: productRoot) }
        try FileManager.default.createDirectory(at: productRoot, withIntermediateDirectories: true)
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        try FileManager.default.createDirectory(
            at: installedPaths.runtimeStateDatabase.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-a-sqlite-database".utf8).write(to: installedPaths.runtimeStateDatabase)

        XCTAssertThrowsError(try MacPlatformAgentService.live(
            installedPaths: installedPaths,
            servesDevConsole: false,
            port: 0,
            automationToken: "test-token"
        )) { error in
            guard case .failed(let path, _, let reason) = error as? RuntimeHostStateStoreStartupError else {
                return XCTFail("expected corrupt Host state store failure, got \(error)")
            }
            XCTAssertEqual(path, installedPaths.runtimeStateDatabase.path)
            XCTAssertFalse(reason.isEmpty)
        }
    }

    @MainActor
    func testHeadlessServiceOwnsReachableRuntimeControlAPI() async throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("platform-agent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: productRoot) }
        try FileManager.default.createDirectory(at: productRoot, withIntermediateDirectories: true)
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        _ = try SQLiteHostRuntimeStateDatabase(
            url: installedPaths.runtimeStateDatabase
        ).initialize()
        let service = try MacPlatformAgentService.live(
            installedPaths: installedPaths,
            servesDevConsole: false,
            port: 0,
            automationToken: "test-token"
        )
        try service.start()
        defer { service.stop() }

        let port = try await waitForActivePort(service)
        var request = URLRequest(
            url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/platform/runtime-provider"))
        )
        request.setValue(
            "test-token",
            forHTTPHeaderField: "X-Runtime-Control-Token"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        let runtimeProvider = try JSONDecoder().decode(RuntimeVMLifecycleResourceState.self, from: data)

        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(runtimeProvider.state, .missing)
        XCTAssertNil(runtimeProvider.document)
        XCTAssertTrue(runtimeProvider.readError?.contains("VM lifecycle SQLite state is missing") == true)
    }

    @MainActor
    func testLoginUserClientReadsRootOwnedStateWithoutAutomationToken() async throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("platform-agent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: productRoot) }
        try FileManager.default.createDirectory(at: productRoot, withIntermediateDirectories: true)
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        _ = try SQLiteHostRuntimeStateDatabase(
            url: installedPaths.runtimeStateDatabase
        ).initialize()
        let service = try MacPlatformAgentService.live(
            installedPaths: installedPaths,
            servesDevConsole: false,
            port: 0,
            automationToken: "root-only-token"
        )
        try service.start()
        defer { service.stop() }
        let port = try await waitForActivePort(service)

        let runtimeProvider = try await Task.detached {
            let owner = try RuntimeControlAPIVMLifecycleOwner(
                baseURL: "http://127.0.0.1:\(port)/",
                token: "not-the-automation-token",
                httpClient: RuntimeControlAPILocalSessionHTTPClient()
            )
            return try owner.loadVMLifecycleResource()
        }.value

        XCTAssertEqual(runtimeProvider.state, .missing)
        XCTAssertTrue(runtimeProvider.readError?.contains("VM lifecycle SQLite state is missing") == true)
    }

    @MainActor
    func testLoginUserClientReestablishesBrowserSessionAfterPlatformAgentRestart() async throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("platform-agent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: productRoot) }
        try FileManager.default.createDirectory(at: productRoot, withIntermediateDirectories: true)
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        _ = try SQLiteHostRuntimeStateDatabase(
            url: installedPaths.runtimeStateDatabase
        ).initialize()

        let initialService = try MacPlatformAgentService.live(
            installedPaths: installedPaths,
            servesDevConsole: false,
            port: 0,
            automationToken: "root-only-token"
        )
        try initialService.start()
        defer { initialService.stop() }
        let port = try await waitForActivePort(initialService)
        let httpClient = RuntimeControlAPILocalSessionHTTPClient()

        let initialState = try await Task.detached {
            let owner = try RuntimeControlAPIVMLifecycleOwner(
                baseURL: "http://127.0.0.1:\(port)/",
                token: "not-the-automation-token",
                httpClient: httpClient
            )
            return try owner.loadVMLifecycleResource()
        }.value
        XCTAssertEqual(initialState.state, .missing)
        initialService.stop()

        let restartedService = try MacPlatformAgentService.live(
            installedPaths: installedPaths,
            servesDevConsole: false,
            port: Int(port),
            automationToken: "root-only-token"
        )
        try restartedService.start()
        defer { restartedService.stop() }
        _ = try await waitForActivePort(restartedService)

        let restartedState = try await Task.detached {
            let owner = try RuntimeControlAPIVMLifecycleOwner(
                baseURL: "http://127.0.0.1:\(port)/",
                token: "not-the-automation-token",
                httpClient: httpClient
            )
            return try owner.loadVMLifecycleResource()
        }.value

        XCTAssertEqual(restartedState.state, .missing)
    }

    @MainActor
    func testHeadlessServiceSynchronizesBootstrapVMIPIntoSQLiteEndpointOwner() async throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("platform-agent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: productRoot) }
        try FileManager.default.createDirectory(at: productRoot, withIntermediateDirectories: true)
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        _ = try SQLiteHostRuntimeStateDatabase(
            url: installedPaths.runtimeStateDatabase
        ).initialize()
        let lifecycle = SQLiteRuntimeVMLifecycleStateRepository(
            databaseURL: installedPaths.runtimeStateDatabase,
            transitionDecider: RuntimeVMLifecycleTransitionUseCase()
        )
        var revision: Int?
        for (index, state) in [RuntimeVMLifecycleState.starting, .bootstrapping, .running].enumerated() {
            let record = try lifecycle.saveVMLifecycleState(RuntimeVMLifecycleStateMutation(
                document: RuntimeVMLifecycleDocument(
                    state: state,
                    operation: .startServices,
                    operationID: "operation-1",
                    bootID: "boot-1",
                    startedAt: "2026-07-15T00:00:00Z",
                    updatedAt: index == 0
                        ? "2026-07-15T00:00:00Z"
                        : "2026-07-15T00:00:0\(index)Z",
                    deadlineAt: state == .running ? nil : "2026-07-15T00:05:00Z",
                    message: state.rawValue
                ),
                expectedRevision: revision
            ))
            revision = record.revision
        }
        try FileManager.default.createDirectory(
            at: installedPaths.vmIPFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("192.168.64.21\n".utf8).write(to: installedPaths.vmIPFile)

        let service = try MacPlatformAgentService.live(
            installedPaths: installedPaths,
            servesDevConsole: false,
            port: 0,
            automationToken: "test-token",
            endpointSynchronizationInterval: 0.02
        )
        try service.start()
        defer { service.stop() }

        let port = try await waitForActivePort(service)
        let endpoint = try await waitForRuntimeEndpoint(port: port)

        XCTAssertEqual(endpoint.state, .loaded)
        XCTAssertEqual(endpoint.read?.loadedAddress, "192.168.64.21")
        XCTAssertEqual(endpoint.read?.source, .platformAgent)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: installedPaths.hostRunDirectory
                .appendingPathComponent("runtime-endpoint.json")
                .path
        ))
    }

    @MainActor
    func testLocalAPISettingsReaderReadsConfiguredPortFromRootOwnedDocument() throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("platform-agent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: productRoot) }
        try FileManager.default.createDirectory(at: productRoot, withIntermediateDirectories: true)
        let paths = InstalledRuntimePaths(productRoot: productRoot)
        let configuredPort = 18444
        try JSONEncoder().encode(RuntimeControlSettingsDocument(
            runtimeControlPort: configuredPort
        )).write(to: paths.runtimeControlSettings)

        let reader = RuntimeControlLocalAPISettingsReader(documentURL: paths.runtimeControlSettings)
        XCTAssertEqual(try reader.loadPort(), configuredPort)
    }

    @MainActor
    func testLocalAPISettingsReaderRejectsInvalidConfiguredPort() throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("platform-agent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: productRoot) }
        try FileManager.default.createDirectory(at: productRoot, withIntermediateDirectories: true)
        let paths = InstalledRuntimePaths(productRoot: productRoot)
        try JSONEncoder().encode(RuntimeControlSettingsDocument(
            runtimeControlPort: 65_536
        )).write(to: paths.runtimeControlSettings)

        let reader = RuntimeControlLocalAPISettingsReader(documentURL: paths.runtimeControlSettings)
        XCTAssertThrowsError(try reader.loadPort()) { error in
            guard case let .invalidPort(path, port) = error as? RuntimeControlLocalAPISettingsError else {
                return XCTFail("expected invalid Runtime Control API port error, got \(error)")
            }
            XCTAssertEqual(path, paths.runtimeControlSettings.path)
            XCTAssertEqual(port, 65_536)
        }
    }

    @MainActor
    private func waitForActivePort(
        _ service: MacPlatformAgentService
    ) async throws -> UInt16 {
        for _ in 0..<100 {
            if let port = service.activePort {
                return port
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Platform Agent listener did not become ready")
        throw PlatformAgentTestError.listenerNotReady
    }

    @MainActor
    private func waitForRuntimeEndpoint(port: UInt16) async throws -> RuntimeGuestAddressResourceState {
        for _ in 0..<100 {
            var request = URLRequest(
                url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/platform/runtime-endpoint"))
            )
            request.setValue("test-token", forHTTPHeaderField: "X-Runtime-Control-Token")
            let (data, _) = try await URLSession.shared.data(for: request)
            let endpoint = try JSONDecoder().decode(RuntimeGuestAddressResourceState.self, from: data)
            if endpoint.state == .loaded {
                return endpoint
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Platform Agent did not synchronize the VM IP bootstrap evidence")
        throw PlatformAgentTestError.endpointNotReady
    }
}

private enum PlatformAgentTestError: Error {
    case listenerNotReady
    case endpointNotReady
}
