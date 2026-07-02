import Contracts
import RuntimeControl

@MainActor
struct RuntimeControlHTTPReadRoutes {
    let handler: any RuntimeControlAPIReadHandler

    func route(
        _ endpoint: RuntimeControlAPIEndpoint,
        request: RuntimeControlHTTPRequest
    ) async throws -> RuntimeControlHTTPResponse? {
        switch endpoint {
        case .capabilities:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadCapabilities())
        case .overview:
            return try await RuntimeControlHTTPResponseFactory.json(loadOverview())
        case .overviewStream:
            return try await RuntimeControlHTTPResponseFactory.eventStream(
                id: "runtime-overview",
                event: "runtime-overview",
                value: loadOverview()
            )
        case .status:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadStatus())
        case .statusStream:
            return try await RuntimeControlHTTPResponseFactory.eventStream(
                id: "runtime-status",
                event: "runtime-status",
                value: handler.loadStatus()
            )
        case .events:
            let query = try request.runtimeEventQuery()
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadEvents(query: query))
        case .eventStream:
            let query = try request.runtimeEventQuery()
            return try await RuntimeControlHTTPResponseFactory.eventStream(handler.loadEvents(query: query))
        case .vitalDBObservation:
            return try await RuntimeControlHTTPResponseFactory.json(loadVitalDBObservation())
        case .vitalDBObservationStream:
            return try await RuntimeControlHTTPResponseFactory.eventStream(
                id: "vitaldb-observation",
                event: "vitaldb-observed",
                value: handler.loadVitalDBObservationSnapshot()
            )
        case .vitalDBRecorders:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadVitalDBRecorders())
        case .vitalDBRecorder:
            let vrcode = try request.vitalDBRecorderCode()
            let recorders = try await handler.loadVitalDBRecorders().recorders
            guard let recorder = recorders.first(where: { $0.vrcode == vrcode }) else {
                return RuntimeControlHTTPResponseFactory.resourceNotFound("VitalDB recorder not found: \(vrcode)")
            }
            return try RuntimeControlHTTPResponseFactory.json(recorder)
        case .vitalDBRecorderActivity:
            let query = try request.vitalDBRecorderActivityWindowQuery()
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.loadVitalDBRecorderActivityWindow(query: query)
            )
        case .vitalDBBeds:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadVitalDBRecorders().beds)
        case .vitalDBBed:
            let bedID = try request.vitalDBBedID()
            let beds = try await handler.loadVitalDBRecorders().beds
            guard let bed = beds.first(where: { $0.bedID == bedID }) else {
                return RuntimeControlHTTPResponseFactory.resourceNotFound("VitalDB bed not found: \(bedID)")
            }
            return try RuntimeControlHTTPResponseFactory.json(bed)
        case .vitalDBRelationships:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadVitalDBRelationships())
        case .health:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadHealthStatus())
        case .settings:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadSettings())
        case .release:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadReleaseInfo())
        case .installInfo:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadInstallInfo())
        case .labScenarios:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadLabScenarios())
        case .labVitalFiles:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadLabVitalFiles())
        case .labBeds:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadLabBeds())
        case .labRecorders:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadLabRecorders())
        case .labSession:
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.loadLabSession(sessionId: try request.runtimeLabSessionID())
            )
        case .guestStackStatus:
            return try await RuntimeControlHTTPResponseFactory.json(handler.guestStackStatus())
        case .guestServices:
            return try await RuntimeControlHTTPResponseFactory.json(handler.listGuestServices())
        case .guestServiceStatus:
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.guestServiceStatus(try request.runtimeGuestServiceName())
            )
        case .logText:
            let logRequest = try request.decodedBody(RuntimeLogTextRequest.self)
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadLogText(request: logRequest))
        case .logStream:
            let logRequest = try request.runtimeLogTextRequest()
            return try await RuntimeControlHTTPResponseFactory.eventStream(
                id: "runtime-log-\(logRequest.source.rawValue)",
                event: "runtime-log",
                value: handler.loadLogText(request: logRequest)
            )
        case .backups:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadBackups())
        case .redisBackups:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadRedisBackups())
        case .runtimeDataBackups:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadRuntimeDataBackups())
        case .applySettings,
             .createLabBeds,
             .deleteLabBeds,
             .resetLabBeds,
             .createLabRecorders,
             .deleteLabRecorders,
             .resetLabRecorders,
             .hideVitalDBRecorders,
             .unhideVitalDBRecorders,
             .deleteVitalDBRecorders,
             .hideVitalDBBeds,
             .unhideVitalDBBeds,
             .deleteVitalDBBeds,
             .createLabSession,
             .startLabSession,
             .stopLabSession,
             .replayLabVitalFile,
             .uploadLabVitalFile,
             .startGuestService,
             .stopGuestService,
             .restartGuestService,
             .repairRuntimeServices,
             .repairProxy,
             .repairDatastore,
             .repairVMDisk,
             .createRedisBackup,
             .createRuntimeDataBackup,
             .updateBundleSummary,
             .verifyUpdateBundle,
             .applyUpdateBundle,
             .rollbackBackup,
             .deleteBackup,
             .deleteUpdateBackup,
             .deleteRuntimeDataBackup,
             .exportLogs,
             .uninstall,
             .restoreRedisBackup,
             .restoreRuntimeDataBackup:
            return nil
        }
    }

    private func loadOverview() async throws -> RuntimeControlOverview {
        try await RuntimeControlOverviewAssembler(handler: handler).load()
    }

    private func loadVitalDBObservation() async throws -> VitalDBObservationDocument? {
        let snapshot = try await handler.loadVitalDBObservationSnapshot()
        return snapshot.observation
    }
}
