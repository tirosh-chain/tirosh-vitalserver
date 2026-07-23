import Contracts
import Foundation

public protocol RuntimeGuestControlGateway {
    func ready() throws -> RuntimeGuestControlReadiness
    func capabilities() throws -> RuntimeGuestControlCapabilities
    func runtimeSettings() throws -> RuntimeProductSettingsRead
    func applyRuntimeSettings(_ settings: GuestRuntimeSettingsDocument) throws -> RuntimeGuestControlServiceOperation
    func applyAdminPassword(_ password: String) throws -> RuntimeGuestControlServiceOperation
    func redisRelaySettings() throws -> RuntimeRedisRelaySettingsRead
    func applyRedisRelaySettings(_ settings: RuntimeRedisRelaySettingsApplyRequest) throws -> RuntimeGuestControlServiceOperation
    func runtimeEvents(query: RuntimeOperationEventQuery) throws -> RuntimeOperationEventHistory
    func listServices() throws -> RuntimeGuestControlServiceList
    func stackStatus() throws -> RuntimeGuestControlStackStatus
    func serviceStatus(_ service: String) throws -> RuntimeGuestControlServiceStatus
    func serviceResource(_ service: String) throws -> RuntimeGuestServiceResource
    func startService(_ service: String) throws -> RuntimeGuestControlServiceOperation
    func stopService(_ service: String) throws -> RuntimeGuestControlServiceOperation
    func restartService(_ service: String) throws -> RuntimeGuestControlServiceOperation
    func reconcileServices() throws -> RuntimeGuestControlServiceOperation
    func createPostgresBackup() throws -> RuntimeGuestControlServiceOperation
    func restorePostgresBackup(
        archive: String,
        restartRuntime: Bool
    ) throws -> RuntimeGuestControlServiceOperation
    func createRedisBackup() throws -> RuntimeGuestControlServiceOperation
    func restoreRedisBackup(archive: String) throws -> RuntimeGuestControlServiceOperation
    func repairDatastore() throws -> RuntimeGuestControlServiceOperation
    func activateUpdate(requestId: String, version: String) throws -> RuntimeGuestControlServiceOperation
    func prepareUpdateShutdown(requestId: String, version: String) throws -> RuntimeGuestControlServiceOperation
    func requestGuestPoweroff() throws -> RuntimeGuestControlServiceOperation
    func operation(_ operationId: String) throws -> RuntimeGuestControlServiceOperation
    func latestVitalDBObservation() throws -> RuntimeGuestControlVitalDBObservationRead
    func vitalDBRecorderActivity(_ vrcode: String) throws -> RuntimeGuestControlVitalDBRecorderActivityRead
    func vitalDBRecorderVitalFiles(_ vrcode: String) throws -> RuntimeVitalRecorderVitalFileHistory
    func vitalDBRelationships() throws -> RuntimeGuestControlVitalDBRelationshipRead
    func vitalDBRelationshipsAsync() async throws -> RuntimeGuestControlVitalDBRelationshipRead
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

/// The Guest Controller rejected an explicitly forwarded operation-ledger query.
///
/// This remains an application-boundary error so inbound HTTP adapters can
/// preserve the caller's bad-request meaning without depending on an outbound
/// transport error type.
public struct RuntimeGuestOperationEventQueryRejectedError: LocalizedError, Equatable, Sendable {
    public let detail: String

    public init(detail: String) {
        self.detail = detail
    }

    public var errorDescription: String? {
        detail
    }
}

/// The Guest Controller could not read its operation-event ledger.
///
/// This application-boundary error retains the Guest dependency failure as a
/// public service-unavailable result without exposing an outbound HTTP error to
/// the inbound adapter.
public struct RuntimeGuestOperationEventHistoryUnavailableError: LocalizedError, Equatable, Sendable {
    public let detail: String

    public init(detail: String) {
        self.detail = detail
    }

    public var errorDescription: String? {
        detail
    }
}

public extension RuntimeGuestControlGateway {
    func ready() throws -> RuntimeGuestControlReadiness {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("ready")
    }

    func capabilities() throws -> RuntimeGuestControlCapabilities {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("capabilities")
    }

    func runtimeSettings() throws -> RuntimeProductSettingsRead {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("settings:get")
    }

    func applyRuntimeSettings(_: GuestRuntimeSettingsDocument) throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("settings:apply")
    }

    func applyAdminPassword(_: String) throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("admin-password:apply")
    }

    func redisRelaySettings() throws -> RuntimeRedisRelaySettingsRead {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("redis-relay:settings:get")
    }

    func applyRedisRelaySettings(_: RuntimeRedisRelaySettingsApplyRequest) throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("redis-relay:settings:apply")
    }

    func runtimeEvents(query _: RuntimeOperationEventQuery) throws -> RuntimeOperationEventHistory {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("events:get")
    }

    func serviceResource(_: String) throws -> RuntimeGuestServiceResource {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("guest-service-resource")
    }

    func vitalDBRecorderActivity(_: String) throws -> RuntimeGuestControlVitalDBRecorderActivityRead {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("vitaldb-recorder-activity")
    }

    func vitalDBRecorderVitalFiles(_: String) throws -> RuntimeVitalRecorderVitalFileHistory {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("vitaldb-recorder-vital-files")
    }

    func vitalDBRelationships() throws -> RuntimeGuestControlVitalDBRelationshipRead {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("vitaldb-relationships")
    }

    func vitalDBRelationshipsAsync() async throws -> RuntimeGuestControlVitalDBRelationshipRead {
        try vitalDBRelationships()
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

    func createPostgresBackup() throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("postgres-backup")
    }

    func restorePostgresBackup(
        archive _: String,
        restartRuntime _: Bool
    ) throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeGuestControlGatewayCapabilityError.unavailable("postgres-restore")
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
