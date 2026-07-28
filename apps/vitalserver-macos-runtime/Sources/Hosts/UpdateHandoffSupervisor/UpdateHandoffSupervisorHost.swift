import Application
import Contracts
import Darwin
import Foundation
import OutboundAdapters
import Workflow

enum UpdateHandoffSupervisorHostError: Error, Equatable {
    case invalidArguments
    case jobNotFound(String)
    case childOwnerAlreadyClaimed(jobId: String, launchId: String)
    case childOwnerReceiptWriteFailed(path: String, reason: String)
}

struct UpdateHandoffSupervisorHost {
    func run(arguments: [String]) throws {
        guard let command = arguments.first else {
            throw UpdateHandoffSupervisorHostError.invalidArguments
        }
        let options = try parseOptions(Array(arguments.dropFirst()))
        switch command {
        case "serve":
            let root = try requiredURL("--root", options)
            let interval = Int(options["--interval-ms"] ?? "500") ?? 500
            while true {
                try serveOnce(root: root)
                usleep(useconds_t(max(interval, 10) * 1_000))
            }
        case "serve-once":
            try serveOnce(root: try requiredURL("--root", options))
        case "enqueue":
            let root = try requiredURL("--root", options)
            let operations = makeOperations(root: root)
            let job = try UpdateHandoffSupervisorWorkflow().enqueue(
                jobId: try required("--job-id", options),
                updateId: try required("--update-id", options),
                operationId: try required("--operation-id", options),
                invocationPath: try required("--invocation", options),
                updaterPath: try required("--updater", options),
                operations: operations
            )
            printJob(job)
        case "cancel":
            let root = try requiredURL("--root", options)
            let store = makeStore(root: root)
            let jobId = try required("--job-id", options)
            let requested = try UpdateHandoffSupervisorWorkflow()
                .requestCancellation(
                    try store.load(jobId: jobId),
                    operations: makeOperations(root: root)
                )
            printJob(requested)
        case "wait":
            let root = try requiredURL("--root", options)
            let store = makeStore(root: root)
            let jobId = try required("--job-id", options)
            let attempts = Int(options["--attempts"] ?? "120") ?? 120
            let interval = Int(options["--interval-ms"] ?? "500") ?? 500
            let job = try UpdateHandoffSupervisorWorkflow().wait(
                jobId: jobId,
                attempts: attempts,
                load: { try store.load(jobId: jobId) },
                pause: { usleep(useconds_t(max(interval, 10) * 1_000)) }
            )
            printJob(job)
        case "run-child":
            try runChild(options: options)
        default:
            throw UpdateHandoffSupervisorHostError.invalidArguments
        }
    }

    private func serveOnce(root: URL) throws {
        let store = makeStore(root: root)
        let operations = makeOperations(root: root)
        for job in try store.loadAll() where !job.state.isTerminal {
            _ = try UpdateHandoffSupervisorWorkflow().reconcile(
                job,
                operations: operations
            )
        }
    }

    private func makeOperations(
        root: URL
    ) -> UpdateHandoffSupervisorWorkflowOperations {
        let store = makeStore(root: root)
        let controller = SystemUpdateHandoffChildProcessController(
            supervisorExecutable: URL(
                fileURLWithPath: CommandLine.arguments[0]
            ),
            store: store
        )
        let manager = ManageUpdateHandoffJobUseCase()
        return UpdateHandoffSupervisorWorkflowOperations(
            enqueue: manager.enqueue,
            launchClaimed: manager.launchClaimed,
            childStarted: manager.childStarted,
            childCompleted: manager.childCompleted,
            cancellationRequested: manager.cancellationRequested,
            processTreeTerminated: manager.processTreeTerminated,
            childCompletionUnavailable:
                manager.childCompletionUnavailable,
            save: store.save,
            launchChildOwner: controller.launchChildOwner,
            readStartReceipt: store.readStartReceipt,
            readCompletionReceipt: store.readCompletionReceipt,
            observeChild: controller.observe,
            terminateProcessTree: controller.terminateProcessTree,
            makeId: { UUID().uuidString.lowercased() },
            now: now,
            describeFailure: { String(describing: $0) }
        )
    }

    private func makeStore(root: URL) -> FileUpdateHandoffSupervisorStore {
        FileUpdateHandoffSupervisorStore(
            root: root,
            validate: ValidateUpdateHandoffJobUseCase().validate
        )
    }

    private func runChild(options: [String: String]) throws {
        let jobId = try required("--job-id", options)
        let launchId = try required("--launch-id", options)
        let updater = try required("--updater", options)
        let invocation = try required("--invocation", options)
        let startURL = try requiredURL("--start-receipt", options)
        let completionURL = try requiredURL("--completion-receipt", options)

        _ = setpgid(0, 0)
        let pid = Int32(getpid())
        let pgid = Int32(getpgrp())
        let child = UpdateHandoffChildIdentity(
            launchId: launchId,
            processId: pid,
            processGroupId: pgid,
            startedAt: now()
        )
        let start = UpdateHandoffChildStartReceipt(
            jobId: jobId,
            child: child
        )
        do {
            try writeExclusive(start, to: startURL)
        } catch CocoaError.fileWriteFileExists {
            let existing = try JSONDecoder().decode(
                UpdateHandoffChildStartReceipt.self,
                from: Data(contentsOf: startURL)
            )
            guard existing.jobId == jobId,
                  existing.child.launchId == launchId else {
                throw UpdateHandoffSupervisorHostError
                    .childOwnerAlreadyClaimed(
                        jobId: jobId,
                        launchId: launchId
                    )
            }
            return
        } catch {
            throw UpdateHandoffSupervisorHostError
                .childOwnerReceiptWriteFailed(
                    path: startURL.path,
                    reason: String(describing: error)
                )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: updater)
        process.arguments = ["execute", "--invocation", invocation]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let receipt: UpdateHandoffChildCompletionReceipt
        do {
            try process.run()
            process.waitUntilExit()
            let exitCode: Int32
            switch process.terminationReason {
            case .exit:
                exitCode = process.terminationStatus
            case .uncaughtSignal:
                exitCode = 128 + process.terminationStatus
            @unknown default:
                exitCode = process.terminationStatus
            }
            receipt = UpdateHandoffChildCompletionReceipt(
                jobId: jobId,
                launchId: launchId,
                processId: pid,
                processGroupId: pgid,
                exitCode: exitCode,
                launchFailureReason: nil,
                finishedAt: now()
            )
        } catch {
            receipt = UpdateHandoffChildCompletionReceipt(
                jobId: jobId,
                launchId: launchId,
                processId: pid,
                processGroupId: pgid,
                exitCode: nil,
                launchFailureReason: String(describing: error),
                finishedAt: now()
            )
        }
        try writeAtomic(receipt, to: completionURL)
    }

    private func writeExclusive<T: Encodable>(
        _ value: T,
        to url: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoded(value).write(to: url, options: .withoutOverwriting)
    }

    private func writeAtomic<T: Encodable>(_ value: T, to url: URL) throws {
        try encoded(value).write(to: url, options: .atomic)
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private func parseOptions(_ arguments: [String]) throws -> [String: String] {
        guard arguments.count.isMultiple(of: 2) else {
            throw UpdateHandoffSupervisorHostError.invalidArguments
        }
        var result: [String: String] = [:]
        for index in stride(from: 0, to: arguments.count, by: 2) {
            guard arguments[index].hasPrefix("--") else {
                throw UpdateHandoffSupervisorHostError.invalidArguments
            }
            result[arguments[index]] = arguments[index + 1]
        }
        return result
    }

    private func required(
        _ key: String,
        _ options: [String: String]
    ) throws -> String {
        guard let value = options[key], !value.isEmpty else {
            throw UpdateHandoffSupervisorHostError.invalidArguments
        }
        return value
    }

    private func requiredURL(
        _ key: String,
        _ options: [String: String]
    ) throws -> URL {
        let path = try required(key, options)
        guard path.hasPrefix("/") else {
            throw UpdateHandoffSupervisorHostError.invalidArguments
        }
        return URL(fileURLWithPath: path)
    }

    private func printJob(_ job: UpdateHandoffJobDocument) {
        print("job: \(job.jobId)")
        print("state: \(job.state.rawValue)")
        print("revision: \(job.revision)")
    }

    private func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
