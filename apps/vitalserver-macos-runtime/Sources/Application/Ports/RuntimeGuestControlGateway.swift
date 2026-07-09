import Contracts

public protocol RuntimeGuestControlGateway {
    func ready() throws -> RuntimeGuestControlReadiness
    func capabilities() throws -> RuntimeGuestControlCapabilities
    func listServices() throws -> RuntimeGuestControlServiceList
    func stackStatus() throws -> RuntimeGuestControlStackStatus
    func serviceStatus(_ service: String) throws -> RuntimeGuestControlServiceStatus
    func serviceResource(_ service: String) throws -> RuntimeGuestServiceResource
    func startService(_ service: String) throws -> RuntimeGuestControlServiceOperation
    func stopService(_ service: String) throws -> RuntimeGuestControlServiceOperation
    func restartService(_ service: String) throws -> RuntimeGuestControlServiceOperation
    func reconcileServices() throws -> RuntimeGuestControlServiceOperation
    func createRedisBackup() throws -> RuntimeGuestControlServiceOperation
    func restoreRedisBackup(archive: String) throws -> RuntimeGuestControlServiceOperation
    func repairDatastore() throws -> RuntimeGuestControlServiceOperation
    func activateUpdate(requestId: String, version: String) throws -> RuntimeGuestControlServiceOperation
    func prepareUpdateShutdown(requestId: String, version: String) throws -> RuntimeGuestControlServiceOperation
    func requestGuestPoweroff() throws -> RuntimeGuestControlServiceOperation
    func operation(_ operationId: String) throws -> RuntimeGuestControlServiceOperation
    func latestVitalDBObservation() throws -> RuntimeGuestControlVitalDBObservationRead
    func vitalDBRecorders() throws -> RuntimeGuestControlVitalDBRecorderRead
    func hideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) throws -> RuntimeGuestControlVitalDBRecorderRead
    func unhideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) throws -> RuntimeGuestControlVitalDBRecorderRead
    func deleteVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) throws -> RuntimeGuestControlVitalDBRecorderRead
    func vitalDBRecorderActivity(_ vrcode: String) throws -> RuntimeGuestControlVitalDBRecorderActivityRead
    func vitalDBBeds() throws -> RuntimeGuestControlVitalDBBedRead
    func hideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) throws -> RuntimeGuestControlVitalDBBedRead
    func unhideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) throws -> RuntimeGuestControlVitalDBBedRead
    func deleteVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) throws -> RuntimeGuestControlVitalDBBedRead
    func vitalDBRelationships() throws -> RuntimeGuestControlVitalDBRelationshipRead
    func recorderIngressStatus() throws -> RuntimeRecorderIngressStatusReadResult
    func redisRelayStatus() throws -> RuntimeRedisRelayStatusReadResult
}

public enum RuntimeGuestControlGatewayCapabilityError: Error, CustomStringConvertible {
    case unavailable(String)

    public var description: String {
        switch self {
        case .unavailable(let capability):
            return "guest control gateway capability is unavailable: \(capability)"
        }
    }
}

public extension RuntimeGuestControlGateway {
    func ready() throws -> RuntimeGuestControlReadiness {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("ready")
    }

    func capabilities() throws -> RuntimeGuestControlCapabilities {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("capabilities")
    }

    func serviceResource(_: String) throws -> RuntimeGuestServiceResource {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("guest-service-resource")
    }

    func vitalDBRecorders() throws -> RuntimeGuestControlVitalDBRecorderRead {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("vitaldb-recorders")
    }

    func hideVitalDBRecorders(_: RuntimeVitalDBRecorderVisibilityRequest) throws -> RuntimeGuestControlVitalDBRecorderRead {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("vitaldb-recorders-hide")
    }

    func unhideVitalDBRecorders(_: RuntimeVitalDBRecorderVisibilityRequest) throws -> RuntimeGuestControlVitalDBRecorderRead {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("vitaldb-recorders-unhide")
    }

    func deleteVitalDBRecorders(_: RuntimeVitalDBRecorderVisibilityRequest) throws -> RuntimeGuestControlVitalDBRecorderRead {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("vitaldb-recorders-delete")
    }

    func vitalDBRecorderActivity(_: String) throws -> RuntimeGuestControlVitalDBRecorderActivityRead {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("vitaldb-recorder-activity")
    }

    func vitalDBBeds() throws -> RuntimeGuestControlVitalDBBedRead {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("vitaldb-beds")
    }

    func hideVitalDBBeds(_: RuntimeVitalDBBedVisibilityRequest) throws -> RuntimeGuestControlVitalDBBedRead {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("vitaldb-beds-hide")
    }

    func unhideVitalDBBeds(_: RuntimeVitalDBBedVisibilityRequest) throws -> RuntimeGuestControlVitalDBBedRead {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("vitaldb-beds-unhide")
    }

    func deleteVitalDBBeds(_: RuntimeVitalDBBedVisibilityRequest) throws -> RuntimeGuestControlVitalDBBedRead {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("vitaldb-beds-delete")
    }

    func vitalDBRelationships() throws -> RuntimeGuestControlVitalDBRelationshipRead {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("vitaldb-relationships")
    }

    func recorderIngressStatus() throws -> RuntimeRecorderIngressStatusReadResult {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("recorder-ingress-status")
    }

    func redisRelayStatus() throws -> RuntimeRedisRelayStatusReadResult {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("redis-relay-status")
    }

    func createRedisBackup() throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("redis-backup")
    }

    func restoreRedisBackup(archive: String) throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("redis-restore")
    }

    func repairDatastore() throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("datastore-repair")
    }

    func activateUpdate(requestId _: String, version _: String) throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("update-activation")
    }

    func prepareUpdateShutdown(requestId _: String, version _: String) throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("update-shutdown")
    }

    func requestGuestPoweroff() throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("guest-poweroff")
    }
}
