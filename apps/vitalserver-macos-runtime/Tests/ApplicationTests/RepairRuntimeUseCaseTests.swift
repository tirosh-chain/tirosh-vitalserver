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
}
