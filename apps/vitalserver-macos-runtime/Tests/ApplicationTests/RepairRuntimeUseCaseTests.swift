import Application
import Contracts
import Domain
import XCTest
import Errors

final class RepairRuntimeUseCaseTests: XCTestCase {
    func testPlansVMDiskRepairFromExplicitDiskState() throws {
        let useCase = RepairRuntimeUseCase()

        let plan = try useCase.planVMDiskRepair(for: input(
            rootfsBaseSizeBytes: 2,
            currentVMDiskSizeBytes: 40 * 1024
        ))

        XCTAssertEqual(plan.operation, .repairVMDisk)
        XCTAssertEqual(plan.targetDiskGiB, 40)
        XCTAssertEqual(plan.requiredFreeSpaceBytes, 1036)
        XCTAssertTrue(plan.shouldArchiveCurrentDisk)
        XCTAssertEqual(
            plan.restartPolicy,
            RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: true, restartWatchdog: true)
        )
    }

    func testPlansDefaultSizeWhenCurrentVMDiskIsMissing() throws {
        let useCase = RepairRuntimeUseCase()

        let plan = try useCase.planVMDiskRepair(for: input(currentVMDiskSizeBytes: nil))

        XCTAssertEqual(plan.targetDiskGiB, 32)
        XCTAssertFalse(plan.shouldArchiveCurrentDisk)
    }

    func testRejectsMissingRootfsBaseWithoutCreatingFallbackState() {
        let useCase = RepairRuntimeUseCase()

        XCTAssertThrowsError(try useCase.planVMDiskRepair(for: input(rootfsBaseExists: false))) { error in
            XCTAssertEqual(
                error as? RepairRuntimeUseCaseError,
                .operationFailed("missing file: /runtime/rootfs-base.raw.gz")
            )
        }
    }

    func testRejectsEmptyRootfsBaseAsInvalidInput() {
        let useCase = RepairRuntimeUseCase()

        XCTAssertThrowsError(try useCase.planVMDiskRepair(for: input(rootfsBaseSizeBytes: 0))) { error in
            XCTAssertEqual(
                error as? RepairRuntimeUseCaseError,
                .operationFailed("rootfs base is empty path=/runtime/rootfs-base.raw.gz")
            )
        }
    }

    func testRejectsInvalidDiskUnitInputs() {
        let useCase = RepairRuntimeUseCase()

        XCTAssertThrowsError(try useCase.planVMDiskRepair(for: input(defaultDiskGiB: 0))) { error in
            XCTAssertEqual(
                error as? RepairRuntimeUseCaseError,
                .operationFailed("default VM disk size must be positive")
            )
        }
        XCTAssertThrowsError(try useCase.planVMDiskRepair(for: input(bytesPerGiB: 0))) { error in
            XCTAssertEqual(
                error as? RepairRuntimeUseCaseError,
                .operationFailed("bytes per GiB must be positive")
            )
        }
    }

    func testRejectsRequiredFreeSpaceOverflow() {
        let useCase = RepairRuntimeUseCase()

        XCTAssertThrowsError(try useCase.planVMDiskRepair(for: input(
            rootfsBaseSizeBytes: UInt64.max / 6 + 1
        ))) { error in
            XCTAssertEqual(
                error as? RepairRuntimeUseCaseError,
                .operationFailed("required free space calculation overflowed")
            )
        }
    }

    func testPlansVMDiskExecutionPathsFromExplicitTimestamp() {
        let useCase = RepairRuntimeUseCase()

        let plan = useCase.vmDiskExecutionPlan(
            vmDisk: URL(fileURLWithPath: "/runtime/vm/vm-disk.img"),
            backupsDirectory: URL(fileURLWithPath: "/runtime/backups"),
            timestamp: "2026-06-06T05:10:11Z"
        )

        XCTAssertEqual(plan.temporaryDisk, URL(fileURLWithPath: "/runtime/vm/.vm-disk.img.repair.tmp"))
        XCTAssertEqual(plan.archiveDirectory, URL(fileURLWithPath: "/runtime/backups/vm-disk-repair-20260606T051011Z"))
        XCTAssertEqual(plan.archivedDisk, URL(fileURLWithPath: "/runtime/backups/vm-disk-repair-20260606T051011Z/vm-disk.img"))
    }

    func testPlansVMDiskReplacementBuildCommandsWithoutWorkflowArgumentConstruction() throws {
        let useCase = RepairRuntimeUseCase()
        let vmDisk = URL(fileURLWithPath: "/runtime/vm/vm-disk.img")
        let backupsDirectory = URL(fileURLWithPath: "/runtime/backups")
        let executionPlan = useCase.vmDiskExecutionPlan(
            vmDisk: vmDisk,
            backupsDirectory: backupsDirectory,
            timestamp: "2026-06-06T05:10:11Z"
        )
        let repairPlan = try useCase.planVMDiskRepair(for: input(
            rootfsBaseSizeBytes: 2,
            currentVMDiskSizeBytes: 40 * 1024
        ))

        let buildPlan = useCase.vmDiskReplacementBuildPlan(
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz"),
            vmDisk: vmDisk,
            backupsDirectory: backupsDirectory,
            gunzipExecutable: "/usr/bin/gunzip",
            truncateExecutable: "/usr/bin/truncate",
            repairPlan: repairPlan,
            executionPlan: executionPlan
        )

        XCTAssertEqual(buildPlan.vmDiskDirectory.path, "/runtime/vm")
        XCTAssertEqual(buildPlan.backupsDirectory, backupsDirectory)
        XCTAssertEqual(buildPlan.temporaryDisk, URL(fileURLWithPath: "/runtime/vm/.vm-disk.img.repair.tmp"))
        XCTAssertEqual(buildPlan.freeSpaceDirectory.path, "/runtime/vm")
        XCTAssertEqual(buildPlan.requiredFreeSpaceBytes, 1036)
        XCTAssertEqual(buildPlan.operation, .repairVMDisk)
        XCTAssertEqual(
            buildPlan.decompression,
            RepairRuntimeProcessOutputPlan(
                executable: "/usr/bin/gunzip",
                arguments: ["-c", "/runtime/rootfs-base.raw.gz"],
                output: URL(fileURLWithPath: "/runtime/vm/.vm-disk.img.repair.tmp")
            )
        )
        XCTAssertEqual(
            buildPlan.resize,
            RepairRuntimeProcessPlan(
                executable: "/usr/bin/truncate",
                arguments: ["-s", "40G", "/runtime/vm/.vm-disk.img.repair.tmp"]
            )
        )
    }

    func testReplacementDiskVerificationPreservesMissingAndUndersizedFailures() {
        let useCase = RepairRuntimeUseCase()

        XCTAssertThrowsError(try useCase.requireReplacementDisk(RepairRuntimeVMDiskReplacementObservation(
            path: "/runtime/vm/vm-disk.img",
            exists: false,
            actualBytes: nil,
            targetDiskGiB: 32,
            bytesPerGiB: 1024
        ))) { error in
            XCTAssertEqual(
                error as? RepairRuntimeUseCaseError,
                .operationFailed("vm disk repair replacement missing path=/runtime/vm/vm-disk.img")
            )
        }
        XCTAssertThrowsError(try useCase.requireReplacementDisk(RepairRuntimeVMDiskReplacementObservation(
            path: "/runtime/vm/vm-disk.img",
            exists: true,
            actualBytes: 1024,
            targetDiskGiB: 2,
            bytesPerGiB: 1024
        ))) { error in
            XCTAssertEqual(
                error as? RepairRuntimeUseCaseError,
                .operationFailed("vm disk repair replacement undersized path=/runtime/vm/vm-disk.img expectedBytes=2048 actualBytes=1024")
            )
        }
    }

    func testVMDiskRepairLifecyclePlansKeepOperationMessagesOutOfWorkflow() {
        let useCase = RepairRuntimeUseCase()

        XCTAssertEqual(
            useCase.vmDiskRepairRequestedPlan(),
            RepairRuntimeLoggedStatusPlan(
                logMessage: "vm disk repair requested",
                status: .recovering,
                operation: .repairVMDisk,
                statusMessage: "VM disk repair requested"
            )
        )
        XCTAssertEqual(
            useCase.vmDiskReplacementCreationStatusPlan(),
            RepairRuntimeStatusPlan(
                status: .recovering,
                operation: .repairVMDisk,
                message: "Creating replacement VM disk"
            )
        )
        XCTAssertEqual(
            useCase.vmDiskArchiveStatusPlan(),
            RepairRuntimeStatusPlan(
                status: .recovering,
                operation: .repairVMDisk,
                message: "Archiving current VM disk"
            )
        )
        XCTAssertEqual(
            useCase.vmDiskStartServicesStatusPlan(),
            RepairRuntimeStatusPlan(
                status: .recovering,
                operation: .repairVMDisk,
                message: "Starting runtime services after VM disk repair"
            )
        )
        XCTAssertEqual(
            useCase.vmDiskArchivedLogMessage(archivedDiskPath: "/runtime/backups/vm-disk.img"),
            "archived vm disk path=/runtime/backups/vm-disk.img"
        )
        XCTAssertEqual(
            useCase.vmDiskMissingArchiveLogMessage(),
            "vm disk missing; creating replacement without archive"
        )
        XCTAssertEqual(
            useCase.vmDiskReplacementCreatedLogMessage(vmDiskPath: "/runtime/vm/vm-disk.img", targetDiskGiB: 64),
            "created replacement vm disk path=/runtime/vm/vm-disk.img size=64 GiB"
        )
    }

    func testVMDiskRedisBackupBestEffortPlansReportDegradedContinuationExplicitly() {
        let useCase = RepairRuntimeUseCase()

        XCTAssertEqual(
            useCase.vmDiskRedisBackupStartedStatusPlan(),
            RepairRuntimeStatusPlan(
                status: .recovering,
                operation: .repairVMDisk,
                message: "Creating Redis backup before VM disk repair"
            )
        )
        XCTAssertEqual(
            useCase.vmDiskRedisBackupCompletedPlan(),
            RepairRuntimeLoggedStatusPlan(
                logMessage: "redis backup before vm disk repair completed",
                status: .recovering,
                operation: .repairVMDisk,
                statusMessage: "Redis backup completed before VM disk repair"
            )
        )
        XCTAssertEqual(
            useCase.vmDiskRedisBackupFailedPlan(reason: "permission denied"),
            RepairRuntimeLoggedStatusPlan(
                logMessage: "redis backup before vm disk repair failed error=permission denied; continuing with VM disk archive",
                status: .recovering,
                operation: .repairVMDisk,
                statusMessage: "Redis backup before VM disk repair failed; current VM disk will be archived before replacement"
            )
        )
    }

    func testCompletionMessagesPreserveArchivePresence() {
        let useCase = RepairRuntimeUseCase()

        let withoutArchive = useCase.vmDiskCompletionMessages(archivedDiskPath: nil)
        let withArchive = useCase.vmDiskCompletionMessages(archivedDiskPath: "/runtime/backups/vm-disk.img")

        XCTAssertEqual(withoutArchive.healthy, "VM disk repaired.")
        XCTAssertEqual(withoutArchive.degraded, "VM disk was recreated, but runtime health check failed.")
        XCTAssertEqual(withArchive.healthy, "VM disk repaired. Previous disk archive: /runtime/backups/vm-disk.img")
        XCTAssertEqual(
            withArchive.degraded,
            "VM disk was recreated, but runtime health check failed. Previous disk archive: /runtime/backups/vm-disk.img"
        )
    }

    func testDatastoreRepairPlanBuildsRequestAndRestartPolicyWithoutWorkflowState() {
        let useCase = RepairRuntimeUseCase()

        let plan = useCase.datastoreRepairPlan()
        let request = useCase.datastoreRepairRequest(
            requestID: "request-1",
            requestedAt: "2026-06-06T00:00:00Z"
        )

        XCTAssertEqual(plan.requestedLogMessage, "datastore repair requested")
        XCTAssertEqual(plan.completedStatusMessage, "datastore repair completed")
        XCTAssertEqual(
            plan.restartPolicy,
            RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: true, restartWatchdog: true)
        )
        XCTAssertEqual(request.id, "request-1")
        XCTAssertEqual(request.requestedAt, "2026-06-06T00:00:00Z")
    }

    func testDatastoreRepairWaitPlansPreserveProgressFailedAndTimeoutMeanings() {
        let useCase = RepairRuntimeUseCase()

        XCTAssertEqual(
            useCase.datastoreRepairWaitStartedLogMessage(timeoutSeconds: 300),
            "waiting for datastore repair result timeoutSeconds=300.0"
        )
        XCTAssertEqual(
            useCase.datastoreRepairWaitProgressPlan(message: "waiting for datastore repair guest worker"),
            RepairRuntimeStatusPlan(
                status: .recovering,
                operation: .repairDatastore,
                message: "waiting for datastore repair guest worker"
            )
        )
        XCTAssertEqual(
            useCase.datastoreRepairWaitResultPlan(.completed(message: "done")),
            RepairRuntimeWaitResultPlan(
                logMessage: "datastore repair guest result completed message=done",
                failureMessage: nil
            )
        )
        XCTAssertEqual(
            useCase.datastoreRepairWaitResultPlan(.failed(message: "repair failed")),
            RepairRuntimeWaitResultPlan(
                logMessage: "datastore repair guest result failed message=repair failed",
                failureMessage: "runtime health check failed"
            )
        )
        XCTAssertEqual(
            useCase.datastoreRepairWaitResultPlan(.timedOut),
            RepairRuntimeWaitResultPlan(
                logMessage: nil,
                failureMessage: "runtime health check failed"
            )
        )
    }

    func testRedisBackupResultDecisionPreservesStaleMissingFailedAndDefaultDisplayMessages() {
        let useCase = RepairRuntimeUseCase()

        XCTAssertEqual(
            useCase.redisBackupResultDecision(
                loadResult: .loaded(redisResult(status: .completed, requestId: "old", message: "done")),
                expectedRequestID: "request-1",
                shouldReportProgress: true
            ),
            .ignoreStaleResult(logMessage: "stale redis backup result ignored")
        )
        XCTAssertEqual(
            useCase.redisBackupResultDecision(
                loadResult: .loaded(redisResult(status: .completed, requestId: "request-1", message: nil, archive: "redis.tar.gz")),
                expectedRequestID: "request-1",
                shouldReportProgress: true
            ),
            .completed(message: "Redis backup completed.", archive: "redis.tar.gz")
        )
        XCTAssertEqual(
            useCase.redisBackupResultDecision(
                loadResult: .loaded(redisResult(status: .failed, requestId: "request-1", message: nil)),
                expectedRequestID: "request-1",
                shouldReportProgress: true
            ),
            .failed(message: "Redis backup failed.")
        )
        XCTAssertEqual(
            useCase.redisBackupResultDecision(
                loadResult: .missing,
                expectedRequestID: "request-1",
                shouldReportProgress: true
            ),
            .waiting(logMessage: "waiting for redis backup guest worker")
        )
        XCTAssertEqual(
            useCase.redisBackupResultDecision(
                loadResult: .failed("permission denied"),
                expectedRequestID: "request-1",
                shouldReportProgress: true
            ),
            .readFailed(message: "failed to read redis backup result: permission denied")
        )
    }

    func testRedisBackupLifecyclePlansKeepStatusAndFailureMessagesOutOfWorkflow() {
        let useCase = RepairRuntimeUseCase()

        XCTAssertEqual(
            useCase.redisBackupRequestedPlan(),
            RepairRuntimeLoggedStatusPlan(
                logMessage: "redis backup requested",
                status: .recovering,
                operation: .redisBackup,
                statusMessage: "redis backup requested"
            )
        )
        XCTAssertEqual(useCase.redisBackupCompletedLogMessage(), "redis backup completed")
        XCTAssertEqual(
            useCase.redisBackupTimedOutPlan(),
            RepairRuntimeFailureStatusPlan(
                status: .degraded,
                operation: .redisBackup,
                statusMessage: "redis backup timed out",
                failureMessage: "redis backup timed out"
            )
        )
    }

    private func input(
        rootfsBasePath: String = "/runtime/rootfs-base.raw.gz",
        rootfsBaseExists: Bool = true,
        rootfsBaseSizeBytes: UInt64 = 2,
        currentVMDiskSizeBytes: UInt64? = 4 * 1024,
        defaultDiskGiB: Int = 32,
        bytesPerGiB: UInt64 = 1024,
        freeSpaceMarginBytes: UInt64 = 1024
    ) -> RepairRuntimeVMDiskInput {
        RepairRuntimeVMDiskInput(
            rootfsBasePath: rootfsBasePath,
            rootfsBaseExists: rootfsBaseExists,
            rootfsBaseSizeBytes: rootfsBaseSizeBytes,
            currentVMDiskSizeBytes: currentVMDiskSizeBytes,
            defaultDiskGiB: defaultDiskGiB,
            bytesPerGiB: bytesPerGiB,
            freeSpaceMarginBytes: freeSpaceMarginBytes
        )
    }

    private func redisResult(
        status: DatastoreRepairStatus,
        requestId: String?,
        message: String?,
        archive: String? = nil
    ) -> RedisBackupResultDocument {
        RedisBackupResultDocument(
            requestId: requestId,
            status: status,
            message: message,
            archive: archive
        )
    }
}
