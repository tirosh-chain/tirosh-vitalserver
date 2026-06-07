public extension RuntimeControlAPIEndpoint {
    var streamCapability: RuntimeControlAPIStreamCapability {
        switch self {
        case .overviewStream,
             .statusStream,
             .eventStream,
             .vitalDBObservationStream,
             .logStream:
            return .supported
        case .capabilities,
             .overview,
             .status,
             .events,
             .vitalDBObservation,
             .vitalDBRecorders,
             .vitalDBRecorder,
             .vitalDBBeds,
             .vitalDBBed,
             .vitalDBRelationships,
             .health,
             .settings,
             .applySettings,
             .release,
             .installInfo,
             .startServices,
             .stopServices,
             .repairRuntimeServices,
             .repairProxy,
             .repairDatastore,
             .repairVMDisk,
             .createRedisBackup,
             .uninstall,
             .backups,
             .redisBackups,
             .restoreRedisBackup,
             .logText,
             .updateBundleSummary,
             .verifyUpdateBundle,
             .applyUpdateBundle,
             .rollbackBackup,
             .deleteBackup,
             .exportLogs:
            return .unsupported
        }
    }

    var clientAccess: RuntimeControlAPIClientAccess {
        switch self {
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
             .installInfo:
            return .browserSafe
        case .exportLogs:
            return .nativeShellOnly
        case .applySettings,
             .startServices,
             .stopServices,
             .repairRuntimeServices,
             .repairProxy,
             .repairDatastore,
             .repairVMDisk,
             .createRedisBackup,
             .uninstall,
             .backups,
             .redisBackups,
             .restoreRedisBackup,
             .logText,
             .logStream,
             .updateBundleSummary,
             .verifyUpdateBundle,
             .applyUpdateBundle,
             .rollbackBackup,
             .deleteBackup:
            return .localServerMediated
        }
    }
}
