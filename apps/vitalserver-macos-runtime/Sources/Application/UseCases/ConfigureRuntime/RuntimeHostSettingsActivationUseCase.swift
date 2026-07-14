import Domain

public typealias RuntimeHostSettingsStateTransitionError = RuntimeHostSettingsActivationError

public struct RuntimeHostSettingsActivationUseCase {
    public init() {}

    public func initialRevision(currentRevision: Int?) throws -> Int {
        try RuntimeHostSettingsActivationPolicy().initialRevision(currentRevision: currentRevision)
    }

    public func importRevision(currentRevision: Int?) throws -> Int {
        try RuntimeHostSettingsActivationPolicy().importRevision(currentRevision: currentRevision)
    }

    public func nextDesiredRevision(currentRevision: Int?, expectedRevision: Int) throws -> Int {
        try RuntimeHostSettingsActivationPolicy().nextDesiredRevision(
            currentRevision: currentRevision,
            expectedRevision: expectedRevision
        )
    }

    public func requireMaterialization(record: RuntimeHostSettingsRecord, revision: Int) throws {
        try RuntimeHostSettingsActivationPolicy().requireMaterialization(
            state: state(record),
            revision: revision
        )
    }

    public func requireBoot(record: RuntimeHostSettingsRecord, revision: Int, runID: String) throws {
        try RuntimeHostSettingsActivationPolicy().requireBoot(
            state: state(record),
            revision: revision,
            runID: runID
        )
    }

    public func requireApply(record: RuntimeHostSettingsRecord, revision: Int, runID: String) throws {
        try RuntimeHostSettingsActivationPolicy().requireApply(
            state: state(record),
            revision: revision,
            runID: runID
        )
    }

    private func state(_ record: RuntimeHostSettingsRecord) -> RuntimeHostSettingsActivationState {
        RuntimeHostSettingsActivationState(
            revision: record.revision,
            materializedRevision: record.materializedRevision,
            bootRevision: record.bootRevision,
            bootRunID: record.bootRunID
        )
    }
}

extension RuntimeHostSettingsActivationUseCase: RuntimeHostSettingsTransitionDeciding {}
