import Application
import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
@testable import CLIHost
import XCTest

final class RuntimeGuestShutdownCompositionTests: XCTestCase {
    func testShutdownCompositionExecutesShutdownPlanThroughBootstrapEffects() throws {
        let fileStore = RuntimeFileStoreSpy()
        let guestRunDirectory = URL(fileURLWithPath: "/product/guest/run")
        let gateway = RuntimeGuestShutdownGatewaySpy(results: [
            .missing,
            .loaded(result(status: .running, requestId: "request-1", message: "stopping")),
            .loaded(result(
                status: .ready,
                requestId: "request-1",
                message: "poweroff requested",
                shutdownPhase: .poweroffRequested
            )),
        ])
        var events: [String] = []
        var statuses: [(RuntimeStatusLevel, RuntimeOperation, String)] = []
        var logs: [String] = []
        let composition = RuntimeGuestShutdownComposition(
            context: RuntimeGuestShutdownCompositionContext(guestRunDirectory: guestRunDirectory),
            operations: RuntimeGuestShutdownCompositionOperations(
                fileStore: fileStore,
                guestGateway: gateway,
                requireCapability: { events.append("capability") },
                writeStatus: { level, operation, message in
                    statuses.append((level, operation, message))
                },
                requestID: { "request-1" },
                timestamp: { "2026-05-22T00:00:00Z" },
                sleep: { events.append("sleep") },
                log: { logs.append($0) }
            )
        )

        try composition.prepareForUpdate(manifest: manifest())

        XCTAssertTrue(fileStore.directories.contains(guestRunDirectory))
        XCTAssertEqual(gateway.events, [
            "remove-result",
            "write-request:request-1:2026-05-22T00:00:00Z:1.2.3",
            "load-result",
            "load-result",
            "load-result",
        ])
        XCTAssertTrue(events.contains("capability"))
        XCTAssertEqual(events.filter { $0 == "sleep" }.count, 2)
        XCTAssertTrue(statuses.contains {
            $0.0 == .updating &&
                $0.1 == .applyBundle &&
                $0.2 == "waiting for guest update shutdown worker"
        })
        XCTAssertTrue(logs.contains("guest update shutdown requested version=1.2.3"))
        XCTAssertTrue(logs.contains("guest update shutdown result ready message=poweroff requested"))
        XCTAssertTrue(logs.contains("guest update shutdown ready version=1.2.3"))
    }

    private func manifest() -> UpdateBundleManifest {
        UpdateBundleManifest(
            schemaVersion: 3,
            product: "ai.tirosh.vitalserver.helper",
            helperVersion: "1.2.3",
            releaseLabel: "1.2.3",
            targetPlatform: "macos-arm64",
            components: ["updater": "1.2.3"],
            createdAt: "2026-05-22T00:00:00Z",
            artifacts: [],
            migrations: []
        )
    }

    private func result(
        status: GuestShutdownStatus,
        requestId: String,
        message: String,
        shutdownPhase: GuestShutdownPhase? = nil
    ) -> GuestUpdateShutdownResultDocument {
        GuestUpdateShutdownResultDocument(
            schemaVersion: 1,
            requestId: requestId,
            operation: .prepareUpdateShutdown,
            status: status,
            shutdownPhase: shutdownPhase,
            message: message,
            updatedAt: "2026-05-22T00:00:00Z"
        )
    }
}

private final class RuntimeGuestShutdownGatewaySpy: RuntimeGuestGateway {
    var events: [String] = []
    var results: [RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>]

    init(results: [RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>]) {
        self.results = results
    }

    func loadRuntimeStateDocument() -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument> {
        .missing
    }

    func loadBootstrapResultDocument() -> RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument> {
        .missing
    }

    func removeUpdateActivationResult() throws {}
    func writeUpdateActivationRequest(_ request: RuntimeGuestActivationRequest) throws {}
    func loadUpdateActivationResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument> { .missing }

    func removeUpdateShutdownResult() throws {
        events.append("remove-result")
    }

    func clearUpdateShutdownPreparation() throws {}

    func writeUpdateShutdownRequest(_ request: RuntimeGuestShutdownRequest) throws {
        events.append("write-request:\(request.id):\(request.requestedAt):\(request.version)")
    }

    func loadUpdateShutdownResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument> {
        events.append("load-result")
        return results.isEmpty ? .missing : results.removeFirst()
    }

    func removeDatastoreRepairResult() throws {}
    func writeDatastoreRepairRequest(_ request: RuntimeDatastoreRepairRequest) throws {}
    func loadDatastoreRepairResultDocument() -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument> { .missing }
}
