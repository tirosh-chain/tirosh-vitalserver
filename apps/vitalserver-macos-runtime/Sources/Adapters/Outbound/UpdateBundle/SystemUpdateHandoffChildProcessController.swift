import Contracts
import Darwin
import Foundation

public enum SystemUpdateHandoffChildProcessControllerError:
    Error, Equatable, Sendable {
    case missingLaunchId(jobId: String)
    case supervisorUnavailable(path: String)
    case launchFailed(path: String, reason: String)
}

public struct SystemUpdateHandoffChildProcessController {
    public let supervisorExecutable: URL
    public let store: FileUpdateHandoffSupervisorStore

    public init(
        supervisorExecutable: URL,
        store: FileUpdateHandoffSupervisorStore
    ) {
        self.supervisorExecutable = supervisorExecutable
        self.store = store
    }

    public func launchChildOwner(
        job: UpdateHandoffJobDocument
    ) throws {
        guard let launchId = job.launchId else {
            throw SystemUpdateHandoffChildProcessControllerError
                .missingLaunchId(jobId: job.jobId)
        }
        guard FileManager.default.isExecutableFile(
            atPath: supervisorExecutable.path
        ) else {
            throw SystemUpdateHandoffChildProcessControllerError
                .supervisorUnavailable(path: supervisorExecutable.path)
        }
        let process = Process()
        process.executableURL = supervisorExecutable
        process.arguments = [
            "run-child",
            "--job-id", job.jobId,
            "--launch-id", launchId,
            "--updater", job.updaterPath,
            "--invocation", job.invocationPath,
            "--start-receipt", store.startReceiptURL(jobId: job.jobId).path,
            "--completion-receipt",
            store.completionReceiptURL(jobId: job.jobId).path,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw SystemUpdateHandoffChildProcessControllerError.launchFailed(
                path: supervisorExecutable.path,
                reason: String(describing: error)
            )
        }
    }

    public func observe(
        child: UpdateHandoffChildIdentity
    ) -> UpdateHandoffChildObservation {
        errno = 0
        let group = getpgid(pid_t(child.processId))
        if group == pid_t(child.processGroupId) {
            return .running(child)
        }
        if group == -1, errno == ESRCH {
            return .notRunning(child)
        }
        let reason = String(cString: strerror(errno))
        return .failed(child, reason: reason)
    }

    public func terminateProcessTree(
        child: UpdateHandoffChildIdentity
    ) -> UpdateHandoffProcessTreeTerminationResult {
        let group = pid_t(child.processGroupId)
        errno = 0
        if kill(-group, SIGTERM) != 0, errno != ESRCH {
            return .failed(
                child,
                reason: "SIGTERM failed: \(String(cString: strerror(errno)))"
            )
        }
        for _ in 0..<50 {
            if getpgid(pid_t(child.processId)) == -1, errno == ESRCH {
                return .terminated(child)
            }
            usleep(100_000)
        }
        errno = 0
        if kill(-group, SIGKILL) != 0, errno != ESRCH {
            return .failed(
                child,
                reason: "SIGKILL failed: \(String(cString: strerror(errno)))"
            )
        }
        return .terminated(child)
    }
}
