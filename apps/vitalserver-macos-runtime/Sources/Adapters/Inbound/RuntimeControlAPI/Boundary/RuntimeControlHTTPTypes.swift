import Contracts
import CryptoKit
import Foundation
import RuntimeControl

public enum RuntimeControlHTTPStatus: Int, Codable, Equatable, Sendable {
    case ok = 200
    case accepted = 202
    case noContent = 204
    case badRequest = 400
    case unauthorized = 401
    case notFound = 404
    case methodNotAllowed = 405
    case serviceUnavailable = 503
    case notImplemented = 501
    case internalServerError = 500
}

public struct RuntimeControlHTTPRequest: Equatable, Sendable {
    public let method: RuntimeControlHTTPMethod
    public let path: String
    public let headers: [String: String]
    public let body: Data?

    public init(
        method: RuntimeControlHTTPMethod,
        path: String,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

public struct RuntimeControlHTTPResponse: Equatable, Sendable {
    public let status: RuntimeControlHTTPStatus
    public let headers: [String: String]
    public let body: Data?

    public init(
        status: RuntimeControlHTTPStatus,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public struct RuntimeControlHTTPStreamResponse: Sendable {
    public let status: RuntimeControlHTTPStatus
    public let headers: [String: String]
    public let events: AsyncThrowingStream<RuntimeControlServerSentEvent, Error>

    public init(
        status: RuntimeControlHTTPStatus,
        headers: [String: String],
        events: AsyncThrowingStream<RuntimeControlServerSentEvent, Error>
    ) {
        self.status = status
        self.headers = headers
        self.events = events
    }
}

public enum RuntimeControlHTTPRouteResult: Sendable {
    case response(RuntimeControlHTTPResponse)
    case stream(RuntimeControlHTTPStreamResponse)
}

public struct RuntimeControlAPIStreamConfiguration: Equatable, Sendable {
    public let pollIntervalNanoseconds: UInt64
    public let heartbeatIntervalNanoseconds: UInt64

    public init(
        pollIntervalNanoseconds: UInt64 = 1_000_000_000,
        heartbeatIntervalNanoseconds: UInt64 = 15_000_000_000
    ) {
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.heartbeatIntervalNanoseconds = heartbeatIntervalNanoseconds
    }
}

@MainActor
public protocol RuntimeControlAPIReadHandler {
    func loadPlatformCapabilities() async throws -> PlatformCapabilities
    func loadRuntimeCapabilities() async throws -> RuntimeCapabilities
    func loadPlatformState() async throws -> PlatformState
    func loadOperationState() async throws -> PlatformOperationState
    func loadPlatformWorkflow() async throws -> PlatformWorkflowResource
    func loadRuntimeOperationEvents(query: RuntimeEventQuery) async throws -> RuntimeOperationEventHistory
    func loadVitalDBObservationSnapshot() async throws -> RuntimeVitalDBObservationSnapshot
    func loadVitalDBRecorders() async throws -> RuntimeVitalRecorderHistory
    func loadVitalDBBeds() async throws -> RuntimeVitalBedHistory
    func loadVitalDBRecorderActivityWindow(query: RuntimeVitalRecorderActivityWindowQuery) async throws -> RuntimeVitalRecorderActivityWindow
    func loadVitalDBRelationships() async throws -> RuntimeVitalRelationshipHistory
    func loadHealthStatus() async throws -> PlatformState
    func loadRuntimeProductSettings() async throws -> RuntimeProductSettingsRead
    func loadReleaseInfo() async throws -> RuntimeReleaseInfo
    func loadInstallInfo() async throws -> RuntimeInstallInfo
    func loadLabScenarios() async throws -> RuntimeLabScenarioList
    func loadLabVitalFiles() async throws -> RuntimeLabVitalFileList
    func loadLabBeds() async throws -> RuntimeLabBedList
    func loadLabRecorders() async throws -> RuntimeLabRecorderList
    func createLabBeds(_ request: RuntimeLabBedCreateRequest) async throws -> RuntimeLabBedList
    func deleteLabBeds(_ request: RuntimeLabBedDeleteRequest) async throws -> RuntimeLabBedList
    func resetLabBeds() async throws -> RuntimeLabBedList
    func createLabRecorders(_ request: RuntimeLabRecorderCreateRequest) async throws -> RuntimeLabRecorderList
    func deleteLabRecorders(_ request: RuntimeLabRecorderDeleteRequest) async throws -> RuntimeLabRecorderList
    func resetLabRecorders() async throws -> RuntimeLabRecorderList
    func hideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory
    func unhideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory
    func deleteVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory
    func hideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory
    func unhideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory
    func deleteVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory
    func createLabSession(_ request: RuntimeLabSessionCreateRequest) async throws -> RuntimeLabSessionResponse
    func loadLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse
    func startLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse
    func stopLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse
    func replayLabVitalFile(_ request: RuntimeLabVitalFileReplayRequest) async throws -> RuntimeLabSessionResponse
    func uploadLabVitalFile(_ request: RuntimeLabVitalFileUploadRequest) async throws -> RuntimeLabVitalFileUploadResponse
    func guestStackStatus() async throws -> RuntimeGuestControlStackStatus
    func listGuestServices() async throws -> RuntimeGuestControlServiceList
    func guestServiceStatus(_ service: String) async throws -> RuntimeGuestControlServiceStatus
    func guestServiceResource(_ service: String) async throws -> RuntimeGuestServiceResource
    func loadRedisRelayStatus() async throws -> RuntimeRedisRelayStatusReadResult
    func loadRuntimeRedisRelaySettings() async throws -> RuntimeRedisRelaySettingsRead
    func loadLogText(request: RuntimeLogTextRequest) async throws -> RuntimeLogTextResponse
    func loadBackups() async throws -> [RuntimeBackup]
    func loadRedisBackups() async throws -> [RuntimeBackup]
    func loadRuntimeDataBackups() async throws -> [RuntimeBackup]
    func applyRuntimeProductSettings(_ settings: GuestRuntimeSettingsDocument) async throws -> RuntimeGuestControlServiceOperation
    func applyRuntimeAdminPassword(_ password: String) async throws -> RuntimeGuestControlServiceOperation
    func applyRuntimeRedisRelaySettings(_ settings: RuntimeRedisRelaySettingsApplyRequest) async throws -> RuntimeGuestControlServiceOperation
    func startGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation
    func stopGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation
    func restartGuestService(_ request: RuntimeGuestServiceRestartRequest) async throws -> RuntimeGuestControlServiceOperation
    func repairRuntimeServices() async throws -> RuntimeControlCommandResponse
    func repairProxy() async throws -> RuntimeControlCommandResponse
    func repairDatastore() async throws -> RuntimeControlCommandResponse
    func repairVMDisk() async throws -> RuntimeControlCommandResponse
    func createRedisBackup() async throws -> RuntimeControlCommandResponse
    func createRuntimeDataBackup() async throws -> RuntimeControlCommandResponse
    func updateBundleSummary(bundle: RuntimeControlFileReference) async throws -> RuntimeUpdateBundleSummaryResponse
    func verifyUpdateBundle(bundle: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse
    func applyUpdateBundle(bundle: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse
    func rollbackRelease() async throws -> PlatformWorkflowOperation
    func rollbackBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse
    func restoreRedisBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse
    func restoreRuntimeDataBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse
    func deleteBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse
    func exportLogs(destination: RuntimeControlFileReference) async throws -> RuntimeLogExportResult
    func createPlatformSupportExport() async throws -> PlatformWorkflowOperation
    func acquireOperationLease(_ request: RuntimeOperationLeaseAcquireRequest) async throws -> RuntimeOperationLeaseMutationResponse
    func heartbeatOperationLease(_ request: RuntimeOperationLeaseHeartbeatRequest) async throws -> RuntimeOperationLeaseMutationResponse
    func releaseOperationLease(_ request: RuntimeOperationLeaseReleaseRequest) async throws -> RuntimeOperationLeaseMutationResponse
    func loadGuestAddressResource() async throws -> RuntimeGuestAddressResourceState
    func putGuestAddressResource(_ request: RuntimeGuestAddressPutRequest) async throws -> RuntimeGuestAddressResourceState
    func loadVMLifecycleResource() async throws -> RuntimeVMLifecycleResourceState
    func putVMLifecycleResource(_ request: RuntimeVMLifecyclePutRequest) async throws -> RuntimeVMLifecycleResourceState
    func controlRuntimeProvider(_ action: RuntimeProviderCommandAction) async throws -> RuntimeProviderCommandResponse
    func uninstallRuntime(mode: RuntimeUninstallMode) async throws -> RuntimeControlCommandResponse
}

@MainActor
public func createManagedPlatformSupportExport(
    in directory: URL,
    operationId suppliedOperationId: String? = nil,
    startedAt suppliedStartedAt: String? = nil,
    export: (URL) async throws -> RuntimeLogExportResult
) async -> PlatformWorkflowOperation {
    let operationId = suppliedOperationId
        ?? "workflow-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let timestamp = suppliedStartedAt ?? ISO8601DateFormatter().string(from: Date())
    let destination = directory.appendingPathComponent("vitalserver-support-\(operationId).zip")
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = try await export(destination)
        let handle = try FileHandle(forReadingFrom: destination)
        defer { try? handle.close() }
        var hasher = SHA256()
        var sizeBytes: Int64 = 0
        while let block = try handle.read(upToCount: 1024 * 1024), !block.isEmpty {
            hasher.update(data: block)
            sizeBytes += Int64(block.count)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return PlatformWorkflowOperation(
            operationId: operationId,
            kind: .supportExport,
            state: .completed,
            startedAt: timestamp,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            release: nil,
            artifact: PlatformWorkflowArtifact(path: destination.path, sha256: digest, sizeBytes: sizeBytes),
            failure: nil
        )
    } catch {
        return PlatformWorkflowOperation(
            operationId: operationId,
            kind: .supportExport,
            state: .failed,
            startedAt: timestamp,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            release: nil,
            artifact: nil,
            failure: PlatformWorkflowFailure(kind: "supportExportFailed", message: error.localizedDescription)
        )
    }
}

public extension RuntimeControlAPIReadHandler {
    func createPlatformSupportExport() async throws -> PlatformWorkflowOperation {
        throw RuntimeControlClientUnsupportedError.unavailable("platform-support-export")
    }

    func rollbackRelease() async throws -> PlatformWorkflowOperation {
        throw RuntimeControlClientUnsupportedError.unavailable("release:rollback")
    }

    func loadPlatformWorkflow() async throws -> PlatformWorkflowResource {
        PlatformWorkflowResource(
            state: .unavailable,
            operation: nil,
            readError: "Platform workflow owner is unavailable on this adapter."
        )
    }
    func loadRuntimeOperationEvents(
        query _: RuntimeEventQuery
    ) async throws -> RuntimeOperationEventHistory {
        throw RuntimeControlClientUnsupportedError.unavailable("events:get")
    }

    func loadRuntimeProductSettings() async throws -> RuntimeProductSettingsRead {
        throw RuntimeControlClientUnsupportedError.unavailable("settings:get")
    }

    func applyRuntimeProductSettings(
        _: GuestRuntimeSettingsDocument
    ) async throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeControlClientUnsupportedError.unavailable("settings:apply")
    }

    func applyRuntimeAdminPassword(_: String) async throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeControlClientUnsupportedError.unavailable("admin-password:apply")
    }

    func loadRuntimeRedisRelaySettings() async throws -> RuntimeRedisRelaySettingsRead {
        throw RuntimeControlClientUnsupportedError.unavailable("redis-relay:settings:get")
    }

    func applyRuntimeRedisRelaySettings(_: RuntimeRedisRelaySettingsApplyRequest) async throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeControlClientUnsupportedError.unavailable("redis-relay:settings:apply")
    }

    func loadGuestAddressResource() async throws -> RuntimeGuestAddressResourceState {
        .unavailable(readError: "Guest address owner is unavailable")
    }

    func putGuestAddressResource(_ request: RuntimeGuestAddressPutRequest) async throws -> RuntimeGuestAddressResourceState {
        throw RuntimeControlClientUnsupportedError.unavailable("guest-address-put")
    }

    func loadVMLifecycleResource() async throws -> RuntimeVMLifecycleResourceState {
        .unavailable(readError: "VM lifecycle owner is unavailable")
    }

    func loadRedisRelayStatus() async throws -> RuntimeRedisRelayStatusReadResult {
        RuntimeRedisRelayStatusReadResult(
            readState: .readFailed,
            document: nil,
            readError: "Redis Relay status owner is unavailable"
        )
    }

    func putVMLifecycleResource(_ request: RuntimeVMLifecyclePutRequest) async throws -> RuntimeVMLifecycleResourceState {
        throw RuntimeControlClientUnsupportedError.unavailable("vm-lifecycle-put")
    }

    func controlRuntimeProvider(_ action: RuntimeProviderCommandAction) async throws -> RuntimeProviderCommandResponse {
        throw RuntimeControlClientUnsupportedError.unavailable("runtime-provider-\(action.rawValue)")
    }

    func loadLabScenarios() async throws -> RuntimeLabScenarioList {
        RuntimeLabScenarioList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func loadLabVitalFiles() async throws -> RuntimeLabVitalFileList {
        RuntimeLabVitalFileList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func loadLabBeds() async throws -> RuntimeLabBedList {
        RuntimeLabBedList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func loadLabRecorders() async throws -> RuntimeLabRecorderList {
        RuntimeLabRecorderList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func createLabBeds(_ request: RuntimeLabBedCreateRequest) async throws -> RuntimeLabBedList {
        RuntimeLabBedList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func deleteLabBeds(_ request: RuntimeLabBedDeleteRequest) async throws -> RuntimeLabBedList {
        RuntimeLabBedList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func resetLabBeds() async throws -> RuntimeLabBedList {
        RuntimeLabBedList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func createLabRecorders(_ request: RuntimeLabRecorderCreateRequest) async throws -> RuntimeLabRecorderList {
        RuntimeLabRecorderList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func deleteLabRecorders(_ request: RuntimeLabRecorderDeleteRequest) async throws -> RuntimeLabRecorderList {
        RuntimeLabRecorderList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func resetLabRecorders() async throws -> RuntimeLabRecorderList {
        RuntimeLabRecorderList.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func hideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        RuntimeVitalRecorderHistory(readError: "VitalDB read model gateway is unavailable.")
    }

    func unhideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        RuntimeVitalRecorderHistory(readError: "VitalDB read model gateway is unavailable.")
    }

    func deleteVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        RuntimeVitalRecorderHistory(readError: "VitalDB read model gateway is unavailable.")
    }

    func loadVitalDBBeds() async throws -> RuntimeVitalBedHistory {
        .failed(readError: "VitalDB bed read model gateway is unavailable.")
    }

    func hideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory {
        .failed(readError: "VitalDB bed read model gateway is unavailable.")
    }

    func unhideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory {
        .failed(readError: "VitalDB bed read model gateway is unavailable.")
    }

    func deleteVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory {
        .failed(readError: "VitalDB bed read model gateway is unavailable.")
    }

    func createLabSession(_ request: RuntimeLabSessionCreateRequest) async throws -> RuntimeLabSessionResponse {
        RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func loadLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func startLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func stopLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func replayLabVitalFile(_ request: RuntimeLabVitalFileReplayRequest) async throws -> RuntimeLabSessionResponse {
        RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func uploadLabVitalFile(_ request: RuntimeLabVitalFileUploadRequest) async throws -> RuntimeLabVitalFileUploadResponse {
        RuntimeLabVitalFileUploadResponse.unavailable(readError: "Runtime Lab gateway is unavailable.")
    }

    func startGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
    }

    func stopGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
    }

    func restartGuestService(_ request: RuntimeGuestServiceRestartRequest) async throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
    }

    func acquireOperationLease(_ request: RuntimeOperationLeaseAcquireRequest) async throws -> RuntimeOperationLeaseMutationResponse {
        throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
    }

    func heartbeatOperationLease(_ request: RuntimeOperationLeaseHeartbeatRequest) async throws -> RuntimeOperationLeaseMutationResponse {
        throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
    }

    func releaseOperationLease(_ request: RuntimeOperationLeaseReleaseRequest) async throws -> RuntimeOperationLeaseMutationResponse {
        throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
    }

    func guestStackStatus() async throws -> RuntimeGuestControlStackStatus {
        throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
    }

    func listGuestServices() async throws -> RuntimeGuestControlServiceList {
        throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
    }

    func guestServiceStatus(_ service: String) async throws -> RuntimeGuestControlServiceStatus {
        throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
    }

    func guestServiceResource(_ service: String) async throws -> RuntimeGuestServiceResource {
        throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
    }

    func loadVitalDBRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) async throws -> RuntimeVitalRecorderActivityWindow {
        RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
            query: query,
            bounds: nil,
            records: [],
            readError: "recorder activity window reader is unavailable"
        )
    }
}
