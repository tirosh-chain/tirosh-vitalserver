import Application
import Contracts
import Domain
import Foundation
import Workflow

enum RuntimeUninstallWorkflowOperationStateSessionError: Error, Equatable, CustomStringConvertible {
    case databaseOutsideProductRoot(database: String, productRoot: String)
    case relocatedStateMissing(path: String, operationID: String)
    case relocatedStateReadFailed(path: String, reason: String)
    case relocatedStateOperationMismatch(expected: String, actual: String)
    case relocatedLeaseMissing(path: String, operationID: String)
    case relocatedLeaseReadFailed(path: String, reason: String)
    case relocatedLeaseMismatch(expected: String, actual: String)
    case leaseNotAcquired
    case leaseReleaseFailed(String)

    var description: String {
        switch self {
        case .databaseOutsideProductRoot(let database, let productRoot):
            return "runtime state database is outside product root database=\(database) productRoot=\(productRoot)"
        case .relocatedStateMissing(let path, let operationID):
            return "relocated uninstall workflow state is missing path=\(path) operationId=\(operationID)"
        case .relocatedStateReadFailed(let path, let reason):
            return "relocated uninstall workflow state read failed path=\(path) reason=\(reason)"
        case .relocatedStateOperationMismatch(let expected, let actual):
            return "relocated uninstall workflow operation mismatch expected=\(expected) actual=\(actual)"
        case .relocatedLeaseMissing(let path, let operationID):
            return "relocated uninstall operation lease is missing path=\(path) operationId=\(operationID)"
        case .relocatedLeaseReadFailed(let path, let reason):
            return "relocated uninstall operation lease read failed path=\(path) reason=\(reason)"
        case .relocatedLeaseMismatch(let expected, let actual):
            return "relocated uninstall operation lease mismatch expected=\(expected) actual=\(actual)"
        case .leaseNotAcquired:
            return "uninstall operation lease is not acquired"
        case .leaseReleaseFailed(let reason):
            return "uninstall operation lease release previously failed reason=\(reason)"
        }
    }
}

final class RuntimeUninstallWorkflowOperationStateSession: @unchecked Sendable {
    typealias RepositoryFactory = (URL) -> any RuntimeWorkflowOperationStateRepository
    typealias LeaseOwnerFactory = (URL) -> any RuntimeOperationLeaseOwner

    private enum LeaseState {
        case notAcquired
        case acquired
        case released
        case releaseFailed(String)
    }

    let operationID: String
    private let now: () -> Date
    private let ownerPID: Int
    private let leaseDurationSeconds: TimeInterval
    private let repositoryFactory: RepositoryFactory
    private let leaseOwnerFactory: LeaseOwnerFactory
    private var repository: any RuntimeWorkflowOperationStateRepository
    private var leaseOwner: any RuntimeOperationLeaseOwner
    private var databaseURL: URL
    private var leaseState: LeaseState = .notAcquired

    init(
        operationID: String,
        databaseURL: URL,
        now: @escaping () -> Date,
        ownerPID: Int,
        leaseDurationSeconds: TimeInterval,
        repositoryFactory: @escaping RepositoryFactory,
        leaseOwnerFactory: @escaping LeaseOwnerFactory
    ) {
        self.operationID = operationID
        self.databaseURL = databaseURL
        self.now = now
        self.ownerPID = ownerPID
        self.leaseDurationSeconds = leaseDurationSeconds
        self.repositoryFactory = repositoryFactory
        self.leaseOwnerFactory = leaseOwnerFactory
        self.repository = repositoryFactory(databaseURL)
        self.leaseOwner = leaseOwnerFactory(databaseURL)
    }

    func writer() -> RuntimeUninstallStateWriter {
        RuntimeUninstallStateWriter(
            acquireOperationLease: { [self] in
                try acquireOperationLease()
            },
            releaseOperationLease: { [self] in
                try releaseOperationLease()
            },
            writeState: { [self] state, _, message, blockers in
                try heartbeatOperationLease()
                let event = try RuntimeUninstallWorkflowOperationStateProjectionPolicy.event(
                    operationID: operationID,
                    state: state,
                    message: message,
                    blockers: blockers
                )
                _ = try PersistRuntimeWorkflowOperationStateUseCase().transition(
                    repository: repository,
                    operationID: operationID,
                    event: event,
                    occurredAt: timestamp(now())
                )
            },
            relocateProductRoot: { [self] sourceRoot, destinationRoot in
                try relocateRepository(from: sourceRoot, to: destinationRoot)
            }
        )
    }

    private func acquireOperationLease() throws {
        let current = now()
        let occurredAt = timestamp(current)
        try leaseOwner.acquire(RuntimeOperationLeaseDocument(
            operationId: operationID,
            operation: .uninstall,
            ownerPID: ownerPID,
            startedAt: occurredAt,
            heartbeatAt: occurredAt,
            expiresAt: timestamp(current.addingTimeInterval(leaseDurationSeconds)),
            message: "runtime uninstall"
        ))
        leaseState = .acquired
    }

    private func heartbeatOperationLease() throws {
        guard case .acquired = leaseState else {
            throw RuntimeUninstallWorkflowOperationStateSessionError.leaseNotAcquired
        }
        let current = now()
        try leaseOwner.heartbeat(
            operationId: operationID,
            heartbeatAt: timestamp(current),
            expiresAt: timestamp(current.addingTimeInterval(leaseDurationSeconds))
        )
    }

    private func releaseOperationLease() throws {
        switch leaseState {
        case .notAcquired:
            throw RuntimeUninstallWorkflowOperationStateSessionError.leaseNotAcquired
        case .acquired:
            do {
                try leaseOwner.release(operationId: operationID)
                leaseState = .released
            } catch {
                let reason = String(describing: error)
                leaseState = .releaseFailed(reason)
                throw error
            }
        case .released:
            return
        case .releaseFailed(let reason):
            throw RuntimeUninstallWorkflowOperationStateSessionError.leaseReleaseFailed(reason)
        }
    }

    private func relocateRepository(from sourceRoot: URL, to destinationRoot: URL) throws {
        let sourcePrefix = sourceRoot.standardizedFileURL.path + "/"
        let standardizedDatabasePath = databaseURL.standardizedFileURL.path
        guard standardizedDatabasePath.hasPrefix(sourcePrefix) else {
            throw RuntimeUninstallWorkflowOperationStateSessionError.databaseOutsideProductRoot(
                database: standardizedDatabasePath,
                productRoot: sourceRoot.standardizedFileURL.path
            )
        }
        let relativePath = String(standardizedDatabasePath.dropFirst(sourcePrefix.count))
        let relocatedDatabaseURL = destinationRoot.appendingPathComponent(relativePath)
        let relocatedRepository = repositoryFactory(relocatedDatabaseURL)
        let relocatedLeaseOwner = leaseOwnerFactory(relocatedDatabaseURL)
        switch relocatedRepository.loadOperationState(operationID: operationID) {
        case .loaded(let state):
            guard state.operation == .uninstall else {
                throw RuntimeUninstallWorkflowOperationStateSessionError.relocatedStateOperationMismatch(
                    expected: RuntimeOperation.uninstall.rawValue,
                    actual: state.operation.rawValue
                )
            }
        case .missing:
            throw RuntimeUninstallWorkflowOperationStateSessionError.relocatedStateMissing(
                path: relocatedDatabaseURL.path,
                operationID: operationID
            )
        case .failed(let reason):
            throw RuntimeUninstallWorkflowOperationStateSessionError.relocatedStateReadFailed(
                path: relocatedDatabaseURL.path,
                reason: reason
            )
        }
        switch relocatedLeaseOwner.loadOperationLease() {
        case .loaded(let lease):
            guard lease.operationId == operationID, lease.operation == .uninstall else {
                throw RuntimeUninstallWorkflowOperationStateSessionError.relocatedLeaseMismatch(
                    expected: "\(operationID):\(RuntimeOperation.uninstall.rawValue)",
                    actual: "\(lease.operationId):\(lease.operation.rawValue)"
                )
            }
        case .missing:
            throw RuntimeUninstallWorkflowOperationStateSessionError.relocatedLeaseMissing(
                path: relocatedDatabaseURL.path,
                operationID: operationID
            )
        case .failed(let reason):
            throw RuntimeUninstallWorkflowOperationStateSessionError.relocatedLeaseReadFailed(
                path: relocatedDatabaseURL.path,
                reason: reason
            )
        }
        databaseURL = relocatedDatabaseURL
        repository = relocatedRepository
        leaseOwner = relocatedLeaseOwner
    }

    private func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
