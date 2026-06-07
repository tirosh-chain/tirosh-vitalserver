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
        case .startServices:
            return try await RuntimeControlHTTPResponseFactory.json(handler.startRuntimeServices())
        case .stopServices:
            return try await RuntimeControlHTTPResponseFactory.json(handler.stopRuntimeServices())
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
        case .deleteBackup:
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
                handler.uninstallRuntime(clean: uninstallRequest.clean)
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
             .vitalDBBeds,
             .vitalDBBed,
             .vitalDBRelationships,
             .health,
             .settings,
             .release,
             .installInfo,
             .logText,
             .logStream,
             .backups,
             .redisBackups,
             .restoreRedisBackup:
            return nil
        }
    }
}
