import Foundation

public struct RuntimeHostSettingsPayload: Equatable, Sendable {
    public let vmConfigJSON: Data
    public let guestRuntimeConfigJSON: Data
    public let guestRuntimeSettingsJSON: Data

    public init(
        vmConfigJSON: Data,
        guestRuntimeConfigJSON: Data,
        guestRuntimeSettingsJSON: Data
    ) {
        self.vmConfigJSON = vmConfigJSON
        self.guestRuntimeConfigJSON = guestRuntimeConfigJSON
        self.guestRuntimeSettingsJSON = guestRuntimeSettingsJSON
    }
}

public struct RuntimeHostSettingsRecord: Equatable, Sendable {
    public let payload: RuntimeHostSettingsPayload
    public let appliedPayload: RuntimeHostSettingsPayload?
    public let revision: Int
    public let desiredAt: String
    public let materializedRevision: Int?
    public let materializedAt: String?
    public let bootRevision: Int?
    public let bootRunID: String?
    public let bootStartedAt: String?
    public let appliedRevision: Int?
    public let appliedRunID: String?
    public let appliedAt: String?

    public init(
        payload: RuntimeHostSettingsPayload,
        appliedPayload: RuntimeHostSettingsPayload? = nil,
        revision: Int,
        desiredAt: String,
        materializedRevision: Int? = nil,
        materializedAt: String? = nil,
        bootRevision: Int? = nil,
        bootRunID: String? = nil,
        bootStartedAt: String? = nil,
        appliedRevision: Int? = nil,
        appliedRunID: String? = nil,
        appliedAt: String? = nil
    ) {
        self.payload = payload
        self.appliedPayload = appliedPayload
        self.revision = revision
        self.desiredAt = desiredAt
        self.materializedRevision = materializedRevision
        self.materializedAt = materializedAt
        self.bootRevision = bootRevision
        self.bootRunID = bootRunID
        self.bootStartedAt = bootStartedAt
        self.appliedRevision = appliedRevision
        self.appliedRunID = appliedRunID
        self.appliedAt = appliedAt
    }

    public var requiresVMRestart: Bool {
        appliedRevision != revision || appliedPayload == nil
    }
}

public enum RuntimeHostSettingsReadResult: Equatable, Sendable {
    case missing
    case loaded(RuntimeHostSettingsRecord)
    case failed(String)
}

public protocol RuntimeHostSettingsReading: Sendable {
    func loadHostSettings() -> RuntimeHostSettingsReadResult
}

public protocol RuntimeHostSettingsRepository: RuntimeHostSettingsReading {
    @discardableResult
    func initializeDesiredHostSettings(
        _ payload: RuntimeHostSettingsPayload,
        desiredAt: String
    ) throws -> RuntimeHostSettingsRecord

    @discardableResult
    func importMaterializedHostSettings(
        _ payload: RuntimeHostSettingsPayload,
        importedAt: String
    ) throws -> RuntimeHostSettingsRecord

    @discardableResult
    func saveDesiredHostSettings(
        _ payload: RuntimeHostSettingsPayload,
        expectedRevision: Int,
        desiredAt: String
    ) throws -> RuntimeHostSettingsRecord

    @discardableResult
    func markHostSettingsMaterialized(
        revision: Int,
        materializedAt: String
    ) throws -> RuntimeHostSettingsRecord

    @discardableResult
    func recordHostSettingsBoot(
        revision: Int,
        runID: String,
        startedAt: String
    ) throws -> RuntimeHostSettingsRecord

    @discardableResult
    func markHostSettingsApplied(
        revision: Int,
        runID: String,
        appliedAt: String
    ) throws -> RuntimeHostSettingsRecord
}

public protocol RuntimeHostSettingsTransitionDeciding: Sendable {
    func initialRevision(currentRevision: Int?) throws -> Int
    func importRevision(currentRevision: Int?) throws -> Int
    func nextDesiredRevision(currentRevision: Int?, expectedRevision: Int) throws -> Int
    func requireMaterialization(record: RuntimeHostSettingsRecord, revision: Int) throws
    func requireBoot(record: RuntimeHostSettingsRecord, revision: Int, runID: String) throws
    func requireApply(record: RuntimeHostSettingsRecord, revision: Int, runID: String) throws
}
