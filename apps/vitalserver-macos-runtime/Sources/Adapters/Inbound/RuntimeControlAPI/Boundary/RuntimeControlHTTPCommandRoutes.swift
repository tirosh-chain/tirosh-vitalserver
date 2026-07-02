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
        case .applySettings:
            let settingsRequest = try request.decodedBody(RuntimeApplySettingsRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.applySettings(settingsRequest.settings))
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
        case .startGuestService:
            let controlRequest = try request.decodedBody(RuntimeGuestServiceControlRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.startGuestService(controlRequest))
        case .stopGuestService:
            let controlRequest = try request.decodedBody(RuntimeGuestServiceControlRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.stopGuestService(controlRequest))
        case .restartGuestService:
            let restartRequest = try request.decodedBody(RuntimeGuestServiceRestartRequest.self)
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
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.verifyUpdateBundle(bundle: bundleRequest.bundle)
            )
        case .applyUpdateBundle:
            let bundleRequest = try request.decodedBody(RuntimeUpdateBundleRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.applyUpdateBundle(bundle: bundleRequest.bundle)
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
        case .uninstall:
            let uninstallRequest = try request.decodedBody(RuntimeUninstallRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.uninstallRuntime(mode: uninstallRequest.mode)
            )
        case .capabilities,
             .overview,
             .overviewStream,
             .status,
             .statusStream,
             .events,
             .eventStream,
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
             .labBeds,
             .labRecorders,
             .labSession,
             .release,
             .installInfo,
             .guestStackStatus,
             .guestServices,
             .guestServiceStatus,
             .logText,
             .logStream,
             .backups,
             .redisBackups,
             .runtimeDataBackups:
            return nil
        }
    }
}
