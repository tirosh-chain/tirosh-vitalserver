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
        case .platformCapabilities:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadPlatformCapabilities())
        case .runtimeCapabilities:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadRuntimeCapabilities())
        case .platformState:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadPlatformState())
        case .platformStateStream:
            return try await RuntimeControlHTTPResponseFactory.eventStream(
                id: "platform-state",
                event: "platform-state",
                value: handler.loadPlatformState()
            )
        case .operationState:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadOperationState())
        case .platformWorkflow:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadPlatformWorkflow())
        case .guestAddress:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadGuestAddressResource())
        case .vmLifecycle:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadVMLifecycleResource())
        case .events:
            let query = try request.runtimeOperationEventQuery()
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadRuntimeOperationEvents(query: query))
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
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadVitalDBBeds())
        case .vitalDBBed:
            let bedID = try request.vitalDBBedID()
            let beds = try await handler.loadVitalDBBeds().beds
            guard let bed = beds.first(where: { $0.bedID == bedID }) else {
                return RuntimeControlHTTPResponseFactory.resourceNotFound("VitalDB bed not found: \(bedID)")
            }
            return try RuntimeControlHTTPResponseFactory.json(bed)
        case .vitalDBRelationships:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadVitalDBRelationships())
        case .health:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadHealthStatus())
        case .settings:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadRuntimeProductSettings())
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
        case .labSessions:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadLabSessions())
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
        case .guestServiceResource:
            return try await RuntimeControlHTTPResponseFactory.json(
                handler.guestServiceResource(try request.runtimeGuestServiceName())
            )
        case .redisRelayStatus:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadRedisRelayStatus())
        case .redisRelaySettings:
            return try await RuntimeControlHTTPResponseFactory.json(handler.loadRuntimeRedisRelaySettings())
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
             .applyAdminPassword,
             .applyRedisRelaySettings,
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
             .startLabRecorder,
             .stopLabRecorder,
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
             .rollbackRelease,
             .rollbackBackup,
             .deleteBackup,
             .deleteUpdateBackup,
             .deleteRuntimeDataBackup,
             .exportLogs,
             .createSupportExport,
             .acquireOperationLease,
             .heartbeatOperationLease,
             .releaseOperationLease,
             .putGuestAddress,
             .putVMLifecycle,
             .startRuntimeProvider,
             .stopRuntimeProvider,
             .restartRuntimeProvider,
             .uninstall,
             .restoreRedisBackup,
             .restoreRuntimeDataBackup:
            return nil
        }
    }

    private func loadVitalDBObservation() async throws -> VitalDBObservationDocument? {
        let snapshot = try await handler.loadVitalDBObservationSnapshot()
        return snapshot.observation
    }
}
