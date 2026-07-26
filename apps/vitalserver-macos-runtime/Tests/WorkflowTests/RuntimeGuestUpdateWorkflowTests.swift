import Application
import Contracts
import Foundation
import Workflow
import XCTest
import Errors

final class RuntimeGuestUpdateWorkflowTests: XCTestCase {
    func testActivationSkipsWhenManifestDoesNotContainGuestDeployArtifact() throws {
        let harness = ActivationHarness()

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
        let harness = ActivationHarness()

        try harness.workflow.activateIfNeeded(
            manifest: manifest(artifacts: [.guestDeploy]),
            context: harness.context,
            actions: harness.operations
        )

        XCTAssertEqual(harness.events, [
            "log:guest update activation requested version=1.2.3",
            "capability",
            "vm-loaded",
            "start-vm",
            "activate:request-1:1.2.3",
            "log:guest update activation operation completed operationId=update-activation-1",
            "log:guest update activation completed version=1.2.3",
        ])
    }

    func testActivationPreservesGuestOperationFailure() {
        let failure = ActivationHarness(
            activationError: RuntimeGuestUpdateUseCaseError.operationFailed(
                "guest update activation failed"
            )
        )
        XCTAssertThrowsError(try failure.workflow.activateIfNeeded(
            manifest: manifest(artifacts: [.guestDeploy]),
            context: failure.context,
            actions: failure.operations
        )) { error in
            XCTAssertEqual(error as? RuntimeGuestUpdateUseCaseError, .operationFailed("guest update activation failed"))
        }
        XCTAssertTrue(failure.events.contains("activate:request-1:1.2.3"))
    }

    func testShutdownExecutesRequestAndWaitsForReadyResult() throws {
        let harness = ShutdownHarness(operationReads: [
            updateShutdownOperation(state: .completed, shutdownPhase: "poweroff-ready"),
        ])

        try harness.workflow.prepareForUpdate(
            version: "1.2.3",
            context: harness.context,
            actions: harness.operations
        )

        XCTAssertEqual(harness.events, [
            "log:guest update shutdown requested version=1.2.3",
            "capability",
            "prepare:request-1:1.2.3",
            "log:waiting for guest update shutdown result timeoutSeconds=6.0",
            "log:guest update shutdown operation running",
            "status:updating:apply-bundle:guest update shutdown operation running",
            "sleep",
            "load-operation:update-shutdown-1",
            "log:guest update shutdown operation completed operationId=update-shutdown-1",
            "poweroff",
            "log:guest poweroff requested operationId=guest-poweroff-1",
            "log:guest update shutdown ready version=1.2.3",
        ])
    }

    func testShutdownProgressUsesContextStatusAndOperation() throws {
        let harness = ShutdownHarness(operationReads: [
            updateShutdownOperation(state: .completed, shutdownPhase: "poweroff-ready"),
        ])
        let context = RuntimeGuestShutdownWorkflowContext(
            guestRunDirectory: URL(fileURLWithPath: "/guest/run"),
            waitTimeoutSeconds: 6,
            progressStatus: .recovering,
            progressOperation: .configure
        )

        try harness.workflow.prepareForUpdate(
            version: "1.2.3",
            context: context,
            actions: harness.operations
        )

        XCTAssertTrue(harness.events.contains(
            "status:recovering:configure:guest update shutdown operation running"
        ))
        XCTAssertFalse(harness.events.contains {
            $0 == "status:updating:apply-bundle:guest update shutdown operation running"
        })
    }

    func testShutdownRejectsPoweroffReadyWithoutPostgresBackupReceipt() {
        let completedWithoutPostgres = RuntimeGuestControlServiceOperation(
            operationId: "update-shutdown-1",
            service: "update-shutdown",
            command: .updateShutdown,
            state: .completed,
            createdAt: "2026-07-01T00:00:00+00:00",
            updatedAt: "2026-07-01T00:00:01+00:00",
            result: RuntimeGuestControlOperationResult(
                shutdownPhase: "poweroff-ready",
                redisBackupPath: "/mnt/tirosh/backups/redis/update.tar.gz"
            )
        )
        let harness = ShutdownHarness(initialOperation: completedWithoutPostgres)

        XCTAssertThrowsError(try harness.workflow.prepareForUpdate(
            version: "1.2.3",
            context: harness.context,
            actions: harness.operations
        )) { error in
            XCTAssertEqual(
                error as? RuntimeGuestUpdateUseCaseError,
                .operationFailed(
                    "guest update shutdown completed without PostgreSQL backup receipt operationId=update-shutdown-1"
                )
            )
        }
        XCTAssertFalse(harness.events.contains("poweroff"))
    }

    func testShutdownPreservesGuestFailureAndTimeoutMeanings() {
        let guestFailure = ShutdownHarness(
            initialOperation: updateShutdownOperation(
                state: .failed,
                failure: RuntimeGuestControlOperationFailure(
                    kind: "guest-shutdown-failed",
                    message: "guest failed"
                )
            )
        )
        XCTAssertThrowsError(try guestFailure.workflow.prepareForUpdate(
            version: "1.2.3",
            context: guestFailure.context,
            actions: guestFailure.operations
        )) { error in
            XCTAssertEqual(
                error as? RuntimeGuestUpdateUseCaseError,
                .operationFailed(
                    "guest update shutdown failed operationId=update-shutdown-1 kind=guest-shutdown-failed reason=guest failed"
                )
            )
        }

        let timeout = ShutdownHarness(operationReads: [
            updateShutdownOperation(state: .running),
            updateShutdownOperation(state: .running),
        ])
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
        let context = RuntimeGuestActivationWorkflowContext()
        var events: [String] = []
        var activationError: Error?
        var vmLoaded = false

        lazy var operations = RuntimeGuestActivationWorkflowActions(
            requireCapability: { [self] in events.append("capability") },
            activateUpdate: { [self] requestID, version in
                events.append("activate:\(requestID):\(version)")
                if let activationError {
                    throw activationError
                }
                return RuntimeGuestControlServiceOperation(
                    operationId: "update-activation-1",
                    service: "update-activation",
                    command: .updateActivation,
                    state: .completed,
                    createdAt: "2026-07-01T00:00:00+00:00",
                    updatedAt: "2026-07-01T00:00:01+00:00"
                )
            },
            isVMServiceLoaded: { [self] in
                events.append("vm-loaded")
                return vmLoaded
            },
            startVMService: { [self] in events.append("start-vm") },
            requestID: { "request-1" },
            log: { [self] message in events.append("log:\(message)") }
        )

        init(activationError: Error? = nil) {
            self.activationError = activationError
        }
    }

    final class ShutdownHarness {
        let workflow = RuntimeGuestShutdownWorkflow()
        let context = RuntimeGuestShutdownWorkflowContext(
            guestRunDirectory: URL(fileURLWithPath: "/guest/run"),
            waitTimeoutSeconds: 6
        )
        var events: [String] = []
        var initialOperation: RuntimeGuestControlServiceOperation
        var operationReads: [RuntimeGuestControlServiceOperation]

        lazy var operations = RuntimeGuestShutdownWorkflowActions(
            requireCapability: { [self] in events.append("capability") },
            prepareUpdateShutdown: { [self] requestID, version in
                events.append("prepare:\(requestID):\(version)")
                return initialOperation
            },
            loadOperation: { [self] operationID in
                events.append("load-operation:\(operationID)")
                return operationReads.isEmpty ? initialOperation : operationReads.removeFirst()
            },
            requestGuestPoweroff: { [self] in
                events.append("poweroff")
                return RuntimeGuestControlServiceOperation(
                    operationId: "guest-poweroff-1",
                    service: "guest-poweroff",
                    command: .requestGuestPoweroff,
                    state: .completed,
                    createdAt: "2026-07-01T00:00:00+00:00",
                    updatedAt: "2026-07-01T00:00:01+00:00"
                )
            },
            writeProgressStatus: { [self] status, operation, message in
                events.append("status:\(status.rawValue):\(operation.rawValue):\(message)")
            },
            requestID: { "request-1" },
            sleep: { [self] in events.append("sleep") },
            log: { [self] message in events.append("log:\(message)") }
        )

        init(
            initialOperation: RuntimeGuestControlServiceOperation = updateShutdownOperation(state: .running),
            operationReads: [RuntimeGuestControlServiceOperation] = []
        ) {
            self.initialOperation = initialOperation
            self.operationReads = operationReads
        }
    }
}

private func updateShutdownOperation(
    state: RuntimeGuestControlOperationState,
    shutdownPhase: String? = nil,
    failure: RuntimeGuestControlOperationFailure? = nil
) -> RuntimeGuestControlServiceOperation {
    RuntimeGuestControlServiceOperation(
        operationId: "update-shutdown-1",
        service: "update-shutdown",
        command: .updateShutdown,
        state: state,
        createdAt: "2026-07-01T00:00:00+00:00",
        updatedAt: "2026-07-01T00:00:01+00:00",
        failure: failure,
        result: shutdownPhase.map {
            RuntimeGuestControlOperationResult(
                shutdownPhase: $0,
                redisBackupPath: "/mnt/tirosh/backups/redis/update.tar.gz",
                postgresBackupPath: "/mnt/tirosh/backups/postgres/update.tar.gz"
            )
        }
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
