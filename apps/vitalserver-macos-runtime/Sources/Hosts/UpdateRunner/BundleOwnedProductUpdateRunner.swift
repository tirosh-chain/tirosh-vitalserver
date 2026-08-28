import Application
import Contracts
import Foundation
import OutboundAdapters
import Workflow

enum BundleOwnedProductUpdateRunnerError: Error, Equatable {
    case invalidArguments
    case updateFailed(code: String, message: String)
}

struct BundleOwnedProductUpdateRunner {
    private let fileStore = SystemRuntimeFileStore()
    private let commandRunner = SystemRuntimeCommandRunner()

    func run(arguments: [String]) throws {
        guard arguments.count == 3,
              arguments[0] == "execute",
              arguments[1] == "--invocation",
              arguments[2].hasPrefix("/") else {
            throw BundleOwnedProductUpdateRunnerError.invalidArguments
        }

        let invocationURL = URL(fileURLWithPath: arguments[2])
        let input = try inputReader().read(invocationURL: invocationURL)
        let effectExecutor = makeEffectExecutor(
            stagedBundleRoot: input.stagedBundleRoot,
            guestControlBaseURL: input.invocation.guestControlBaseURL
        )
        let report = try ExecuteBundleOwnedProductUpdateWorkflow().run(
            invocation: input.invocation,
            specification: input.specification,
            operations: workflowOperations(effectExecutor: effectExecutor)
        )
        let publication = try completionPublisher(
            stagedBundleRoot: input.stagedBundleRoot
        ).publish(report: report, invocation: input.invocation)
        print(
            "published product update completion report=\(publication.reportURL.path) receipt=\(publication.receiptURL.path)"
        )
        if let failure = report.failure {
            throw BundleOwnedProductUpdateRunnerError.updateFailed(
                code: failure.code,
                message: failure.message
            )
        }
    }

    private func inputReader() -> BundleOwnedProductUpdateInputReader {
        BundleOwnedProductUpdateInputReader(
            operations: BundleOwnedProductUpdateInputReadOperations(
                pathState: fileStore.pathState,
                fileSize: fileStore.fileSize,
                readData: fileStore.readData
            )
        )
    }

    private func makeEffectExecutor(
        stagedBundleRoot: URL,
        guestControlBaseURL: String
    ) -> BundleOwnedProductUpdateLayerEffectExecutor {
        let observer = UpdateBootstrapArtifactFileObserver(
            bundleDirectory: stagedBundleRoot
        )
        return BundleOwnedProductUpdateLayerEffectExecutor(
            stagedBundleRoot: stagedBundleRoot,
            guestControlBaseURL: guestControlBaseURL,
            operations:
                BundleOwnedProductUpdateLayerEffectExecutorOperations(
                    observe: observer.observe,
                    fileState: { url in
                        fileStore.fileState(atPath: url.path)
                    },
                    pathState: fileStore.pathState,
                    createDirectory: fileStore.createDirectory,
                    writeData: fileStore.writeData,
                    fileSize: fileStore.fileSize,
                    readData: fileStore.readData,
                    run: commandRunner.run
                )
        )
    }

    private func workflowOperations(
        effectExecutor: BundleOwnedProductUpdateLayerEffectExecutor
    ) -> ExecuteBundleOwnedProductUpdateWorkflowOperations {
        let planner = PlanBundleOwnedProductUpdateUseCase()
        let requestMaker = MakeProductUpdateLayerEffectRequestUseCase()
        let evaluator = EvaluateProductUpdateLayerEffectUseCase()
        let validator = ValidateProductUpdateExecutionReportUseCase()
        return ExecuteBundleOwnedProductUpdateWorkflowOperations(
            plan: planner.execute,
            makeRequest: requestMaker.execute,
            execute: effectExecutor.execute,
            evaluate: evaluator.execute,
            validateReport: validator.execute,
            now: now
        )
    }

    private func completionPublisher(
        stagedBundleRoot: URL
    ) -> BundleOwnedProductUpdateCompletionPublisher {
        BundleOwnedProductUpdateCompletionPublisher(
            stagedBundleRoot: stagedBundleRoot,
            operations:
                BundleOwnedProductUpdateCompletionPublishOperations(
                    pathState: fileStore.pathState,
                    createDirectory: fileStore.createDirectory,
                    writeData: fileStore.writeData
                )
        )
    }

    private func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
