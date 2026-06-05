import Contracts
import Core
import Foundation
import RuntimeWorkflow
import XCTest

final class RuntimeGuestActivationRunnerTests: XCTestCase {
    func testActivateSkipsWhenGuestDeployArtifactIsAbsent() throws {
        let events = EventLog()
        let runner = makeRunner(
            events: events,
            loadResult: { .missing }
        )

        try runner.activateIfNeeded(manifest: manifest(artifacts: [.appBundle]))

        XCTAssertEqual(events.values, [
            "log:guest update activation not required",
        ])
    }

    func testActivateWritesRequestStartsVMAndWaitsForResult() throws {
        let events = EventLog()
        var results: [RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument>] = [
            .missing,
            .loaded(result(status: .running, requestId: "request-1", message: "loading")),
            .loaded(result(status: .completed, requestId: "request-1", message: "done")),
        ]
        let runner = makeRunner(
            events: events,
            vmServiceLoaded: false,
            loadResult: { results.removeFirst() }
        )

        try runner.activateIfNeeded(manifest: manifest(artifacts: [.guestDeploy]))

        XCTAssertEqual(events.values, [
            "log:guest update activation requested version=1.2.3",
            "capability",
            "mkdir",
            "remove-result",
            "write-request:request-1:2026-05-22T00:00:00Z:1.2.3",
            "start-vm",
            "log:waiting for guest update activation result timeoutSeconds=180.0",
            "log:waiting for guest update activation worker",
            "progress:waiting for guest update activation worker",
            "sleep",
            "sleep",
            "log:guest update activation result completed message=done",
            "log:guest update activation completed version=1.2.3",
        ])
    }

    func testActivateDoesNotStartVMWhenItIsAlreadyLoaded() throws {
        let events = EventLog()
        let runner = makeRunner(
            events: events,
            vmServiceLoaded: true,
            loadResult: {
                .loaded(self.result(status: .completed, requestId: "request-1", message: "done"))
            }
        )

        try runner.activateIfNeeded(manifest: manifest(artifacts: [.guestDeploy]))

        XCTAssertFalse(events.values.contains("start-vm"))
        XCTAssertTrue(events.values.contains("write-request:request-1:2026-05-22T00:00:00Z:1.2.3"))
    }

    func testActivateStopsBeforeWritingRequestWhenCapabilityIsMissing() {
        let events = EventLog()
        let runner = makeRunner(
            events: events,
            requireCapability: {
                throw RuntimeWorkflowError.operationFailed("guest capability missing: activate-update")
            },
            loadResult: { .missing }
        )

        XCTAssertThrowsError(try runner.activateIfNeeded(manifest: manifest(artifacts: [.guestDeploy]))) { error in
            XCTAssertEqual(String(describing: error), "guest capability missing: activate-update")
        }
        XCTAssertEqual(events.values, [
            "log:guest update activation requested version=1.2.3",
            "capability",
        ])
    }

    func testActivatePropagatesFailedResult() {
        let events = EventLog()
        let runner = makeRunner(
            events: events,
            loadResult: {
                .loaded(self.result(status: .failed, requestId: "request-1", message: "compose failed"))
            }
        )

        XCTAssertThrowsError(try runner.activateIfNeeded(manifest: manifest(artifacts: [.guestDeploy]))) { error in
            XCTAssertEqual(String(describing: error), "runtime health check failed")
        }
        XCTAssertTrue(events.values.contains("log:guest update activation result failed message=compose failed"))
    }

    private func makeRunner(
        events: EventLog,
        vmServiceLoaded: Bool = false,
        requireCapability: @escaping () throws -> Void = {},
        loadResult: @escaping () -> RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument>
    ) -> RuntimeGuestActivationRunner {
        RuntimeGuestActivationRunner(
            requireCapability: {
                events.append("capability")
                try requireCapability()
            },
            createRunDirectory: {
                events.append("mkdir")
            },
            removePreviousResult: {
                events.append("remove-result")
            },
            requestID: {
                "request-1"
            },
            timestamp: {
                "2026-05-22T00:00:00Z"
            },
            writeRequest: { request in
                events.append("write-request:\(request.id):\(request.requestedAt):\(request.version)")
            },
            isVMServiceLoaded: {
                vmServiceLoaded
            },
            startVMService: {
                events.append("start-vm")
            },
            loadResult: loadResult,
            reportProgress: { message in
                events.append("progress:\(message)")
            },
            sleep: {
                events.append("sleep")
            },
            log: { message in
                events.append("log:\(message)")
            },
            waitTimeoutSeconds: 180
        )
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

    private final class EventLog {
        private(set) var values: [String] = []

        func append(_ value: String) {
            values.append(value)
        }
    }
}
