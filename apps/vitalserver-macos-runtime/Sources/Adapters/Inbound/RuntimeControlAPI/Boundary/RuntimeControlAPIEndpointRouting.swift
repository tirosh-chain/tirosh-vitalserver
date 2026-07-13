public extension RuntimeControlAPIEndpoint {
    var route: RuntimeControlAPIRoute {
        switch self {
        case .runtimeCapabilities:
            return .init(method: .get, path: "/runtime/capabilities", scope: .runtimeControl)
        case .platformCapabilities:
            return .init(method: .get, path: "/platform/capabilities", scope: .runtimeControl)
        case .platformState:
            return .init(method: .get, path: "/platform", scope: .runtimeControl)
        case .platformStateStream:
            return .init(method: .get, path: "/platform/stream", scope: .runtimeControl)
        case .operationState:
            return .init(method: .get, path: "/platform/operations", scope: .runtimeControl)
        case .platformWorkflow:
            return .init(method: .get, path: "/platform/workflows/current", scope: .platformAffordance)
        case .events:
            return .init(method: .get, path: "/runtime/events", scope: .runtimeControl)
        case .vitalDBObservation:
            return .init(method: .get, path: "/runtime/vitaldb/observations/latest", scope: .runtimeControl)
        case .vitalDBObservationStream:
            return .init(method: .get, path: "/runtime/vitaldb/observations/stream", scope: .runtimeControl)
        case .vitalDBRecorders:
            return .init(method: .get, path: "/runtime/vitaldb/recorders", scope: .runtimeControl)
        case .vitalDBRecorder:
            return .init(method: .get, path: "/runtime/vitaldb/recorders/{vrcode}", scope: .runtimeControl)
        case .vitalDBRecorderActivity:
            return .init(method: .get, path: "/runtime/vitaldb/recorders/{vrcode}/activity", scope: .runtimeControl)
        case .vitalDBBeds:
            return .init(method: .get, path: "/runtime/vitaldb/beds", scope: .runtimeControl)
        case .vitalDBBed:
            return .init(method: .get, path: "/runtime/vitaldb/beds/{bedID}", scope: .runtimeControl)
        case .vitalDBRelationships:
            return .init(method: .get, path: "/runtime/vitaldb/relationships", scope: .runtimeControl)
        case .hideVitalDBRecorders:
            return .init(method: .post, path: "/runtime/vitaldb/recorders/hide", scope: .runtimeControl)
        case .unhideVitalDBRecorders:
            return .init(method: .post, path: "/runtime/vitaldb/recorders/unhide", scope: .runtimeControl)
        case .deleteVitalDBRecorders:
            return .init(method: .post, path: "/runtime/vitaldb/recorders/delete", scope: .runtimeControl)
        case .hideVitalDBBeds:
            return .init(method: .post, path: "/runtime/vitaldb/beds/hide", scope: .runtimeControl)
        case .unhideVitalDBBeds:
            return .init(method: .post, path: "/runtime/vitaldb/beds/unhide", scope: .runtimeControl)
        case .deleteVitalDBBeds:
            return .init(method: .post, path: "/runtime/vitaldb/beds/delete", scope: .runtimeControl)
        case .health:
            return .init(method: .post, path: "/platform/health", scope: .runtimeControl)
        case .settings:
            return .init(method: .get, path: "/runtime/settings", scope: .runtimeControl)
        case .applySettings:
            return .init(method: .put, path: "/runtime/settings", scope: .runtimeControl)
        case .applyAdminPassword:
            return .init(method: .post, path: "/runtime/admin-password", scope: .runtimeControl)
        case .release:
            return .init(method: .get, path: "/platform/release", scope: .runtimeControl)
        case .installInfo:
            return .init(method: .get, path: "/platform/installation", scope: .runtimeControl)
        case .labScenarios:
            return .init(method: .get, path: "/runtime/lab/scenarios", scope: .runtimeControl)
        case .labVitalFiles:
            return .init(method: .get, path: "/runtime/lab/vital-files", scope: .runtimeControl)
        case .labBeds:
            return .init(method: .get, path: "/runtime/lab/beds", scope: .runtimeControl)
        case .createLabBeds:
            return .init(method: .post, path: "/runtime/lab/beds/create", scope: .runtimeControl)
        case .deleteLabBeds:
            return .init(method: .post, path: "/runtime/lab/beds/delete", scope: .runtimeControl)
        case .resetLabBeds:
            return .init(method: .post, path: "/runtime/lab/beds/reset", scope: .runtimeControl)
        case .labRecorders:
            return .init(method: .get, path: "/runtime/lab/recorders", scope: .runtimeControl)
        case .createLabRecorders:
            return .init(method: .post, path: "/runtime/lab/recorders/create", scope: .runtimeControl)
        case .deleteLabRecorders:
            return .init(method: .post, path: "/runtime/lab/recorders/delete", scope: .runtimeControl)
        case .resetLabRecorders:
            return .init(method: .post, path: "/runtime/lab/recorders/reset", scope: .runtimeControl)
        case .createLabSession:
            return .init(method: .post, path: "/runtime/lab/sessions", scope: .runtimeControl)
        case .labSessions:
            return .init(method: .get, path: "/runtime/lab/sessions", scope: .runtimeControl)
        case .labSession:
            return .init(method: .get, path: "/runtime/lab/sessions/{sessionId}", scope: .runtimeControl)
        case .startLabSession:
            return .init(method: .post, path: "/runtime/lab/sessions/{sessionId}/start", scope: .runtimeControl)
        case .stopLabSession:
            return .init(method: .post, path: "/runtime/lab/sessions/{sessionId}/stop", scope: .runtimeControl)
        case .startLabRecorder:
            return .init(method: .post, path: "/runtime/lab/sessions/{sessionId}/recorders/{recorderId}/start", scope: .runtimeControl)
        case .stopLabRecorder:
            return .init(method: .post, path: "/runtime/lab/sessions/{sessionId}/recorders/{recorderId}/stop", scope: .runtimeControl)
        case .replayLabVitalFile:
            return .init(method: .post, path: "/runtime/lab/vital-files/replay", scope: .runtimeControl)
        case .uploadLabVitalFile:
            return .init(method: .post, path: "/runtime/lab/vital-files/upload", scope: .runtimeControl)
        case .guestStackStatus:
            return .init(method: .get, path: "/runtime/stack", scope: .runtimeControl)
        case .guestServices:
            return .init(method: .get, path: "/runtime/services", scope: .runtimeControl)
        case .guestServiceStatus:
            return .init(method: .get, path: "/runtime/services/{service}/status", scope: .runtimeControl)
        case .guestServiceResource:
            return .init(method: .get, path: "/runtime/services/{service}/resource", scope: .runtimeControl)
        case .redisRelayStatus:
            return .init(method: .get, path: "/runtime/redis-relay/status", scope: .runtimeControl)
        case .redisRelaySettings:
            return .init(method: .get, path: "/runtime/redis-relay/settings", scope: .runtimeControl)
        case .applyRedisRelaySettings:
            return .init(method: .put, path: "/runtime/redis-relay/settings", scope: .runtimeControl)
        case .startGuestService:
            return .init(method: .post, path: "/runtime/services/{service}/start", scope: .runtimeControl)
        case .stopGuestService:
            return .init(method: .post, path: "/runtime/services/{service}/stop", scope: .runtimeControl)
        case .restartGuestService:
            return .init(method: .post, path: "/runtime/services/{service}/restart", scope: .runtimeControl)
        case .repairRuntimeServices:
            return .init(method: .post, path: "/platform/services/repair", scope: .runtimeControl)
        case .repairProxy:
            return .init(method: .post, path: "/platform/proxy/repair", scope: .runtimeControl)
        case .repairDatastore:
            return .init(method: .post, path: "/runtime/maintenance/datastore/repair", scope: .runtimeControl)
        case .repairVMDisk:
            return .init(method: .post, path: "/platform/runtime-provider/disk/repair", scope: .runtimeControl)
        case .createRedisBackup:
            return .init(method: .post, path: "/platform/backups/redis", scope: .runtimeControl)
        case .createRuntimeDataBackup:
            return .init(method: .post, path: "/platform/backups/runtime-data", scope: .runtimeControl)
        case .uninstall:
            return .init(method: .post, path: "/platform/uninstall", scope: .runtimeControl)
        case .backups:
            return .init(method: .get, path: "/platform/backups", scope: .platformAffordance)
        case .redisBackups:
            return .init(method: .get, path: "/platform/backups/redis", scope: .platformAffordance)
        case .runtimeDataBackups:
            return .init(method: .get, path: "/platform/backups/runtime-data", scope: .platformAffordance)
        case .restoreRedisBackup:
            return .init(method: .post, path: "/platform/backups/redis/restore", scope: .platformAffordance)
        case .restoreRuntimeDataBackup:
            return .init(method: .post, path: "/platform/backups/runtime-data/restore", scope: .platformAffordance)
        case .logText:
            return .init(method: .post, path: "/platform/logs/read", scope: .platformAffordance)
        case .logStream:
            return .init(method: .get, path: "/platform/logs/stream", scope: .platformAffordance)
        case .updateBundleSummary:
            return .init(method: .post, path: "/platform/update-bundles/summary", scope: .platformAffordance)
        case .verifyUpdateBundle:
            return .init(method: .post, path: "/platform/update-bundles/verify", scope: .platformAffordance)
        case .applyUpdateBundle:
            return .init(method: .post, path: "/platform/update-bundles/apply", scope: .platformAffordance)
        case .rollbackRelease:
            return .init(method: .post, path: "/platform/releases/rollback", scope: .platformAffordance)
        case .rollbackBackup:
            return .init(method: .post, path: "/platform/backups/rollback", scope: .platformAffordance)
        case .deleteBackup:
            return .init(method: .delete, path: "/platform/backups", scope: .platformAffordance)
        case .deleteUpdateBackup:
            return .init(method: .delete, path: "/platform/backups/update", scope: .platformAffordance)
        case .deleteRuntimeDataBackup:
            return .init(method: .delete, path: "/platform/backups/runtime-data", scope: .platformAffordance)
        case .exportLogs:
            return .init(method: .post, path: "/platform/logs/export", scope: .platformAffordance)
        case .createSupportExport:
            return .init(method: .post, path: "/platform/support-exports", scope: .platformAffordance)
        case .acquireOperationLease:
            return .init(method: .post, path: "/platform/operations/lease/acquire", scope: .platformAffordance)
        case .heartbeatOperationLease:
            return .init(method: .post, path: "/platform/operations/lease/heartbeat", scope: .platformAffordance)
        case .releaseOperationLease:
            return .init(method: .post, path: "/platform/operations/lease/release", scope: .platformAffordance)
        case .guestAddress:
            return .init(method: .get, path: "/platform/runtime-endpoint", scope: .platformAffordance)
        case .putGuestAddress:
            return .init(method: .put, path: "/platform/runtime-endpoint", scope: .platformAffordance)
        case .vmLifecycle:
            return .init(method: .get, path: "/platform/runtime-provider", scope: .platformAffordance)
        case .putVMLifecycle:
            return .init(method: .put, path: "/platform/runtime-provider", scope: .platformAffordance)
        case .startRuntimeProvider:
            return .init(method: .post, path: "/platform/runtime-provider/start", scope: .platformAffordance)
        case .stopRuntimeProvider:
            return .init(method: .post, path: "/platform/runtime-provider/stop", scope: .platformAffordance)
        case .restartRuntimeProvider:
            return .init(method: .post, path: "/platform/runtime-provider/restart", scope: .platformAffordance)
        }
    }

    static func matching(method: RuntimeControlHTTPMethod, path: String) -> RuntimeControlAPIEndpoint? {
        allCases.first { endpoint in
            endpoint.route.method == method && endpoint.matches(path: normalizedPath(path))
        }
    }

    static func matching(path: String) -> RuntimeControlAPIEndpoint? {
        allCases.first { endpoint in
            endpoint.matches(path: normalizedPath(path))
        }
    }

    static func normalizedPathForRequest(_ path: String) -> String {
        normalizedPath(path)
    }

    private func matches(path: String) -> Bool {
        switch self {
        case .vitalDBRecorderActivity:
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            return components.count == 5
                && components[0] == "runtime"
                && components[1] == "vitaldb"
                && components[2] == "recorders"
                && !components[3].isEmpty
                && components[4] == "activity"
        case .vitalDBRecorder:
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            return components.count == 4
                && components[0] == "runtime"
                && components[1] == "vitaldb"
                && components[2] == "recorders"
                && !components[3].isEmpty
        case .vitalDBBed:
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            return components.count == 4
                && components[0] == "runtime"
                && components[1] == "vitaldb"
                && components[2] == "beds"
                && !components[3].isEmpty
        case .guestServiceStatus, .guestServiceResource,
             .startGuestService, .stopGuestService, .restartGuestService:
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            guard components.count == 4,
                  components[0] == "runtime",
                  components[1] == "services",
                  !components[2].isEmpty else {
                return false
            }
            let expectedAction: Substring
            switch self {
            case .guestServiceStatus:
                expectedAction = "status"
            case .guestServiceResource:
                expectedAction = "resource"
            case .startGuestService:
                expectedAction = "start"
            case .stopGuestService:
                expectedAction = "stop"
            case .restartGuestService:
                expectedAction = "restart"
            default:
                return false
            }
            return components[3] == expectedAction
        case .labSession:
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            return components.count == 4
                && components[0] == "runtime"
                && components[1] == "lab"
                && components[2] == "sessions"
                && !components[3].isEmpty
        case .startLabSession:
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            return components.count == 5
                && components[0] == "runtime"
                && components[1] == "lab"
                && components[2] == "sessions"
                && !components[3].isEmpty
                && components[4] == "start"
        case .stopLabSession:
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            return components.count == 5
                && components[0] == "runtime"
                && components[1] == "lab"
                && components[2] == "sessions"
                && !components[3].isEmpty
                && components[4] == "stop"
        case .startLabRecorder, .stopLabRecorder:
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            let expectedAction: Substring = self == .startLabRecorder ? "start" : "stop"
            return components.count == 7
                && components[0] == "runtime"
                && components[1] == "lab"
                && components[2] == "sessions"
                && !components[3].isEmpty
                && components[4] == "recorders"
                && !components[5].isEmpty
                && components[6] == expectedAction
        default:
            return route.path == path
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        guard let queryIndex = path.firstIndex(of: "?") else {
            return path
        }
        return String(path[..<queryIndex])
    }
}
