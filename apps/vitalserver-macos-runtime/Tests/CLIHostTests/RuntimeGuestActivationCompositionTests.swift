import Application
import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
@testable import CLIHost
import XCTest

final class RuntimeGuestActivationCompositionTests: XCTestCase {
    func testActivationCompositionExecutesActivationPlanThroughBootstrapEffects() throws {
        let fileStore = RuntimeFileStoreSpy()
        let guestRunDirectory = URL(fileURLWithPath: "/product/guest/run")
        let gateway = RuntimeGuestActivationGatewaySpy(results: [
            .missing,
            .loaded(result(status: .running, requestId: "request-1", message: "loading")),
            .loaded(result(status: .completed, requestId: "request-1", message: "done")),
        ])
        var events: [String] = []
        var statuses: [(RuntimeStatusLevel, RuntimeOperation, String)] = []
        var logs: [String] = []
        let composition = RuntimeGuestActivationComposition(
            context: RuntimeGuestActivationCompositionContext(guestRunDirectory: guestRunDirectory),
            operations: RuntimeGuestActivationCompositionOperations(
                fileStore: fileStore,
                guestGateway: gateway,
                requireCapability: { events.append("capability") },
                isVMServiceLoaded: { false },
                startVMService: { events.append("start-vm") },
                writeStatus: { level, operation, message in
                    statuses.append((level, operation, message))
                },
                requestID: { "request-1" },
                timestamp: { "2026-05-22T00:00:00Z" },
                sleep: { events.append("sleep") },
                log: { logs.append($0) }
            )
        )

        try composition.activateIfNeeded(manifest: manifest(artifacts: [.guestDeploy]))

        XCTAssertTrue(fileStore.directories.contains(guestRunDirectory))
        XCTAssertEqual(gateway.events, [
            "remove-result",
            "write-request:request-1:2026-05-22T00:00:00Z:1.2.3",
            "load-result",
            "load-result",
            "load-result",
        ])
        XCTAssertTrue(events.contains("capability"))
        XCTAssertTrue(events.contains("start-vm"))
        XCTAssertEqual(events.filter { $0 == "sleep" }.count, 2)
        XCTAssertTrue(statuses.contains {
            $0.0 == .recovering &&
                $0.1 == .activateGuestUpdate &&
                $0.2 == "waiting for guest update activation worker"
        })
        XCTAssertTrue(logs.contains("guest update activation requested version=1.2.3"))
        XCTAssertTrue(logs.contains("guest update activation result completed message=done"))
        XCTAssertTrue(logs.contains("guest update activation completed version=1.2.3"))
    }

    private func manifest(artifacts: [UpdateBundleArtifactType]) -> UpdateBundleManifest {
        UpdateBundleManifest(
            schemaVersion: 3,
            product: "ai.tirosh.vitalserver.helper",
            helperVersion: "1.2.3",
            releaseLabel: "1.2.3",
            targetPlatform: "macos-arm64",
            components: ["updater": "1.2.3"],
            createdAt: "2026-05-22T00:00:00Z",
            artifacts: artifacts.map {
                UpdateBundleArtifact(name: "\($0.rawValue).tar.gz", type: $0, sha256: "sha256", size: 1)
            },
            migrations: []
        )
    }

    private func result(
        status: GuestActivationStatus,
        requestId: String,
        message: String
    ) -> GuestUpdateActivationResultDocument {
        GuestUpdateActivationResultDocument(
            schemaVersion: 2,
            requestId: requestId,
            operation: .activateGuestUpdate,
            status: status,
            message: message,
            updatedAt: "2026-05-22T00:00:00Z"
        )
    }
}

private final class RuntimeGuestActivationGatewaySpy: RuntimeGuestGateway {
    var events: [String] = []
    var results: [RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument>]

    init(results: [RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument>]) {
        self.results = results
    }

    func loadRuntimeStateDocument() -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument> {
        .missing
    }

    func loadBootstrapResultDocument() -> RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument> {
        .missing
    }

    func removeUpdateActivationResult() throws {
        events.append("remove-result")
    }

    func writeUpdateActivationRequest(_ request: RuntimeGuestActivationRequest) throws {
        events.append("write-request:\(request.id):\(request.requestedAt):\(request.version)")
    }

    func loadUpdateActivationResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument> {
        events.append("load-result")
        return results.isEmpty ? .missing : results.removeFirst()
    }

    func removeUpdateShutdownResult() throws {}
    func writeUpdateShutdownRequest(_ request: RuntimeGuestShutdownRequest) throws {}
    func loadUpdateShutdownResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument> { .missing }
    func removeDatastoreRepairResult() throws {}
    func writeDatastoreRepairRequest(_ request: RuntimeDatastoreRepairRequest) throws {}
    func loadDatastoreRepairResultDocument() -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument> { .missing }
}
