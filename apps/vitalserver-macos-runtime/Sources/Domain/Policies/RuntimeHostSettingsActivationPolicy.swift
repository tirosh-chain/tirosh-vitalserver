public enum RuntimeHostSettingsActivationError: Error, Equatable, CustomStringConvertible {
    case missingState
    case alreadyExists(revision: Int)
    case staleRevision(expected: Int, actual: Int)
    case notMaterialized(revision: Int)
    case invalidRunID
    case bootMismatch(expectedRevision: Int, actualRevision: Int?, expectedRunID: String, actualRunID: String?)

    public var description: String {
        switch self {
        case .missingState:
            return "Host settings state is missing"
        case .alreadyExists(let revision):
            return "Host settings state already exists revision=\(revision)"
        case .staleRevision(let expected, let actual):
            return "Host settings revision is stale expected=\(expected) actual=\(actual)"
        case .notMaterialized(let revision):
            return "Host settings revision is not materialized revision=\(revision)"
        case .invalidRunID:
            return "Host settings boot run ID is missing"
        case .bootMismatch(let expectedRevision, let actualRevision, let expectedRunID, let actualRunID):
            let actualRevisionText = actualRevision.map(String.init) ?? "missing"
            let actualRunIDText = actualRunID ?? "missing"
            return "Host settings boot proof mismatch expectedRevision=\(expectedRevision) actualRevision=\(actualRevisionText) expectedRunId=\(expectedRunID) actualRunId=\(actualRunIDText)"
        }
    }
}

public struct RuntimeHostSettingsActivationState: Equatable, Sendable {
    public let revision: Int
    public let materializedRevision: Int?
    public let bootRevision: Int?
    public let bootRunID: String?

    public init(
        revision: Int,
        materializedRevision: Int?,
        bootRevision: Int?,
        bootRunID: String?
    ) {
        self.revision = revision
        self.materializedRevision = materializedRevision
        self.bootRevision = bootRevision
        self.bootRunID = bootRunID
    }
}

public struct RuntimeHostSettingsActivationPolicy: Sendable {
    public init() {}

    public func importRevision(currentRevision: Int?) throws -> Int {
        if let currentRevision {
            throw RuntimeHostSettingsActivationError.alreadyExists(revision: currentRevision)
        }
        return 1
    }

    public func nextDesiredRevision(currentRevision: Int?, expectedRevision: Int) throws -> Int {
        guard let currentRevision else {
            throw RuntimeHostSettingsActivationError.missingState
        }
        guard currentRevision == expectedRevision else {
            throw RuntimeHostSettingsActivationError.staleRevision(
                expected: expectedRevision,
                actual: currentRevision
            )
        }
        return currentRevision + 1
    }

    public func requireMaterialization(state: RuntimeHostSettingsActivationState, revision: Int) throws {
        try requireCurrent(state: state, revision: revision)
    }

    public func requireBoot(state: RuntimeHostSettingsActivationState, revision: Int, runID: String) throws {
        try requireCurrent(state: state, revision: revision)
        guard state.materializedRevision == revision else {
            throw RuntimeHostSettingsActivationError.notMaterialized(revision: revision)
        }
        guard !runID.isEmpty else {
            throw RuntimeHostSettingsActivationError.invalidRunID
        }
    }

    public func requireApply(state: RuntimeHostSettingsActivationState, revision: Int, runID: String) throws {
        try requireCurrent(state: state, revision: revision)
        guard state.bootRevision == revision, state.bootRunID == runID else {
            throw RuntimeHostSettingsActivationError.bootMismatch(
                expectedRevision: revision,
                actualRevision: state.bootRevision,
                expectedRunID: runID,
                actualRunID: state.bootRunID
            )
        }
    }

    private func requireCurrent(state: RuntimeHostSettingsActivationState, revision: Int) throws {
        guard state.revision == revision else {
            throw RuntimeHostSettingsActivationError.staleRevision(
                expected: revision,
                actual: state.revision
            )
        }
    }
}
