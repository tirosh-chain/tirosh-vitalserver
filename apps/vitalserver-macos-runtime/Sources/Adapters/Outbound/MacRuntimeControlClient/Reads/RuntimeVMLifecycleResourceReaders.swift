import Application
import Contracts
import Foundation
import RuntimeControl

public protocol RuntimeVMLifecycleResourceReading: Sendable {
    func loadVMLifecycleResource() -> RuntimeVMLifecycleResourceState
}

public protocol RuntimeVMLifecycleResourceWriting {
    @discardableResult
    func writeVMLifecycleResource(
        state: RuntimeVMLifecycleState,
        operation: RuntimeOperation?,
        terminalReason: RuntimeVMLifecycleTerminalReason?,
        message: String?,
        bootWindowSeconds: TimeInterval?
    ) throws -> RuntimeVMLifecycleResourceState
}

public struct UnavailableRuntimeVMLifecycleResourceReader: RuntimeVMLifecycleResourceReading {
    private let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public func loadVMLifecycleResource() -> RuntimeVMLifecycleResourceState {
        .unavailable(readError: reason)
    }
}

public struct MissingRuntimeVMLifecycleResourceReader: RuntimeVMLifecycleResourceReading {
    private let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public func loadVMLifecycleResource() -> RuntimeVMLifecycleResourceState {
        .missing(readError: reason)
    }
}

public struct RuntimeControlAPIVMLifecycleResourceReader: RuntimeVMLifecycleResourceReading {
    private let ownerFactory: @Sendable () throws -> RuntimeControlAPIVMLifecycleOwner

    public init(
        ownerFactory: @escaping @Sendable () throws -> RuntimeControlAPIVMLifecycleOwner = {
            try RuntimeControlAPIVMLifecycleOwner()
        }
    ) {
        self.ownerFactory = ownerFactory
    }

    public func loadVMLifecycleResource() -> RuntimeVMLifecycleResourceState {
        do {
            return try ownerFactory().loadVMLifecycleResource()
        } catch {
            return .failed(readError: String(describing: error))
        }
    }
}

public struct RuntimeControlAPIVMLifecycleResourceWriter: RuntimeVMLifecycleResourceWriting {
    private let ownerFactory: () throws -> RuntimeControlAPIVMLifecycleOwner
    private let now: @Sendable () -> Date

    public init(
        ownerFactory: @escaping () throws -> RuntimeControlAPIVMLifecycleOwner = {
            try RuntimeControlAPIVMLifecycleOwner()
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.ownerFactory = ownerFactory
        self.now = now
    }

    @discardableResult
    public func writeVMLifecycleResource(
        state: RuntimeVMLifecycleState,
        operation: RuntimeOperation? = nil,
        terminalReason: RuntimeVMLifecycleTerminalReason? = nil,
        message: String? = nil,
        bootWindowSeconds: TimeInterval? = nil
    ) throws -> RuntimeVMLifecycleResourceState {
        let owner = try ownerFactory()
        let timestamp = now()
        let startedAt = try startedAtForWrite(
            state: state,
            timestamp: timestamp,
            owner: owner
        )
        let deadlineAt = bootWindowSeconds.map { timestamp.addingTimeInterval($0) }
        return try owner.putVMLifecycleResource(RuntimeVMLifecycleDocument(
            state: state,
            operation: operation,
            startedAt: ISO8601DateFormatter().string(from: startedAt),
            updatedAt: ISO8601DateFormatter().string(from: timestamp),
            deadlineAt: deadlineAt.map { ISO8601DateFormatter().string(from: $0) },
            terminalReason: terminalReason,
            message: message
        ))
    }

    private func startedAtForWrite(
        state: RuntimeVMLifecycleState,
        timestamp: Date,
        owner: RuntimeControlAPIVMLifecycleOwner
    ) throws -> Date {
        guard state != .starting else {
            return timestamp
        }
        let resource = try owner.loadVMLifecycleResource()
        switch resource.state {
        case .loaded:
            guard let document = resource.document else {
                throw RuntimeControlClientHTTPClientError.invalidVMLifecycleState(
                    "state=loaded has no VM lifecycle document"
                )
            }
            guard let startedAt = ISO8601DateFormatter().date(from: document.startedAt) else {
                throw RuntimeVMLifecycleResourceWriteError.invalidStartedAt(document.startedAt)
            }
            return startedAt
        case .missing:
            throw RuntimeVMLifecycleResourceWriteError.missingDocumentForState(state)
        case .unavailable, .failed:
            throw RuntimeVMLifecycleResourceWriteError.readFailed(
                resource.readError ?? "VM lifecycle resource read failed state=\(resource.state.rawValue)"
            )
        }
    }
}

enum RuntimeVMLifecycleResourceReadMapper {
    static func loadResult(
        from resource: RuntimeVMLifecycleResourceState
    ) -> RuntimeGuestDocumentLoadResult<RuntimeVMLifecycleDocument> {
        switch resource.state {
        case .loaded:
            guard let document = resource.document else {
                return .failed("VM lifecycle resource loaded without document")
            }
            return .loaded(document)
        case .missing:
            return .missing
        case .unavailable:
            return .failed(resource.readError ?? "VM lifecycle resource unavailable")
        case .failed:
            return .failed(resource.readError ?? "VM lifecycle resource read failed")
        }
    }

    static func statusRead(from resource: RuntimeVMLifecycleResourceState) -> RuntimeVMLifecycleRead {
        switch resource.state {
        case .loaded:
            guard let document = resource.document else {
                return RuntimeVMLifecycleRead(
                    document: nil,
                    issue: PlatformStateReadIssue(
                        source: "vmLifecycle",
                        message: "VM lifecycle resource loaded without document"
                    )
                )
            }
            return RuntimeVMLifecycleRead(document: document, issue: nil)
        case .missing:
            return RuntimeVMLifecycleRead(
                document: nil,
                issue: PlatformStateReadIssue(
                    source: "vmLifecycle",
                    message: resource.readError ?? "VM lifecycle document missing"
                )
            )
        case .unavailable:
            return RuntimeVMLifecycleRead(
                document: nil,
                issue: PlatformStateReadIssue(
                    source: "vmLifecycle",
                    message: resource.readError ?? "VM lifecycle resource unavailable"
                )
            )
        case .failed:
            return RuntimeVMLifecycleRead(
                document: nil,
                issue: PlatformStateReadIssue(
                    source: "vmLifecycle",
                    message: resource.readError ?? "VM lifecycle resource read failed"
                )
            )
        }
    }
}
