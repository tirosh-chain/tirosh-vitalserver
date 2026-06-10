public extension RuntimeControlAPIEndpoint {
    var route: RuntimeControlAPIRoute {
        switch self {
        case .capabilities:
            return .init(method: .get, path: "/runtime/capabilities", scope: .runtimeControl)
        case .overview:
            return .init(method: .get, path: "/runtime/overview", scope: .runtimeControl)
        case .overviewStream:
            return .init(method: .get, path: "/runtime/overview/stream", scope: .runtimeControl)
        case .status:
            return .init(method: .get, path: "/runtime/status", scope: .runtimeControl)
        case .statusStream:
            return .init(method: .get, path: "/runtime/status/stream", scope: .runtimeControl)
        case .events:
            return .init(method: .get, path: "/runtime/events", scope: .runtimeControl)
        case .eventStream:
            return .init(method: .get, path: "/runtime/events/stream", scope: .runtimeControl)
        case .vitalDBObservation:
            return .init(method: .get, path: "/vitaldb/observations/latest", scope: .runtimeControl)
        case .vitalDBObservationStream:
            return .init(method: .get, path: "/vitaldb/observations/stream", scope: .runtimeControl)
        case .vitalDBRecorders:
            return .init(method: .get, path: "/vitaldb/recorders", scope: .runtimeControl)
        case .vitalDBRecorder:
            return .init(method: .get, path: "/vitaldb/recorders/{vrcode}", scope: .runtimeControl)
        case .vitalDBRecorderActivity:
            return .init(method: .get, path: "/vitaldb/recorders/{vrcode}/activity", scope: .runtimeControl)
        case .vitalDBBeds:
            return .init(method: .get, path: "/vitaldb/beds", scope: .runtimeControl)
        case .vitalDBBed:
            return .init(method: .get, path: "/vitaldb/beds/{bedID}", scope: .runtimeControl)
        case .vitalDBRelationships:
            return .init(method: .get, path: "/vitaldb/relationships", scope: .runtimeControl)
        case .health:
            return .init(method: .post, path: "/runtime/health", scope: .runtimeControl)
        case .settings:
            return .init(method: .get, path: "/runtime/settings", scope: .runtimeControl)
        case .applySettings:
            return .init(method: .put, path: "/runtime/settings", scope: .runtimeControl)
        case .release:
            return .init(method: .get, path: "/runtime/release", scope: .runtimeControl)
        case .installInfo:
            return .init(method: .get, path: "/runtime/install", scope: .runtimeControl)
        case .startServices:
            return .init(method: .post, path: "/runtime/services/start", scope: .runtimeControl)
        case .stopServices:
            return .init(method: .post, path: "/runtime/services/stop", scope: .runtimeControl)
        case .repairRuntimeServices:
            return .init(method: .post, path: "/runtime/services/repair-runtime", scope: .runtimeControl)
        case .repairProxy:
            return .init(method: .post, path: "/runtime/services/repair-proxy", scope: .runtimeControl)
        case .repairDatastore:
            return .init(method: .post, path: "/runtime/services/repair-datastore", scope: .runtimeControl)
        case .repairVMDisk:
            return .init(method: .post, path: "/runtime/services/repair-vm-disk", scope: .runtimeControl)
        case .createRedisBackup:
            return .init(method: .post, path: "/runtime/redis/backups", scope: .runtimeControl)
        case .createRuntimeDataBackup:
            return .init(method: .post, path: "/runtime/data/backups", scope: .runtimeControl)
        case .uninstall:
            return .init(method: .post, path: "/runtime/uninstall", scope: .runtimeControl)
        case .backups:
            return .init(method: .get, path: "/host/backups", scope: .hostAffordance)
        case .redisBackups:
            return .init(method: .get, path: "/host/backups/redis", scope: .hostAffordance)
        case .runtimeDataBackups:
            return .init(method: .get, path: "/host/backups/runtime-data", scope: .hostAffordance)
        case .restoreRedisBackup:
            return .init(method: .post, path: "/host/backups/redis/restore", scope: .hostAffordance)
        case .restoreRuntimeDataBackup:
            return .init(method: .post, path: "/host/backups/runtime-data/restore", scope: .hostAffordance)
        case .logText:
            return .init(method: .post, path: "/host/logs/read", scope: .hostAffordance)
        case .logStream:
            return .init(method: .get, path: "/host/logs/stream", scope: .hostAffordance)
        case .updateBundleSummary:
            return .init(method: .post, path: "/host/update-bundles/summary", scope: .hostAffordance)
        case .verifyUpdateBundle:
            return .init(method: .post, path: "/host/update-bundles/verify", scope: .hostAffordance)
        case .applyUpdateBundle:
            return .init(method: .post, path: "/host/update-bundles/apply", scope: .hostAffordance)
        case .rollbackBackup:
            return .init(method: .post, path: "/host/backups/rollback", scope: .hostAffordance)
        case .deleteBackup:
            return .init(method: .delete, path: "/host/backups", scope: .hostAffordance)
        case .exportLogs:
            return .init(method: .post, path: "/host/logs/export", scope: .hostAffordance)
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
            return components.count == 4
                && components[0] == "vitaldb"
                && components[1] == "recorders"
                && !components[2].isEmpty
                && components[3] == "activity"
        case .vitalDBRecorder:
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            return components.count == 3
                && components[0] == "vitaldb"
                && components[1] == "recorders"
                && !components[2].isEmpty
        case .vitalDBBed:
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            return components.count == 3
                && components[0] == "vitaldb"
                && components[1] == "beds"
                && !components[2].isEmpty
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
