import Contracts

public struct RuntimeOperationPlan: Equatable, Sendable {
    public let operation: RuntimeOperation
    public let steps: [RuntimeWorkflowStep]

    public init(operation: RuntimeOperation, steps: [RuntimeWorkflowStep]) throws {
        let invalidSteps = Self.invalidSteps(operation: operation, steps: steps)
        guard invalidSteps.isEmpty else {
            throw RuntimeOperationPlanValidationError(
                operation: operation,
                invalidSteps: invalidSteps
            )
        }

        self.operation = operation
        self.steps = steps
    }

    public var invalidSteps: [RuntimeWorkflowStep] {
        Self.invalidSteps(operation: operation, steps: steps)
    }

    public var isValid: Bool {
        invalidSteps.isEmpty
    }

    public static func invalidSteps(
        operation: RuntimeOperation,
        steps: [RuntimeWorkflowStep]
    ) -> [RuntimeWorkflowStep] {
        steps.filter { !$0.belongs(to: operation) }
    }
}

public enum RuntimeOperationPlans {
    public static let install = try! RuntimeOperationPlan(
        operation: .install,
        steps: [
            .loadInstallSettings,
            .prepareInstallDirectories,
            .prepareHostStateStore,
            .rotateRuntimeLogs,
            .configureGuestRuntimeConfig,
            .prepareInstalledExecutables,
            .provisionVMDisk,
            .configureVMRuntime,
            .createCloudInitSeed,
            .writeInstallRuntimeVersion,
            .configureInstalledPermissions,
            .startInstalledServices,
            .applyStartOnBootPolicy,
            .waitInstallRuntimeHealth,
            .settleInstalledProductRelease,
            .cleanupInstallSettings,
        ]
    )

    public static let installProvision = try! RuntimeOperationPlan(
        operation: .install,
        steps: [
            .loadInstallSettings,
            .prepareInstallDirectories,
            .prepareHostStateStore,
            .rotateRuntimeLogs,
            .configureGuestRuntimeConfig,
            .prepareInstalledExecutables,
            .provisionVMDisk,
            .configureVMRuntime,
            .createCloudInitSeed,
            .writeInstallRuntimeVersion,
            .configureInstalledPermissions,
            .startInstalledServices,
            .applyStartOnBootPolicy,
            .settleInstalledProductRelease,
            .cleanupInstallSettings,
        ]
    )

    public static let applyBundle = try! RuntimeOperationPlan(
        operation: .applyBundle,
        steps: [
            .stopRuntimeServices,
            .replaceRootfsBase,
            .replaceUpdateArtifacts,
            .runMigrations,
            .refreshCloudInitSeed,
            .writeRuntimeVersion,
            .startRuntimeServices,
            .activateGuestUpdate,
            .waitRuntimeHealth,
        ]
    )

    public static func applyBundle(updatesRootfsBase: Bool) -> RuntimeOperationPlan {
        try! RuntimeOperationPlan(
            operation: .applyBundle,
            steps: [
                .stopRuntimeServices,
            ]
                + (updatesRootfsBase ? [.replaceRootfsBase] : [])
                + [
                    .replaceUpdateArtifacts,
                    .runMigrations,
                    .refreshCloudInitSeed,
                    .writeRuntimeVersion,
                    .startRuntimeServices,
                    .activateGuestUpdate,
                    .waitRuntimeHealth,
                ]
        )
    }

    public static let rollback = try! RuntimeOperationPlan(
        operation: .rollback,
        steps: [
            .rollbackStopRuntimeServices,
            .rollbackRestoreRootfsBase,
            .rollbackRestoreRuntimeVersion,
            .rollbackRestoreUpdateArtifacts,
            .rollbackStartRuntimeServices,
            .rollbackWaitRuntimeHealth,
        ]
    )

    public static func rollback(restoresRootfsBase: Bool) -> RuntimeOperationPlan {
        try! RuntimeOperationPlan(
            operation: .rollback,
            steps: [
                .rollbackStopRuntimeServices,
            ]
                + (restoresRootfsBase ? [.rollbackRestoreRootfsBase] : [])
                + [
                    .rollbackRestoreRuntimeVersion,
                    .rollbackRestoreUpdateArtifacts,
                    .rollbackStartRuntimeServices,
                    .rollbackWaitRuntimeHealth,
                ]
        )
    }
}
