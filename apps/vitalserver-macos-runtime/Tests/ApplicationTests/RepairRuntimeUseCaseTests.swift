import Application
import Contracts
import Domain
import XCTest
import Errors

final class RepairRuntimeUseCaseTests: XCTestCase {
    func testPlansVMDiskRepairFromExplicitDiskState() throws {
        let useCase = RuntimeVMDiskRepairUseCase()

        let plan = try useCase.planRepair(for: input(
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
        let useCase = RuntimeVMDiskRepairUseCase()

        let plan = try useCase.planRepair(for: input(
            currentVMDiskState: .missing,
            currentVMDiskSizeBytes: nil
        ))

        XCTAssertEqual(plan.targetDiskGiB, 32)
        XCTAssertFalse(plan.shouldArchiveCurrentDisk)
    }

    func testRejectsMissingRootfsBaseWithoutCreatingFallbackState() {
        let useCase = RuntimeVMDiskRepairUseCase()

        XCTAssertThrowsError(try useCase.planRepair(for: input(rootfsBaseState: .missing))) { error in
            XCTAssertEqual(
                error as? RepairRuntimeUseCaseError,
                .operationFailed("missing file: /runtime/rootfs-base.raw.gz")
            )
        }
    }

    func testRejectsRootfsBaseInspectionFailureWithoutCreatingFallbackState() {
        let useCase = RuntimeVMDiskRepairUseCase()

        XCTAssertThrowsError(try useCase.planRepair(for: input(
            rootfsBaseState: .inspectFailed("permission denied"),
            rootfsBaseSizeBytes: nil
        ))) { error in
            XCTAssertEqual(
                error as? RepairRuntimeUseCaseError,
                .operationFailed("rootfs base path inspection failed: /runtime/rootfs-base.raw.gz reason=permission denied")
            )
        }
    }

    func testRejectsUnexpectedRootfsBasePathState() {
        let useCase = RuntimeVMDiskRepairUseCase()

        XCTAssertThrowsError(try useCase.planRepair(for: input(
            rootfsBaseState: .directory,
            rootfsBaseSizeBytes: nil
        ))) { error in
            XCTAssertEqual(
                error as? RepairRuntimeUseCaseError,
                .operationFailed("rootfs base path state is unexpected: /runtime/rootfs-base.raw.gz state=directory")
            )
        }
    }

    func testRejectsEmptyRootfsBaseAsInvalidInput() {
        let useCase = RuntimeVMDiskRepairUseCase()

        XCTAssertThrowsError(try useCase.planRepair(for: input(rootfsBaseSizeBytes: 0))) { error in
            XCTAssertEqual(
                error as? RepairRuntimeUseCaseError,
                .operationFailed("rootfs base is empty path=/runtime/rootfs-base.raw.gz")
            )
        }
    }

    func testRejectsInvalidDiskUnitInputs() {
        let useCase = RuntimeVMDiskRepairUseCase()

        XCTAssertThrowsError(try useCase.planRepair(for: input(defaultDiskGiB: 0))) { error in
            XCTAssertEqual(
                error as? RepairRuntimeUseCaseError,
                .operationFailed("default VM disk size must be positive")
            )
        }
        XCTAssertThrowsError(try useCase.planRepair(for: input(bytesPerGiB: 0))) { error in
            XCTAssertEqual(
                error as? RepairRuntimeUseCaseError,
                .operationFailed("bytes per GiB must be positive")
            )
        }
    }

    func testRejectsRequiredFreeSpaceOverflow() {
        let useCase = RuntimeVMDiskRepairUseCase()

        XCTAssertThrowsError(try useCase.planRepair(for: input(
            rootfsBaseSizeBytes: UInt64.max / 6 + 1
        ))) { error in
            XCTAssertEqual(
                error as? RepairRuntimeUseCaseError,
                .operationFailed("required free space calculation overflowed")
            )
        }
    }

    func testPlansVMDiskExecutionPathsFromExplicitTimestamp() {
        let useCase = RuntimeVMDiskRepairUseCase()

        let plan = useCase.executionPlan(
            vmDisk: URL(fileURLWithPath: "/runtime/vm/vm-disk.img"),
            backupsDirectory: URL(fileURLWithPath: "/runtime/backups"),
            timestamp: "2026-06-06T05:10:11Z"
        )

        XCTAssertEqual(plan.temporaryDisk, URL(fileURLWithPath: "/runtime/vm/.vm-disk.img.repair.tmp"))
        XCTAssertEqual(plan.archiveDirectory, URL(fileURLWithPath: "/runtime/backups/vm-disk-repair-20260606T051011Z"))
        XCTAssertEqual(plan.archivedDisk, URL(fileURLWithPath: "/runtime/backups/vm-disk-repair-20260606T051011Z/vm-disk.img"))
    }

    func testPlansVMDiskReplacementBuildInputsWithoutWorkflowArgumentConstruction() throws {
        let useCase = RuntimeVMDiskRepairUseCase()
        let vmDisk = URL(fileURLWithPath: "/runtime/vm/vm-disk.img")
        let backupsDirectory = URL(fileURLWithPath: "/runtime/backups")
        let executionPlan = useCase.executionPlan(
            vmDisk: vmDisk,
            backupsDirectory: backupsDirectory,
            timestamp: "2026-06-06T05:10:11Z"
        )
        let repairPlan = try useCase.planRepair(for: input(
            rootfsBaseSizeBytes: 2,
            currentVMDiskSizeBytes: 40 * 1024
        ))

        let buildPlan = useCase.replacementBuildPlan(
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz"),
            vmDisk: vmDisk,
            backupsDirectory: backupsDirectory,
            repairPlan: repairPlan,
            executionPlan: executionPlan
        )

        XCTAssertEqual(buildPlan.rootfsBase.path, "/runtime/rootfs-base.raw.gz")
        XCTAssertEqual(buildPlan.vmDiskDirectory.path, "/runtime/vm")
        XCTAssertEqual(buildPlan.backupsDirectory, backupsDirectory)
        XCTAssertEqual(buildPlan.temporaryDisk, URL(fileURLWithPath: "/runtime/vm/.vm-disk.img.repair.tmp"))
        XCTAssertEqual(buildPlan.freeSpaceDirectory.path, "/runtime/vm")
        XCTAssertEqual(buildPlan.requiredFreeSpaceBytes, 1036)
        XCTAssertEqual(buildPlan.operation, .repairVMDisk)
        XCTAssertEqual(buildPlan.targetDiskGiB, 40)
    }

    func testReplacementDiskVerificationPreservesMissingAndUndersizedFailures() {
        let useCase = RuntimeVMDiskRepairUseCase()

        XCTAssertThrowsError(try useCase.requireReplacementDisk(RepairRuntimeVMDiskReplacementObservation(
            path: "/runtime/vm/vm-disk.img",
            state: .missing,
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
            state: .file,
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
        let useCase = RuntimeVMDiskRepairUseCase()

        XCTAssertEqual(
            useCase.requestedPlan(),
            RepairRuntimeLoggedStatusPlan(
                logMessage: "vm disk repair requested",
                status: .recovering,
                operation: .repairVMDisk,
                statusMessage: "VM disk repair requested"
            )
        )
        XCTAssertEqual(
            useCase.replacementCreationStatusPlan(),
            RepairRuntimeStatusPlan(
                status: .recovering,
                operation: .repairVMDisk,
                message: "Creating replacement VM disk"
            )
        )
        XCTAssertEqual(
            useCase.archiveStatusPlan(),
            RepairRuntimeStatusPlan(
                status: .recovering,
                operation: .repairVMDisk,
                message: "Archiving current VM disk"
            )
        )
        XCTAssertEqual(
            useCase.startServicesStatusPlan(),
            RepairRuntimeStatusPlan(
                status: .recovering,
                operation: .repairVMDisk,
                message: "Starting runtime services after VM disk repair"
            )
        )
        XCTAssertEqual(
            useCase.archivedLogMessage(archivedDiskPath: "/runtime/backups/vm-disk.img"),
            "archived vm disk path=/runtime/backups/vm-disk.img"
        )
        XCTAssertEqual(
            useCase.missingArchiveLogMessage(),
            "vm disk missing; creating replacement without archive"
        )
        XCTAssertEqual(
            useCase.replacementCreatedLogMessage(vmDiskPath: "/runtime/vm/vm-disk.img", targetDiskGiB: 64),
            "created replacement vm disk path=/runtime/vm/vm-disk.img size=64 GiB"
        )
    }

    func testVMDiskRedisBackupBestEffortPlansReportDegradedContinuationExplicitly() {
        let useCase = RuntimeVMDiskRepairUseCase()

        XCTAssertEqual(
            useCase.redisBackupStartedStatusPlan(),
            RepairRuntimeStatusPlan(
                status: .recovering,
                operation: .repairVMDisk,
                message: "Creating Redis backup before VM disk repair"
            )
        )
        XCTAssertEqual(
            useCase.redisBackupCompletedPlan(),
            RepairRuntimeLoggedStatusPlan(
                logMessage: "redis backup before vm disk repair completed",
                status: .recovering,
                operation: .repairVMDisk,
                statusMessage: "Redis backup completed before VM disk repair"
            )
        )
        XCTAssertEqual(
            useCase.redisBackupFailedPlan(reason: "permission denied"),
            RepairRuntimeLoggedStatusPlan(
                logMessage: "redis backup before vm disk repair failed error=permission denied; continuing with VM disk archive",
                status: .recovering,
                operation: .repairVMDisk,
                statusMessage: "Redis backup before VM disk repair failed; current VM disk will be archived before replacement"
            )
        )
    }

    func testCompletionMessagesPreserveArchivePresence() {
        let useCase = RuntimeVMDiskRepairUseCase()

        let withoutArchive = useCase.completionMessages(archivedDiskPath: nil)
        let withArchive = useCase.completionMessages(archivedDiskPath: "/runtime/backups/vm-disk.img")

        XCTAssertEqual(withoutArchive.healthy, "VM disk repaired.")
        XCTAssertEqual(withoutArchive.degraded, "VM disk was recreated, but runtime health check failed.")
        XCTAssertEqual(withArchive.healthy, "VM disk repaired. Previous disk archive: /runtime/backups/vm-disk.img")
        XCTAssertEqual(
            withArchive.degraded,
            "VM disk was recreated, but runtime health check failed. Previous disk archive: /runtime/backups/vm-disk.img"
        )
    }

    func testDatastoreRepairPlanBuildsRestartPolicyWithoutWorkflowState() {
        let useCase = RuntimeDatastoreRepairUseCase()

        let plan = useCase.plan()

        XCTAssertEqual(plan.requestedLogMessage, "datastore repair requested")
        XCTAssertEqual(plan.completedStatusMessage, "datastore repair completed")
        XCTAssertEqual(
            plan.restartPolicy,
            RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: true, restartWatchdog: true)
        )
    }

    private func input(
        rootfsBasePath: String = "/runtime/rootfs-base.raw.gz",
        rootfsBaseState: RuntimePathState = .file,
        rootfsBaseSizeBytes: UInt64? = 2,
        currentVMDiskState: RuntimePathState? = nil,
        currentVMDiskSizeBytes: UInt64? = 4 * 1024,
        defaultDiskGiB: Int = 32,
        bytesPerGiB: UInt64 = 1024,
        freeSpaceMarginBytes: UInt64 = 1024
    ) -> RepairRuntimeVMDiskInput {
        let resolvedCurrentVMDiskState = currentVMDiskState ?? (currentVMDiskSizeBytes == nil ? .missing : .file)
        return RepairRuntimeVMDiskInput(
            rootfsBasePath: rootfsBasePath,
            rootfsBaseState: rootfsBaseState,
            rootfsBaseSizeBytes: rootfsBaseSizeBytes,
            currentVMDiskState: resolvedCurrentVMDiskState,
            currentVMDiskSizeBytes: currentVMDiskSizeBytes,
            defaultDiskGiB: defaultDiskGiB,
            bytesPerGiB: bytesPerGiB,
            freeSpaceMarginBytes: freeSpaceMarginBytes
        )
    }

}
