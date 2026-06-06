import Application
import Contracts
import Foundation
import Workflow
import XCTest
import Errors

final class RuntimeGuestUpdateWorkflowTests: XCTestCase {
    func testActivationSkipsWhenManifestDoesNotContainGuestDeployArtifact() throws {
        let harness = ActivationHarness(results: [])

        try harness.workflow.activateIfNeeded(
            manifest: manifest(artifacts: [.appBundle]),
            context: harness.context,
            actions: harness.operations
        )

        XCTAssertEqual(harness.events, [
            "log:guest update activation not required",
        ])
    }

    func testActivationExecutesRequestStartsVMAndWaitsForCompletion() throws {
        let harness = ActivationHarness(results: [
            .missing,
            .loaded(activationResult(status: .completed, requestId: "request-1", message: "activated")),
        ])

        try harness.workflow.activateIfNeeded(
            manifest: manifest(artifacts: [.guestDeploy]),
            context: harness.context,
            actions: harness.operations
        )

        XCTAssertEqual(harness.events, [
            "log:guest update activation requested version=1.2.3",
            "capability",
            "create:/guest/run",
            "remove-result",
            "request:request-1:2026-06-05T00:00:00Z:1.2.3",
            "vm-loaded",
            "start-vm",
            "log:waiting for guest update activation result timeoutSeconds=6.0",
            "load",
            "log:waiting for guest update activation worker",
            "status:recovering:activate-guest-update:waiting for guest update activation worker",
            "sleep",
            "load",
            "log:guest update activation result completed message=activated",
            "log:guest update activation completed version=1.2.3",
        ])
    }

    func testActivationPreservesReadFailureAndTimeoutAsDistinctFailures() {
        let readFailure = ActivationHarness(results: [.failed("permission denied")])
        XCTAssertThrowsError(try readFailure.workflow.activateIfNeeded(
            manifest: manifest(artifacts: [.guestDeploy]),
            context: readFailure.context,
            actions: readFailure.operations
        )) { error in
            XCTAssertEqual(error as? RuntimeGuestUpdateUseCaseError, .operationFailed("runtime health check failed"))
        }
        XCTAssertTrue(readFailure.events.contains(
            "log:guest update activation result failed message=failed to read guest update activation result: permission denied"
        ))

        let timeout = ActivationHarness(results: [.missing, .missing])
        XCTAssertThrowsError(try timeout.workflow.activateIfNeeded(
            manifest: manifest(artifacts: [.guestDeploy]),
            context: timeout.context,
            actions: timeout.operations
        )) { error in
            XCTAssertEqual(error as? RuntimeGuestUpdateUseCaseError, .operationFailed("runtime health check failed"))
        }
        XCTAssertFalse(timeout.events.contains { $0.contains("result failed") })
    }

    func testShutdownExecutesRequestAndWaitsForReadyResult() throws {
        let harness = ShutdownHarness(results: [
            .missing,
            .loaded(shutdownResult(
                status: .ready,
                phase: .poweroffRequested,
                requestId: "request-1",
                message: "ready"
            )),
        ])

        try harness.workflow.prepareForUpdate(
            version: "1.2.3",
            context: harness.context,
            actions: harness.operations
        )

        XCTAssertEqual(harness.events, [
            "log:guest update shutdown requested version=1.2.3",
            "capability",
            "create:/guest/run",
            "remove-result",
            "request:request-1:2026-06-05T00:00:00Z:1.2.3",
            "log:waiting for guest update shutdown result timeoutSeconds=6.0",
            "load",
            "log:waiting for guest update shutdown worker",
            "status:updating:apply-bundle:waiting for guest update shutdown worker",
            "sleep",
            "load",
            "log:guest update shutdown result ready message=ready",
            "log:guest update shutdown ready version=1.2.3",
        ])
    }

    func testShutdownPreservesGuestFailureReadFailureAndTimeoutMeanings() {
        let guestFailure = ShutdownHarness(results: [
            .loaded(shutdownResult(status: .failed, phase: nil, requestId: "request-1", message: "guest failed")),
        ])
        XCTAssertThrowsError(try guestFailure.workflow.prepareForUpdate(
            version: "1.2.3",
            context: guestFailure.context,
            actions: guestFailure.operations
        )) { error in
            XCTAssertEqual(error as? RuntimeGuestUpdateUseCaseError, .operationFailed("guest failed"))
        }
        XCTAssertTrue(guestFailure.events.contains("log:guest update shutdown result failed message=guest failed"))

        let readFailure = ShutdownHarness(results: [.failed("permission denied")])
        XCTAssertThrowsError(try readFailure.workflow.prepareForUpdate(
            version: "1.2.3",
            context: readFailure.context,
            actions: readFailure.operations
        )) { error in
            XCTAssertEqual(
                error as? RuntimeGuestUpdateUseCaseError,
                .operationFailed("failed to read guest update shutdown result: permission denied")
            )
        }

        let timeout = ShutdownHarness(results: [.missing, .missing])
        XCTAssertThrowsError(try timeout.workflow.prepareForUpdate(
            version: "1.2.3",
            context: timeout.context,
            actions: timeout.operations
        )) { error in
            XCTAssertEqual(error as? RuntimeGuestUpdateUseCaseError, .operationFailed("guest update shutdown timed out"))
        }
    }

    final class ActivationHarness {
        let workflow = RuntimeGuestActivationWorkflow()
        let context = RuntimeGuestActivationWorkflowContext(
            guestRunDirectory: URL(fileURLWithPath: "/guest/run"),
            waitTimeoutSeconds: 6
        )
        var events: [String] = []
        var results: [RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument>]
        var vmLoaded = false

        lazy var operations = RuntimeGuestActivationWorkflowActions(
            requireCapability: { [self] in events.append("capability") },
            createGuestRunDirectory: { [self] directory in events.append("create:\(directory.path)") },
            removeActivationResult: { [self] in events.append("remove-result") },
            writeActivationRequest: { [self] request in
                events.append("request:\(request.id):\(request.requestedAt):\(request.version)")
            },
            loadActivationResult: { [self] in
                events.append("load")
                guard !results.isEmpty else {
                    return .missing
                }
                return results.removeFirst()
            },
            isVMServiceLoaded: { [self] in
                events.append("vm-loaded")
                return vmLoaded
            },
            startVMService: { [self] in events.append("start-vm") },
            writeProgressStatus: { [self] status, operation, message in
                events.append("status:\(status.rawValue):\(operation.rawValue):\(message)")
            },
            requestID: { "request-1" },
            timestamp: { "2026-06-05T00:00:00Z" },
            sleep: { [self] in events.append("sleep") },
            log: { [self] message in events.append("log:\(message)") }
        )

        init(results: [RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument>]) {
            self.results = results
        }
    }

    final class ShutdownHarness {
        let workflow = RuntimeGuestShutdownWorkflow()
        let context = RuntimeGuestShutdownWorkflowContext(
            guestRunDirectory: URL(fileURLWithPath: "/guest/run"),
            waitTimeoutSeconds: 6
        )
        var events: [String] = []
        var results: [RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>]

        lazy var operations = RuntimeGuestShutdownWorkflowActions(
            requireCapability: { [self] in events.append("capability") },
            createGuestRunDirectory: { [self] directory in events.append("create:\(directory.path)") },
            removeShutdownResult: { [self] in events.append("remove-result") },
            writeShutdownRequest: { [self] request in
                events.append("request:\(request.id):\(request.requestedAt):\(request.version)")
            },
            loadShutdownResult: { [self] in
                events.append("load")
                guard !results.isEmpty else {
                    return .missing
                }
                return results.removeFirst()
            },
            writeProgressStatus: { [self] status, operation, message in
                events.append("status:\(status.rawValue):\(operation.rawValue):\(message)")
            },
            requestID: { "request-1" },
            timestamp: { "2026-06-05T00:00:00Z" },
            sleep: { [self] in events.append("sleep") },
            log: { [self] message in events.append("log:\(message)") }
        )

        init(results: [RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>]) {
            self.results = results
        }
    }
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

private func activationResult(
    status: GuestActivationStatus,
    requestId: String?,
    message: String?
) -> GuestUpdateActivationResultDocument {
    GuestUpdateActivationResultDocument(
        schemaVersion: 2,
        requestId: requestId,
        operation: .activateGuestUpdate,
        status: status,
        message: message,
        updatedAt: "2026-06-05T00:00:01Z"
    )
}

private func shutdownResult(
    status: GuestShutdownStatus,
    phase: GuestShutdownPhase?,
    requestId: String?,
    message: String?
) -> GuestUpdateShutdownResultDocument {
    GuestUpdateShutdownResultDocument(
        schemaVersion: 1,
        requestId: requestId,
        operation: .prepareUpdateShutdown,
        status: status,
        shutdownPhase: phase,
        message: message,
        updatedAt: "2026-06-05T00:00:01Z"
    )
}
