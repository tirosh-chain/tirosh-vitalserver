import Application
import Contracts
import Foundation

public enum FileUpdateHandoffSupervisorStoreError:
    Error, Equatable, Sendable {
    case lockUnavailable(path: String, reason: String)
    case jobAlreadyExists(jobId: String)
    case jobMissing(jobId: String)
    case revisionConflict(jobId: String, expected: Int, actual: Int)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)
    case writeFailed(path: String, reason: String)
    case invalidJob(jobId: String, reason: String)
}

public struct FileUpdateHandoffSupervisorStore {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func load(jobId: String) throws -> UpdateHandoffJobDocument {
        try read(jobURL(jobId: jobId))
    }

    public func loadAll() throws -> [UpdateHandoffJobDocument] {
        let fileManager = FileManager.default
        do {
            guard fileManager.fileExists(atPath: root.path) else {
                return []
            }
            return try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            .filter { $0.hasDirectoryPath }
            .map { try read($0.appendingPathComponent("job.json")) }
            .sorted { $0.createdAt < $1.createdAt }
        } catch let error as FileUpdateHandoffSupervisorStoreError {
            throw error
        } catch {
            throw FileUpdateHandoffSupervisorStoreError.readFailed(
                path: root.path,
                reason: String(describing: error)
            )
        }
    }

    public func save(
        _ job: UpdateHandoffJobDocument,
        expectedRevision: Int?
    ) throws {
        do {
            try ValidateUpdateHandoffJobUseCase().validate(job)
        } catch {
            throw FileUpdateHandoffSupervisorStoreError.invalidJob(
                jobId: job.jobId,
                reason: String(describing: error)
            )
        }
        try withJobLock(jobId: job.jobId) {
            let destination = jobURL(jobId: job.jobId)
            let exists = FileManager.default.fileExists(
                atPath: destination.path
            )
            if let expected = expectedRevision {
                guard exists else {
                    throw FileUpdateHandoffSupervisorStoreError.jobMissing(
                        jobId: job.jobId
                    )
                }
                let current: UpdateHandoffJobDocument = try read(destination)
                guard current.revision == expected else {
                    throw FileUpdateHandoffSupervisorStoreError
                        .revisionConflict(
                            jobId: job.jobId,
                            expected: expected,
                            actual: current.revision
                        )
                }
            } else if exists {
                throw FileUpdateHandoffSupervisorStoreError.jobAlreadyExists(
                    jobId: job.jobId
                )
            }
            let data: Data
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                data = try encoder.encode(job)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: destination, options: .atomic)
            } catch {
                throw FileUpdateHandoffSupervisorStoreError.writeFailed(
                    path: destination.path,
                    reason: String(describing: error)
                )
            }
        }
    }

    public func startReceiptURL(jobId: String) -> URL {
        jobDirectory(jobId: jobId)
            .appendingPathComponent("child-start.json")
    }

    public func completionReceiptURL(jobId: String) -> URL {
        jobDirectory(jobId: jobId)
            .appendingPathComponent("child-completion.json")
    }

    public func readStartReceipt(
        job: UpdateHandoffJobDocument
    ) -> UpdateHandoffReceiptReadResult<UpdateHandoffChildStartReceipt> {
        readReceipt(startReceiptURL(jobId: job.jobId))
    }

    public func readCompletionReceipt(
        job: UpdateHandoffJobDocument
    ) -> UpdateHandoffReceiptReadResult<
        UpdateHandoffChildCompletionReceipt
    > {
        readReceipt(completionReceiptURL(jobId: job.jobId))
    }

    private func read<T: Decodable>(_ url: URL) throws -> T {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw FileUpdateHandoffSupervisorStoreError.readFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw FileUpdateHandoffSupervisorStoreError.decodeFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }
    }

    private func readReceipt<T: Decodable & Equatable & Sendable>(
        _ url: URL
    ) -> UpdateHandoffReceiptReadResult<T> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing(path: url.path)
        }
        do {
            return .loaded(try read(url))
        } catch {
            return .failed(path: url.path, reason: String(describing: error))
        }
    }

    private func withJobLock<T>(
        jobId: String,
        operation: () throws -> T
    ) throws -> T {
        let fileManager = FileManager.default
        let lock = root.appendingPathComponent(".\(jobId).lock")
        do {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: lock,
                withIntermediateDirectories: false
            )
        } catch {
            throw FileUpdateHandoffSupervisorStoreError.lockUnavailable(
                path: lock.path,
                reason: String(describing: error)
            )
        }
        defer { try? fileManager.removeItem(at: lock) }
        return try operation()
    }

    private func jobDirectory(jobId: String) -> URL {
        root.appendingPathComponent(jobId, isDirectory: true)
    }

    private func jobURL(jobId: String) -> URL {
        jobDirectory(jobId: jobId).appendingPathComponent("job.json")
    }
}
