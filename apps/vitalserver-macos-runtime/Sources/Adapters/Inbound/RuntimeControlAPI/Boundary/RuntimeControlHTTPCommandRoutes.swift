import Foundation
import Contracts
import RuntimeControl

@MainActor
struct RuntimeControlHTTPCommandRoutes {
    let handler: any RuntimeControlAPIReadHandler

    func route(
        _ endpoint: RuntimeControlAPIEndpoint,
        request: RuntimeControlHTTPRequest
    ) async throws -> RuntimeControlHTTPResponse? {
        switch endpoint {
        case .startRuntimeProvider, .stopRuntimeProvider, .restartRuntimeProvider:
            let action: RuntimeProviderCommandAction
            switch endpoint {
            case .startRuntimeProvider:
                action = .start
            case .stopRuntimeProvider:
                action = .stop
            case .restartRuntimeProvider:
                action = .restart
            default:
                preconditionFailure("unreachable Runtime Provider command endpoint")
            }
            let result = try await handler.controlRuntimeProvider(action)
            return try RuntimeControlHTTPResponseFactory.json(
                result,
                status: result.state == .completed ? .ok : .serviceUnavailable
            )
        case .applySettings:
            let settingsRequest = try request.decodedBody(RuntimeApplyProductSettingsRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.applyRuntimeProductSettings(settingsRequest.settings),
                status: .accepted
            )
        case .applyAdminPassword:
            let adminRequest = try request.decodedBody(RuntimeAdminPasswordRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.applyRuntimeAdminPassword(adminRequest.password),
                status: .accepted
            )
        case .applyRedisRelaySettings:
            let relayRequest = try request.decodedBody(RuntimeRedisRelaySettingsApplyRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.applyRuntimeRedisRelaySettings(relayRequest),
                status: .accepted
            )
        case .createLabSession:
            let createRequest = try request.decodedBody(RuntimeLabSessionCreateRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.createLabSession(createRequest))
        case .createLabBeds:
            let createRequest = try request.decodedBody(RuntimeLabBedCreateRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.createLabBeds(createRequest))
        case .deleteLabBeds:
            let deleteRequest = try request.decodedBody(RuntimeLabBedDeleteRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.deleteLabBeds(deleteRequest))
        case .resetLabBeds:
            return try await RuntimeControlHTTPResponseFactory.json(handler.resetLabBeds())
        case .createLabRecorders:
            let createRequest = try request.decodedBody(RuntimeLabRecorderCreateRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.createLabRecorders(createRequest))
        case .deleteLabRecorders:
            let deleteRequest = try request.decodedBody(RuntimeLabRecorderDeleteRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.deleteLabRecorders(deleteRequest))
        case .resetLabRecorders:
            return try await RuntimeControlHTTPResponseFactory.json(handler.resetLabRecorders())
        case .hideVitalDBRecorders:
            let request = try request.decodedBody(RuntimeVitalDBRecorderVisibilityRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.hideVitalDBRecorders(request))
        case .unhideVitalDBRecorders:
            let request = try request.decodedBody(RuntimeVitalDBRecorderVisibilityRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.unhideVitalDBRecorders(request))
        case .deleteVitalDBRecorders:
            let request = try request.decodedBody(RuntimeVitalDBRecorderVisibilityRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.deleteVitalDBRecorders(request))
        case .hideVitalDBBeds:
            let request = try request.decodedBody(RuntimeVitalDBBedVisibilityRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.hideVitalDBBeds(request))
        case .unhideVitalDBBeds:
            let request = try request.decodedBody(RuntimeVitalDBBedVisibilityRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.unhideVitalDBBeds(request))
        case .deleteVitalDBBeds:
            let request = try request.decodedBody(RuntimeVitalDBBedVisibilityRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.deleteVitalDBBeds(request))
        case .startLabSession:
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.startLabSession(sessionId: try request.runtimeLabSessionID())
            )
        case .stopLabSession:
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.stopLabSession(sessionId: try request.runtimeLabSessionID())
            )
        case .replayLabVitalFile:
            let replayRequest = try request.decodedBody(RuntimeLabVitalFileReplayRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.replayLabVitalFile(replayRequest))
        case .uploadLabVitalFile:
            let uploadRequest = try request.decodedBody(RuntimeLabVitalFileUploadRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.uploadLabVitalFile(uploadRequest))
        case .startGuestService:
            let controlRequest = RuntimeGuestServiceControlRequest(
                service: try request.runtimeGuestServiceName()
            )
            return try await RuntimeControlHTTPResponseFactory.json(handler.startGuestService(controlRequest))
        case .stopGuestService:
            let controlRequest = RuntimeGuestServiceControlRequest(
                service: try request.runtimeGuestServiceName()
            )
            return try await RuntimeControlHTTPResponseFactory.json(handler.stopGuestService(controlRequest))
        case .restartGuestService:
            let restartRequest = RuntimeGuestServiceRestartRequest(
                service: try request.runtimeGuestServiceName()
            )
            return try await RuntimeControlHTTPResponseFactory.json(handler.restartGuestService(restartRequest))
        case .repairRuntimeServices:
            return try await RuntimeControlHTTPResponseFactory.json(handler.repairRuntimeServices())
        case .repairProxy:
            return try await RuntimeControlHTTPResponseFactory.json(handler.repairProxy())
        case .repairDatastore:
            return try await RuntimeControlHTTPResponseFactory.json(handler.repairDatastore())
        case .repairVMDisk:
            return try await RuntimeControlHTTPResponseFactory.json(handler.repairVMDisk())
        case .createRedisBackup:
            return try await RuntimeControlHTTPResponseFactory.json(handler.createRedisBackup())
        case .createRuntimeDataBackup:
            return try await RuntimeControlHTTPResponseFactory.json(handler.createRuntimeDataBackup())
        case .updateBundleSummary:
            let bundleRequest = try request.decodedBody(RuntimeUpdateBundleRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.updateBundleSummary(bundle: bundleRequest.bundle)
            )
        case .verifyUpdateBundle:
            let bundleRequest = try request.decodedBody(RuntimeUpdateBundleRequest.self)
            let response = try await handler.verifyUpdateBundle(bundle: bundleRequest.bundle)
            return try RuntimeControlHTTPResponseFactory.json(
                platformWorkflowOperation(response.result, kind: .updateVerify),
                status: .accepted
            )
        case .applyUpdateBundle:
            let bundleRequest = try request.decodedBody(RuntimeUpdateBundleRequest.self)
            let response = try await handler.applyUpdateBundle(bundle: bundleRequest.bundle)
            return try RuntimeControlHTTPResponseFactory.json(
                platformWorkflowOperation(response.result, kind: .updateApply),
                status: .accepted
            )
        case .rollbackRelease:
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.rollbackRelease(),
                status: .accepted
            )
        case .rollbackBackup:
            let backupRequest = try request.decodedBody(RuntimeBackupRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.rollbackBackup(backupRequest.backup))
        case .restoreRedisBackup:
            let backupRequest = try request.decodedBody(RuntimeBackupRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.restoreRedisBackup(backupRequest.backup))
        case .restoreRuntimeDataBackup:
            let backupRequest = try request.decodedBody(RuntimeBackupRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.restoreRuntimeDataBackup(backupRequest.backup))
        case .deleteBackup,
             .deleteUpdateBackup,
             .deleteRuntimeDataBackup:
            let backupRequest = try request.decodedBody(RuntimeBackupRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.deleteBackup(backupRequest.backup))
        case .exportLogs:
            let exportRequest = try request.decodedBody(RuntimeExportLogsRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.exportLogs(destination: exportRequest.destination)
            )
        case .createSupportExport:
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.createPlatformSupportExport(),
                status: .accepted
            )
        case .acquireOperationLease:
            let acquireRequest = try request.decodedBody(RuntimeOperationLeaseAcquireRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.acquireOperationLease(acquireRequest)
            )
        case .heartbeatOperationLease:
            let heartbeatRequest = try request.decodedBody(RuntimeOperationLeaseHeartbeatRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.heartbeatOperationLease(heartbeatRequest)
            )
        case .releaseOperationLease:
            let releaseRequest = try request.decodedBody(RuntimeOperationLeaseReleaseRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.releaseOperationLease(releaseRequest)
            )
        case .putGuestAddress:
            let guestAddressRequest = try request.decodedBody(RuntimeGuestAddressPutRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.putGuestAddressResource(guestAddressRequest)
            )
        case .putVMLifecycle:
            let lifecycleRequest = try request.decodedBody(RuntimeVMLifecyclePutRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.putVMLifecycleResource(lifecycleRequest)
            )
        case .uninstall:
            let uninstallRequest = try request.decodedBody(RuntimeUninstallRequest.self)
            let response = try await handler.uninstallRuntime(mode: uninstallRequest.mode)
            return try RuntimeControlHTTPResponseFactory.json(
                platformWorkflowOperation(response.result, kind: .uninstall),
                status: .accepted
            )
        case .platformCapabilities,
             .runtimeCapabilities,
             .platformState,
             .platformStateStream,
             .operationState,
             .platformWorkflow,
             .guestAddress,
             .vmLifecycle,
             .events,
             .vitalDBObservation,
             .vitalDBObservationStream,
             .vitalDBRecorders,
             .vitalDBRecorder,
             .vitalDBRecorderActivity,
             .vitalDBBeds,
             .vitalDBBed,
             .vitalDBRelationships,
             .health,
             .settings,
             .labScenarios,
             .labVitalFiles,
             .labBeds,
             .labRecorders,
             .labSession,
             .release,
             .installInfo,
             .guestStackStatus,
             .guestServices,
             .guestServiceStatus,
             .guestServiceResource,
             .redisRelayStatus,
             .redisRelaySettings,
             .logText,
             .logStream,
             .backups,
             .redisBackups,
             .runtimeDataBackups:
            return nil
        }
    }

    private func platformWorkflowOperation(
        _ result: RuntimeCommandResult,
        kind: PlatformWorkflowKind
    ) -> PlatformWorkflowOperation {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let succeeded = result.exitCode == 0
            && result.executionIssue == nil
            && result.outputIssues.isEmpty
        let failureKind: String
        switch kind {
        case .updateVerify:
            failureKind = "updateVerifyFailed"
        case .updateApply:
            failureKind = "updateApplyFailed"
        case .rollback:
            failureKind = "rollbackFailed"
        case .uninstall:
            failureKind = "uninstallFailed"
        case .supportExport:
            failureKind = "supportExportFailed"
        }
        let failure = succeeded ? nil : PlatformWorkflowFailure(
            kind: failureKind,
            message: RuntimeProcessFailureMessageFormatter.message(
                exitCode: result.exitCode,
                stdout: result.stdout,
                stderr: result.stderr,
                outputIssues: result.outputIssues,
                executionIssue: result.executionIssue
            )
        )
        return PlatformWorkflowOperation(
            operationId: UUID().uuidString.lowercased(),
            kind: kind,
            state: succeeded ? .completed : .failed,
            startedAt: timestamp,
            updatedAt: timestamp,
            release: nil,
            failure: failure
        )
    }
}
