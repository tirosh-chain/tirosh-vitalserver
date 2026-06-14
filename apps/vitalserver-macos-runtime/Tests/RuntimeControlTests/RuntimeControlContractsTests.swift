import RuntimeControl
import Contracts
import XCTest
import Errors

final class RuntimeControlContractsTests: XCTestCase {
    func testRuntimeStatePreservesUnknownValues() throws {
        let state = RuntimeState(rawValue: "maintenance")

        XCTAssertEqual(state.rawValue, "maintenance")

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(RuntimeState.self, from: encoded)

        XCTAssertEqual(decoded, .unknown("maintenance"))
    }

    func testRuntimeStatusUsesTypedOperationAndRoundTripsThroughJSON() throws {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            vmServiceState: .loaded,
            proxyServiceState: .loaded,
            watchdogServiceState: .loaded,
            runtimeState: .healthy,
            operation: .applyBundle,
            readIssues: [RuntimeStatusReadIssue(source: "hostProxyHTTP", message: "exitCode=28 stderr=timeout")],
            vmState: .running,
            vmErrors: [],
            vmIP: "192.168.64.2",
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )

        XCTAssertTrue(RuntimeReadinessPolicy.isReady(status))

        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(RuntimeStatus.self, from: encoded)

        XCTAssertEqual(decoded.operation, .applyBundle)
        XCTAssertEqual(decoded.readIssues, [
            RuntimeStatusReadIssue(source: "hostProxyHTTP", message: "exitCode=28 stderr=timeout"),
        ])
        XCTAssertEqual(decoded.vmState, .running)
        XCTAssertEqual(decoded.vmErrors ?? [], [])
        XCTAssertEqual(decoded.runtimeInstallationState, .executable)
        XCTAssertEqual(decoded.effectiveRuntimeInstallationState, .executable)
        XCTAssertEqual(decoded.vmServiceState, .loaded)
        XCTAssertEqual(decoded.proxyServiceState, .loaded)
        XCTAssertEqual(decoded.watchdogServiceState, .loaded)
        XCTAssertTrue(RuntimeReadinessPolicy.isReady(decoded))
    }

    func testRuntimeStatusDecodesLegacyRuntimeInstallationStateFromInstalledBool() throws {
        let legacyInstalled = try JSONDecoder().decode(RuntimeStatus.self, from: Data("""
        {
          "runtimeInstalled": true,
          "vmServiceLoaded": false,
          "proxyServiceLoaded": false,
          "guestLogSyncServiceLoaded": false,
          "watchdogServiceLoaded": false,
          "readIssues": [],
          "failureReasons": []
        }
        """.utf8))
        let legacyMissing = RuntimeStatus(runtimeInstalled: false)

        XCTAssertNil(legacyInstalled.runtimeInstallationState)
        XCTAssertEqual(legacyInstalled.effectiveRuntimeInstallationState, .executable)
        XCTAssertEqual(legacyMissing.effectiveRuntimeInstallationState, .missing)
    }

    func testRuntimeSettingsReadPolicyAppliesVMConfigWithoutReadingHostState() {
        let settings = RuntimeSettingsReadPolicy.applyVMConfig(
            RuntimeVMConfigSettingsReadInput(
                cpuCount: 4,
                memoryMiB: 512,
                networkMode: "bridged",
                bridgedInterface: nil,
                vitalFilesDirectoryHostPath: "/Volumes/Vital Files",
                autoRecoveryEnabled: nil,
                preventSystemSleep: false
            ),
            to: RuntimeSettings()
        )

        XCTAssertEqual(settings.cpuCount, 4)
        XCTAssertEqual(settings.memoryGiB, 1)
        XCTAssertEqual(settings.networkMode, .bridged)
        XCTAssertNil(settings.bridgedInterface)
        XCTAssertEqual(settings.vitalFilesDirectory, "/Volumes/Vital Files")
        XCTAssertTrue(settings.autoRecoveryEnabled)
        XCTAssertFalse(settings.preventSystemSleep)
        XCTAssertEqual(settings.readIssues, [
            RuntimeSettingsReadIssue(
                source: "vmConfig.network.bridgedInterface",
                message: "bridgedInterface is missing for bridged network mode"
            ),
            RuntimeSettingsReadIssue(
                source: "vmConfig.autoRecoveryEnabled",
                message: "autoRecoveryEnabled is missing"
            ),
        ])
    }

    func testRuntimeSettingsReadPolicyClampsGuestRetentionAsExplicitReadIssue() {
        let settings = RuntimeSettingsReadPolicy.applyGuestRuntimeSettings(
            RuntimeGuestRuntimeSettingsReadInput(
                vitalServerURL: "https://settings.example.test/",
                remoteConsoleURL: "https://console.settings.example.test/",
                publicHost: "settings.example.test",
                publicPort: 8443,
                redisBackupRetentionCount: 31
            ),
            to: RuntimeSettings()
        )

        XCTAssertEqual(settings.vitalServerURL, "https://settings.example.test/")
        XCTAssertEqual(settings.remoteConsoleURL, "https://console.settings.example.test/")
        XCTAssertEqual(settings.publicHost, "settings.example.test")
        XCTAssertEqual(settings.publicPort, 8443)
        XCTAssertEqual(settings.redisBackupRetentionCount, 30)
        XCTAssertEqual(settings.readIssues, [
            RuntimeSettingsReadIssue(
                source: "guestRuntimeSettings.redisBackupRetentionCount",
                message: "redisBackupRetentionCount is out of range: 31"
            ),
        ])
    }

    func testRuntimeSettingsReadPolicyAssemblesSettingsFromExplicitSnapshot() {
        let settings = RuntimeSettingsReadPolicy.settings(from: RuntimeSettingsReadSnapshot(
            vmConfig: .loaded(RuntimeVMConfigSettingsReadInput(
                cpuCount: 4,
                memoryMiB: 4096,
                networkMode: "shared",
                bridgedInterface: "en0",
                vitalFilesDirectoryHostPath: "/Volumes/Vital Files",
                autoRecoveryEnabled: false,
                preventSystemSleep: false
            )),
            diskGiB: .loaded(32),
            guestRuntimeSettings: .loaded(RuntimeGuestRuntimeSettingsReadInput(
                vitalServerURL: "https://vitaldb.example.test/",
                remoteConsoleURL: "https://console.example.test/",
                publicHost: "example.test",
                publicPort: 8443,
                redisBackupRetentionCount: 12
            )),
            proxyPort: .loaded(19090),
            startOnBoot: .loaded(false)
        ))

        XCTAssertEqual(settings.readIssues, [])
        XCTAssertEqual(settings.cpuCount, 4)
        XCTAssertEqual(settings.memoryGiB, 4)
        XCTAssertEqual(settings.diskGiB, 32)
        XCTAssertEqual(settings.minimumDiskGiB, 32)
        XCTAssertEqual(settings.vitalFilesDirectory, "/Volumes/Vital Files")
        XCTAssertEqual(settings.vitalServerURL, "https://vitaldb.example.test/")
        XCTAssertEqual(settings.remoteConsoleURL, "https://console.example.test/")
        XCTAssertEqual(settings.publicHost, "example.test")
        XCTAssertEqual(settings.publicPort, 8443)
        XCTAssertEqual(settings.redisBackupRetentionCount, 12)
        XCTAssertEqual(settings.proxyPort, 19090)
        XCTAssertFalse(settings.startOnBoot)
        XCTAssertTrue(settings.startOnBootConfigurable)
        XCTAssertFalse(settings.autoRecoveryEnabled)
        XCTAssertFalse(settings.preventSystemSleep)
    }

    func testRuntimeSettingsReadPolicyKeepsSavedAndAppliedVMSettingsDistinct() {
        let settings = RuntimeSettingsReadPolicy.settings(from: RuntimeSettingsReadSnapshot(
            vmConfig: .loaded(RuntimeVMConfigSettingsReadInput(
                cpuCount: 8,
                memoryMiB: 8192,
                networkMode: "shared",
                bridgedInterface: nil,
                vitalFilesDirectoryHostPath: "/Volumes/New Vital Files",
                autoRecoveryEnabled: true,
                preventSystemSleep: true
            )),
            appliedVMConfig: .loaded(RuntimeVMConfigSettingsReadInput(
                cpuCount: 4,
                memoryMiB: 4096,
                networkMode: "shared",
                bridgedInterface: nil,
                vitalFilesDirectoryHostPath: "/Volumes/Applied Vital Files",
                autoRecoveryEnabled: true,
                preventSystemSleep: true
            )),
            diskGiB: .loaded(32),
            guestRuntimeSettings: .missing,
            proxyPort: .missing,
            startOnBoot: .missing
        ))

        XCTAssertEqual(settings.vitalFilesDirectory, "/Volumes/New Vital Files")
        XCTAssertEqual(settings.runtimeAppliedSettings.vitalFilesDirectory, "/Volumes/Applied Vital Files")
        XCTAssertEqual(settings.runtimeAppliedSettings.cpuCount, 4)
        XCTAssertEqual(settings.runtimeAppliedSettings.memoryGiB, 4)
    }

    func testRuntimeSettingsReadPolicyPreservesMissingAndFailedSnapshotMeanings() {
        let settings = RuntimeSettingsReadPolicy.settings(from: RuntimeSettingsReadSnapshot(
            vmConfig: .missing,
            appliedVMConfig: .failed("applied config denied"),
            diskGiB: .failed("disk size denied"),
            guestRuntimeSettings: .missing,
            proxyPort: .failed("proxy plist denied"),
            startOnBoot: .failed("launchctl denied")
        ))

        XCTAssertEqual(settings.diskGiB, RuntimeSettings().diskGiB)
        XCTAssertEqual(settings.proxyPort, RuntimeSettings().proxyPort)
        XCTAssertFalse(settings.startOnBootConfigurable)
        XCTAssertEqual(settings.readIssues, [
            RuntimeSettingsReadIssue(source: "vmDisk", message: "disk size denied"),
            RuntimeSettingsReadIssue(source: "appliedVMConfig", message: "applied config denied"),
            RuntimeSettingsReadIssue(source: "guestRuntimeSettings", message: "runtime settings document is missing"),
            RuntimeSettingsReadIssue(source: "proxyLaunchDaemon", message: "proxy plist denied"),
            RuntimeSettingsReadIssue(source: "startOnBoot", message: "launchctl denied"),
        ])
    }

    func testRuntimeLogExportManifestStatusValuesPreserveMissingFailedAndIncludedMeanings() throws {
        XCTAssertEqual(
            RuntimeLogExportManifest.SupplementalItem.statusValue(
                sourcePresent: false,
                included: false,
                error: nil
            ),
            "missing"
        )
        XCTAssertEqual(
            RuntimeLogExportManifest.SupplementalItem.statusValue(
                sourcePresent: true,
                included: false,
                error: nil
            ),
            "not-included"
        )
        XCTAssertEqual(
            RuntimeLogExportManifest.SupplementalItem.statusValue(
                sourcePresent: true,
                included: false,
                error: "permission denied"
            ),
            "failed"
        )
        XCTAssertEqual(
            RuntimeLogExportManifest.SupplementalItem.statusValue(
                sourcePresent: true,
                included: true,
                error: "late cleanup issue"
            ),
            "included"
        )

        XCTAssertEqual(
            RuntimeLogExportManifest.RotatedSupplementalSet.statusValue(
                sourcePresent: false,
                copiedCount: 0,
                error: nil
            ),
            "missing"
        )
        XCTAssertEqual(
            RuntimeLogExportManifest.RotatedSupplementalSet.statusValue(
                sourcePresent: true,
                copiedCount: 0,
                error: nil
            ),
            "no-matching-files"
        )
        XCTAssertEqual(
            RuntimeLogExportManifest.RotatedSupplementalSet.statusValue(
                sourcePresent: true,
                copiedCount: 0,
                error: "list failed"
            ),
            "failed"
        )
        XCTAssertEqual(
            RuntimeLogExportManifest.RotatedSupplementalSet.statusValue(
                sourcePresent: true,
                copiedCount: 2,
                error: nil
            ),
            "included"
        )
    }

    func testRuntimeLogExportSourceContractOwnsBundleRelativeDestinations() {
        let destinations = Set(RuntimeLogExportSourceContract.supplementalDestinations().map(\.relativeDestination))
        let rotated = RuntimeLogExportSourceContract.rotatedSupplementalDestinations()

        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeFileNames.runtimeStatus)"))
        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeFileNames.runtimeOperationLease)"))
        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeFileNames.runtimeEvents)"))
        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeFileNames.runtimeObservabilityDB)"))
        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeFileNames.runtimeObservabilityDB)-wal"))
        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeFileNames.runtimeObservabilityDB)-shm"))
        XCTAssertTrue(destinations.contains("diagnostics/guest/\(RuntimeFileNames.runtimeState)"))
        XCTAssertTrue(destinations.contains("diagnostics/runtime/\(RuntimeFileNames.vmLifecycle)"))
        XCTAssertTrue(destinations.contains("diagnostics/guest/\(RuntimeFileNames.vmIP)"))
        XCTAssertTrue(destinations.contains("diagnostics/runtime/vm-config.json"))
        XCTAssertTrue(destinations.contains("diagnostics/runtime/runtime-version.json"))
        XCTAssertTrue(destinations.contains("diagnostics/guest/runtime-config.json"))
        XCTAssertTrue(destinations.contains("diagnostics/host/ai.tirosh.vitalserver.helper.proxy.plist"))
        XCTAssertTrue(destinations.contains("diagnostics/host/vitalserver-nginx.conf"))
        XCTAssertTrue(destinations.contains("guest/guest-observability"))
        XCTAssertTrue(destinations.contains("helper-message.log"))

        let runtimeEventSet = rotated.first { $0.sourceID == .runtimeEvents }
        XCTAssertEqual(runtimeEventSet?.sourceFilePrefix, "\(RuntimeFileNames.runtimeEvents).")
        XCTAssertEqual(runtimeEventSet?.relativeDestinationDirectory, "diagnostics/status")
        XCTAssertEqual(runtimeEventSet?.destinationFilePrefix, "\(RuntimeFileNames.runtimeEvents).")
    }

    func testRuntimeLogCollectionSourceContractOwnsProductLogNamesAndArchivePrefixes() {
        let files = RuntimeLogCollectionSourceContract.fileCopies()
        let runtimeLauncher = files.first { $0.sourceID == .launcherLog }
        let bootstrap = files.first { $0.sourceID == .bootstrapLog }
        let command = files.first { $0.sourceID == .commandLog }
        let directories = RuntimeLogCollectionSourceContract.directoryCopies()
        let rotated = RuntimeLogCollectionSourceContract.rotatedCopies()

        XCTAssertEqual(runtimeLauncher?.sourceFileName, "launcher.log")
        XCTAssertEqual(runtimeLauncher?.destinationScope, .runtimeLogs)
        XCTAssertEqual(runtimeLauncher?.destinationFileName, "launcher.log")
        XCTAssertEqual(runtimeLauncher?.archivePrefix, "runtime-launcher.log")

        XCTAssertEqual(bootstrap?.sourceFileName, RuntimeFileNames.bootstrapLog)
        XCTAssertEqual(bootstrap?.destinationScope, .guestLogs)
        XCTAssertEqual(bootstrap?.destinationFileName, RuntimeFileNames.bootstrapLog)
        XCTAssertEqual(bootstrap?.archivePrefix, "guest-bootstrap.log")

        XCTAssertEqual(command?.sourceFileName, RuntimeFileNames.managerCommandLog)
        XCTAssertEqual(command?.destinationScope, .productLogs)
        XCTAssertEqual(command?.destinationFileName, "command.log")
        XCTAssertEqual(command?.archivePrefix, "command.log")

        XCTAssertEqual(directories.first?.sourceID, .guestObservability)
        XCTAssertEqual(directories.first?.destinationScope, .guestLogs)
        XCTAssertEqual(directories.first?.destinationDirectoryName, "guest-observability")

        XCTAssertEqual(rotated.first?.sourceID, .containerLogs)
        XCTAssertEqual(rotated.first?.sourceFilePrefix, "container-logs.log.")
        XCTAssertEqual(rotated.first?.destinationScope, .guestLogs)
        XCTAssertEqual(rotated.first?.destinationFilePrefix, "container-logs.log.")
        XCTAssertEqual(rotated.first?.archivePrefix, "guest-container-logs.log.")
    }

    func testRuntimeLogCollectionSourceContractMapsReadableLogSources() {
        XCTAssertEqual(
            RuntimeLogCollectionSourceContract.fileCopy(for: .launcher)?.sourceID,
            .launcherLog
        )
        XCTAssertEqual(
            RuntimeLogCollectionSourceContract.fileCopy(for: .vmLaunchOutput)?.sourceID,
            .launchdOutputLog
        )
        XCTAssertEqual(
            RuntimeLogCollectionSourceContract.fileCopy(for: .vmLaunchError)?.sourceID,
            .launchdErrorLog
        )
        XCTAssertEqual(
            RuntimeLogCollectionSourceContract.fileCopy(for: .proxyError)?.sourceID,
            .proxyErrorLog
        )
        XCTAssertEqual(
            RuntimeLogCollectionSourceContract.fileCopy(for: .watchdog)?.sourceID,
            .watchdogOutputLog
        )
        XCTAssertEqual(
            RuntimeLogCollectionSourceContract.fileCopy(for: .containers)?.sourceID,
            .containerLog
        )
        XCTAssertNil(RuntimeLogCollectionSourceContract.fileCopy(for: .helperMessage))
        XCTAssertNil(RuntimeLogCollectionSourceContract.fileCopy(for: .install))
    }

    func testRuntimeLogCollectionDecisionRulesUseExplicitInputsWithoutHostState() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let rules = RuntimeLogCollectionDecisionRules(calendar: calendar)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertTrue(rules.shouldRefreshTarget(RuntimeLogCollectionRefreshTargetInput(
            sourceID: .launcher,
            destinationFileName: "launcher.log"
        )))
        XCTAssertFalse(rules.shouldRefreshTarget(RuntimeLogCollectionRefreshTargetInput(
            sourceID: .launcher,
            destinationFileName: "proxy.err.log"
        )))
        XCTAssertFalse(rules.shouldRefreshTarget(RuntimeLogCollectionRefreshTargetInput(
            sourceID: .install,
            destinationFileName: "install.log"
        )))
        XCTAssertTrue(rules.shouldRefreshCopy(RuntimeLogCollectionCopyRefreshInput(
            destinationPresent: false,
            rotationRequired: false,
            sourceSize: 0,
            destinationSize: 0,
            sourceModificationDate: now,
            destinationModificationDate: now
        )))
        XCTAssertFalse(rules.shouldRefreshCopy(RuntimeLogCollectionCopyRefreshInput(
            destinationPresent: true,
            rotationRequired: false,
            sourceSize: 10,
            destinationSize: 10,
            sourceModificationDate: now,
            destinationModificationDate: now
        )))
        XCTAssertTrue(rules.shouldRotateCentralLog(RuntimeLogCollectionRotationInput(
            destinationPresent: true,
            fileSize: 10,
            modificationDate: now.addingTimeInterval(-86_400),
            now: now,
            maxCentralLogBytes: 100
        )))
        XCTAssertTrue(rules.canAppendCopy(RuntimeLogCollectionAppendInput(
            destinationPresent: true,
            sourceSize: 12,
            destinationSize: 6,
            sourceMatchesDestinationTail: true
        )))
    }

    func testRuntimeTestKitSessionStatePolicyPreservesActiveAndTerminalMeanings() {
        XCTAssertTrue(RuntimeTestKitSessionStatePolicy.isActive(" running "))
        XCTAssertTrue(RuntimeTestKitSessionStatePolicy.isActive("PAUSED"))
        XCTAssertTrue(RuntimeTestKitSessionStatePolicy.isActive("starting"))
        XCTAssertTrue(RuntimeTestKitSessionStatePolicy.isActive("stopping"))
        XCTAssertFalse(RuntimeTestKitSessionStatePolicy.isActive("stopped"))
        XCTAssertFalse(RuntimeTestKitSessionStatePolicy.isActive("failed"))

        XCTAssertTrue(RuntimeTestKitSessionStatePolicy.isTerminal(" stopped "))
        XCTAssertTrue(RuntimeTestKitSessionStatePolicy.isTerminal("FAILED"))
        XCTAssertFalse(RuntimeTestKitSessionStatePolicy.isTerminal("running"))

        let sessions = [
            runtimeTestKitSession(id: "done", state: "stopped"),
            runtimeTestKitSession(id: "active", state: "paused"),
            runtimeTestKitSession(id: "later", state: "running"),
        ]

        XCTAssertEqual(RuntimeTestKitSessionStatePolicy.preferredActiveSession(from: sessions)?.id, "active")
    }

    func testReadinessDoesNotInferServiceStateFromLegacyLoadedBools() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            vmIP: "192.168.64.2",
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )

        XCTAssertFalse(RuntimeReadinessPolicy.isReady(status))
    }

    func testActiveOperationPolicyTreatsNonTerminalUpdateProgressAsInProgress() {
        let status = RuntimeStatus(
            runtimeState: .healthy,
            operation: .health,
            progress: RuntimeProgressDocument(
                operation: .applyBundle,
                phase: .running,
                step: nil,
                stepStatus: nil,
                message: "applying",
                reasonCodes: [],
                startedAt: nil,
                updatedAt: "2026-06-08T00:00:00Z"
            )
        )

        XCTAssertTrue(RuntimeActiveOperationPolicy.isUpdateInProgress(status))
    }

    func testActiveOperationPolicyTreatsNonTerminalInstallProgressAsInProgress() {
        let status = RuntimeStatus(
            runtimeState: .installing,
            operation: .status,
            progress: RuntimeProgressDocument(
                operation: .install,
                phase: .running,
                step: nil,
                stepStatus: nil,
                message: "installing",
                reasonCodes: [],
                startedAt: nil,
                updatedAt: "2026-06-08T00:00:00Z"
            )
        )

        XCTAssertTrue(RuntimeActiveOperationPolicy.isInstallInProgress(status))
    }

    func testActiveOperationPolicyDoesNotTreatTerminalProgressAsInProgress() {
        let status = RuntimeStatus(
            runtimeState: .healthy,
            operation: .applyBundle,
            progress: RuntimeProgressDocument(
                operation: .applyBundle,
                phase: .completed,
                step: nil,
                stepStatus: nil,
                message: "completed",
                reasonCodes: [],
                startedAt: nil,
                updatedAt: "2026-06-08T00:00:00Z"
            )
        )

        XCTAssertFalse(RuntimeActiveOperationPolicy.isUpdateInProgress(status))
    }

    func testActiveOperationPolicyTreatsNonTerminalRestoreProgressAsRecoveryInProgress() {
        let status = RuntimeStatus(
            runtimeState: .critical,
            operation: .watchdog,
            progress: RuntimeProgressDocument(
                operation: .runtimeDataRestore,
                phase: .running,
                step: nil,
                stepStatus: nil,
                message: "restoring",
                reasonCodes: [],
                startedAt: nil,
                updatedAt: "2026-06-13T10:14:07Z"
            )
        )

        XCTAssertTrue(RuntimeActiveOperationPolicy.isRecoveryInProgress(status))
    }

    func testActiveOperationPolicyDoesNotTreatTerminalRestoreProgressAsRecoveryInProgress() {
        let status = RuntimeStatus(
            runtimeState: .critical,
            operation: .runtimeDataRestore,
            progress: RuntimeProgressDocument(
                operation: .runtimeDataRestore,
                phase: .completed,
                step: nil,
                stepStatus: nil,
                message: "restored",
                reasonCodes: [],
                startedAt: nil,
                updatedAt: "2026-06-13T10:14:07Z"
            )
        )

        XCTAssertFalse(RuntimeActiveOperationPolicy.isRecoveryInProgress(status))
    }

    func testActiveOperationPolicyDoesNotTreatTerminalInstallProgressAsInProgress() {
        let status = RuntimeStatus(
            runtimeState: .installing,
            operation: .install,
            progress: RuntimeProgressDocument(
                operation: .install,
                phase: .completed,
                step: nil,
                stepStatus: nil,
                message: "completed",
                reasonCodes: [],
                startedAt: nil,
                updatedAt: "2026-06-08T00:00:00Z"
            )
        )

        XCTAssertFalse(RuntimeActiveOperationPolicy.isInstallInProgress(status))
    }

    func testActiveOperationPolicyFallsBackToRuntimeStateForLegacyStatusWithoutProgress() {
        let updating = RuntimeStatus(runtimeState: .updating, operation: .applyBundle)
        let recoveringUpdate = RuntimeStatus(runtimeState: .recovering, operation: .activateGuestUpdate)
        let recoveringRollback = RuntimeStatus(runtimeState: .recovering, operation: .rollback)
        let healthy = RuntimeStatus(runtimeState: .healthy, operation: .applyBundle)
        let nonUpdate = RuntimeStatus(runtimeState: .updating, operation: .repairVMDisk)

        XCTAssertTrue(RuntimeActiveOperationPolicy.isUpdateInProgress(updating))
        XCTAssertFalse(RuntimeActiveOperationPolicy.isUpdateInProgress(recoveringUpdate))
        XCTAssertTrue(RuntimeActiveOperationPolicy.isRecoveryInProgress(recoveringUpdate))
        XCTAssertTrue(RuntimeActiveOperationPolicy.isRecoveryInProgress(recoveringRollback))
        XCTAssertFalse(RuntimeActiveOperationPolicy.isUpdateInProgress(healthy))
        XCTAssertFalse(RuntimeActiveOperationPolicy.isUpdateInProgress(nonUpdate))
    }

    func testActiveOperationPolicyTreatsInitializingRuntimeStateAsInitializationInProgress() {
        let initializing = RuntimeStatus(runtimeState: .initializing, operation: .install)

        XCTAssertFalse(RuntimeActiveOperationPolicy.isInstallInProgress(initializing))
        XCTAssertTrue(RuntimeActiveOperationPolicy.isInitializationInProgress(initializing))
    }

    func testActiveOperationPolicyDoesNotInferInstallProgressFromLegacyDegradedInstall() {
        let installing = RuntimeStatus(runtimeState: .degraded, operation: .install)
        let degradedWithoutInstallOperation = RuntimeStatus(runtimeState: .degraded, operation: .health)

        XCTAssertFalse(RuntimeActiveOperationPolicy.isInstallInProgress(installing))
        XCTAssertFalse(RuntimeActiveOperationPolicy.isInstallInProgress(degradedWithoutInstallOperation))
    }

    func testActiveOperationPolicyUsesInitializingStatusForProvisionedInstallState() {
        let status = RuntimeStatus(
            runtimeState: .initializing,
            operation: .watchdog,
            installStateDocument: RuntimeInstallStateDocument(
                state: .provisioned,
                mode: .provision,
                updatedAt: "2026-06-09T14:06:25Z",
                message: "runtime install provisioned"
            )
        )

        XCTAssertFalse(RuntimeActiveOperationPolicy.isInstallInProgress(status))
        XCTAssertTrue(RuntimeActiveOperationPolicy.isInitializationInProgress(status))
    }

    func testActiveOperationPolicyStopsUsingProvisionedInstallStateAfterRuntimeIsReady() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            vmServiceState: .loaded,
            proxyServiceState: .loaded,
            watchdogServiceState: .loaded,
            runtimeState: .healthy,
            operation: .health,
            installStateDocument: RuntimeInstallStateDocument(
                state: .provisioned,
                mode: .provision,
                updatedAt: "2026-06-09T14:06:25Z",
                message: "runtime install provisioned"
            ),
            vmIP: "192.168.64.2",
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )

        XCTAssertFalse(RuntimeActiveOperationPolicy.isInstallInProgress(status))
        XCTAssertFalse(RuntimeActiveOperationPolicy.isInitializationInProgress(status))
    }

    func testActiveOperationPolicyTreatsCompletedInstallStateDocumentAsTerminal() {
        let status = RuntimeStatus(
            runtimeState: .degraded,
            operation: .watchdog,
            installStateDocument: RuntimeInstallStateDocument(
                state: .completed,
                mode: .full,
                updatedAt: "2026-06-09T14:06:25Z",
                message: "runtime install completed"
            )
        )

        XCTAssertFalse(RuntimeActiveOperationPolicy.isInstallInProgress(status))
    }

    func testRuntimeStatusIncludesDataDirectoryStats() throws {
        let status = RuntimeStatus(
            dataStorageError: "volume read failed",
            dataDirectoryStats: RuntimeDataDirectoryStats(fileCount: 2, sizeBytes: 1024)
        )

        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(RuntimeStatus.self, from: encoded)

        XCTAssertEqual(decoded.dataStorageError, "volume read failed")
        XCTAssertEqual(decoded.dataDirectoryStats?.fileCount, 2)
        XCTAssertEqual(decoded.dataDirectoryStats?.sizeBytes, 1024)
    }

    func testRuntimeEventCursorWireCodecRoundTripsOpaqueCursor() {
        let cursor = RuntimeEventCursor(timestamp: "2026-05-24T00:01:00Z", id: "event-2")

        let encoded = RuntimeEventCursorWireCodec.encode(cursor)
        let decoded = RuntimeEventCursorWireCodec.decode(encoded)

        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
        XCTAssertEqual(decoded, cursor)
    }

    func testRuntimeEventHistoryIncludesOptionalReadMetadata() throws {
        let history = RuntimeEventHistory(
            events: [],
            nextCursor: "opaque-cursor",
            matchingCount: 3,
            readError: "sqlite=read failed"
        )

        let encoded = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(RuntimeEventHistory.self, from: encoded)
        let legacy = try JSONDecoder().decode(RuntimeEventHistory.self, from: Data("""
        {
          "events": [],
          "nextCursor": "legacy-cursor",
          "matchingCount": 0,
          "readError": "legacy read failed"
        }
        """.utf8))

        XCTAssertEqual(decoded.state, .readFailed)
        XCTAssertEqual(decoded.nextCursor, "opaque-cursor")
        XCTAssertEqual(decoded.matchingCount, 3)
        XCTAssertEqual(decoded.readError, "sqlite=read failed")
        XCTAssertEqual(legacy.state, .readFailed)
        XCTAssertEqual(legacy.nextCursor, "legacy-cursor")
        XCTAssertEqual(legacy.readError, "legacy read failed")
    }

    func testRuntimeCommandResultPreservesOutputIssuesAndDecodesLegacyPayload() throws {
        let result = RuntimeCommandResult(
            exitCode: 1,
            stdout: "",
            stderr: "",
            outputIssues: [
                RuntimeCommandOutputIssue(
                    stream: .stderr,
                    message: "command stderr is not valid UTF-8"
                ),
            ]
        )
        let launchFailure = RuntimeCommandResult(
            exitCode: 1,
            stdout: "",
            stderr: "launch denied",
            executionIssue: RuntimeProcessExecutionIssue(
                kind: .processLaunchFailed,
                message: "launch denied"
            )
        )

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(RuntimeCommandResult.self, from: encoded)
        let decodedLaunchFailure = try JSONDecoder().decode(
            RuntimeCommandResult.self,
            from: JSONEncoder().encode(launchFailure)
        )
        let legacy = try JSONDecoder().decode(RuntimeCommandResult.self, from: Data("""
        {
          "exitCode": 0,
          "stdout": "ok",
          "stderr": ""
        }
        """.utf8))

        XCTAssertEqual(decoded.outputIssues, result.outputIssues)
        XCTAssertEqual(decoded.executionIssue, nil)
        XCTAssertEqual(decodedLaunchFailure.executionIssue, launchFailure.executionIssue)
        XCTAssertEqual(legacy.outputIssues, [])
        XCTAssertEqual(legacy.executionIssue, nil)
    }

    func testRuntimeTestKitStatusPreservesReadIssuesAndDecodesLegacyPayload() throws {
        let status = RuntimeTestKitStatus(
            enabled: true,
            state: .failed,
            lastError: "TestKit failed",
            readIssues: [
                RuntimeTestKitReadIssue(source: "containerAPI", message: "read failed"),
            ]
        )

        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(RuntimeTestKitStatus.self, from: encoded)
        let legacy = try JSONDecoder().decode(RuntimeTestKitStatus.self, from: Data("""
        {
          "enabled": true,
          "state": "running",
          "sessions": [],
          "beds": []
        }
        """.utf8))

        XCTAssertEqual(decoded.readIssues, status.readIssues)
        XCTAssertEqual(legacy.readIssues, [])
    }

    func testRuntimeTestKitAvailabilityPolicyPreservesMissingServiceObservationAsReadIssues() {
        let message = RuntimeTestKitAvailabilityPolicy.unavailableMessage(
            for: nil,
            serviceName: "testkit",
            apiBaseURL: "http://127.0.0.1:18322",
            healthIssue: "connection refused"
        )
        let issues = RuntimeTestKitAvailabilityPolicy.unavailableReadIssues(
            for: nil,
            serviceName: "testkit",
            message: message,
            healthIssue: "connection refused"
        )

        XCTAssertEqual(RuntimeTestKitAvailabilityPolicy.unavailableState(for: nil), .stopped)
        XCTAssertEqual(
            message,
            "TestKit container is not running. TestKit is optional and does not affect VitalServer. Health check: connection refused."
        )
        XCTAssertEqual(issues, [
            RuntimeTestKitReadIssue(source: "testKitAPI", message: message),
            RuntimeTestKitReadIssue(source: "testKitAPI.health", message: "connection refused"),
            RuntimeTestKitReadIssue(
                source: "containerService",
                message: "TestKit container service observation is missing for testkit."
            ),
        ])
    }

    func testRuntimeTestKitAvailabilityPolicyMapsExplicitContainerStateWithoutIO() {
        let service = RuntimeContainerServiceObservation(
            service: "testkit",
            state: "running",
            health: nil
        )
        let status = RuntimeStatus(
            containerObservation: RuntimeContainerObservation(
                auditProxyHTTP: "200",
                auditProxyStatus: nil,
                containerLogsPresent: true,
                containerLogsBytes: 128,
                composeServices: [service]
            )
        )
        let selected = RuntimeTestKitAvailabilityPolicy.service(in: status, serviceName: "testkit")
        let message = RuntimeTestKitAvailabilityPolicy.unavailableMessage(
            for: selected,
            serviceName: "testkit",
            apiBaseURL: "http://127.0.0.1:18322",
            healthIssue: nil
        )
        let issues = RuntimeTestKitAvailabilityPolicy.unavailableReadIssues(
            for: selected,
            serviceName: "testkit",
            message: message,
            healthIssue: nil
        )

        XCTAssertEqual(selected, service)
        XCTAssertEqual(RuntimeTestKitAvailabilityPolicy.unavailableState(for: selected), .starting)
        XCTAssertEqual(
            message,
            "TestKit container API is not reachable at http://127.0.0.1:18322. Container state: running, health: not reported."
        )
        XCTAssertEqual(issues, [
            RuntimeTestKitReadIssue(source: "testKitAPI", message: message),
            RuntimeTestKitReadIssue(
                source: "containerService.health",
                message: "TestKit container service health is not reported for testkit."
            ),
        ])
    }

    func testVitalDBObservationSnapshotPreservesUnavailableState() throws {
        let snapshot = RuntimeVitalDBObservationSnapshot.unavailable(readError: "sqlite=read failed")

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RuntimeVitalDBObservationSnapshot.self, from: encoded)

        XCTAssertEqual(decoded.state, .unavailable)
        XCTAssertNil(decoded.observation)
        XCTAssertEqual(decoded.readError, "sqlite=read failed")
    }

    func testVitalDBObservationSnapshotFromOptionalPreservesLoadedReadError() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60
        )

        let snapshot = RuntimeVitalDBObservationSnapshot.fromOptional(
            observation,
            readError: "projection=read failed"
        )

        XCTAssertEqual(snapshot.state, .loaded)
        XCTAssertEqual(snapshot.observation?.observedAt, "2026-05-31T00:00:00Z")
        XCTAssertEqual(snapshot.readError, "projection=read failed")
    }

    func testVitalRelationshipHistoryPreservesReadError() throws {
        let history = RuntimeVitalRelationshipHistory(readError: "assignments=read failed")

        let encoded = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(RuntimeVitalRelationshipHistory.self, from: encoded)

        XCTAssertEqual(decoded.state, .readFailed)
        XCTAssertEqual(decoded.assignments, [])
        XCTAssertEqual(decoded.events, [])
        XCTAssertEqual(decoded.readError, "assignments=read failed")
    }

    func testVitalRelationshipHistoryPreservesExplicitPartialStateAndDecodesLegacyPayload() throws {
        let history = RuntimeVitalRelationshipHistory(
            assignments: [
                RuntimeVitalBedAssignmentRecord(
                    assignmentID: "assignment-1",
                    bedID: "bed-a",
                    bedName: "A",
                    vrcode: "VR_A",
                    startedAt: "2026-05-31T00:00:00Z",
                    endedAt: nil,
                    lastSeenAt: "2026-05-31T00:00:10Z",
                    lastObservedAt: "2026-05-31T00:00:10Z",
                    status: .online,
                    patientConnected: true,
                    observationCount: 2
                ),
            ],
            state: .partiallyLoaded,
            readError: "events=read failed"
        )

        let encoded = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(RuntimeVitalRelationshipHistory.self, from: encoded)
        let legacy = try JSONDecoder().decode(RuntimeVitalRelationshipHistory.self, from: Data("""
        {
          "assignments": [],
          "events": [],
          "readError": "legacy read failed"
        }
        """.utf8))

        XCTAssertEqual(decoded.state, .partiallyLoaded)
        XCTAssertEqual(decoded.assignments.map(\.assignmentID), ["assignment-1"])
        XCTAssertEqual(decoded.readError, "events=read failed")
        XCTAssertEqual(legacy.state, .readFailed)
        XCTAssertEqual(legacy.readError, "legacy read failed")
    }

    func testVitalRecorderHistoryPreservesReadStateAndDecodesLegacyPayload() throws {
        let partial = RuntimeVitalRecorderHistory(
            observations: [
                VitalDBObservationDocument(
                    observedAt: "2026-05-26T00:00:00Z",
                    ready: true,
                    recorderOnlineThresholdSeconds: 60,
                    recorders: [
                        VitalDBRecorderObservation(vrcode: "VR_A", online: true),
                    ]
                ),
            ],
            activityBuckets: [],
            readError: "currentObservation=runtimeState=missing"
        )
        let failed = RuntimeVitalRecorderHistory(readError: "observations=read failed")

        let encoded = try JSONEncoder().encode(partial)
        let decoded = try JSONDecoder().decode(RuntimeVitalRecorderHistory.self, from: encoded)
        let legacy = try JSONDecoder().decode(RuntimeVitalRecorderHistory.self, from: Data("""
        {
          "recorders": [],
          "beds": [],
          "readError": "legacy recorder read failed"
        }
        """.utf8))

        XCTAssertEqual(partial.state, .partiallyLoaded)
        XCTAssertEqual(decoded.state, .partiallyLoaded)
        XCTAssertEqual(decoded.recorders.map(\.vrcode), ["VR_A"])
        XCTAssertEqual(decoded.readError, "currentObservation=runtimeState=missing")
        XCTAssertEqual(failed.state, .readFailed)
        XCTAssertEqual(legacy.state, .readFailed)
        XCTAssertEqual(legacy.readError, "legacy recorder read failed")
    }

    func testVitalRecorderHistoryAggregatesByVrcode() {
        let firstObservation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                .init(
                    vrcode: "VR_A",
                    ip: "192.168.64.10",
                    lastSeenAt: "2026-05-26T00:00:00Z",
                    version: "1.0.0",
                    online: true,
                    activity: VitalDBRecorderActivityObservation(
                        windowSeconds: 300,
                        messageCount: 2,
                        byteCount: 1024,
                        roomCount: 1,
                        messagesPerSecond: 0.01,
                        bytesPerSecond: 3.4,
                        buckets: [
                            VitalDBRecorderActivityBucket(
                                bucketStartedAt: "2026-05-26T00:00:00Z",
                                bucketSeconds: 60,
                                messageCount: 2,
                                byteCount: 1024,
                                roomCount: 1
                            ),
                        ]
                    )
                ),
                .init(
                    vrcode: "VR_B",
                    ip: "192.168.64.11",
                    lastSeenAt: "2026-05-26T00:00:00Z",
                    online: true
                ),
            ],
            beds: [
                .init(bedID: "bed-a", name: "OR A", vrcode: "VR_A", patientConnected: true, online: true),
                .init(bedID: "bed-b", name: "OR B", vrcode: "VR_B", patientConnected: false, online: true),
            ]
        )
        let latestObservation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                .init(
                    vrcode: "VR_A",
                    ip: "192.168.64.12",
                    lastSeenAt: "2026-05-26T00:01:00Z",
                    version: "1.0.1",
                    online: true,
                    activity: VitalDBRecorderActivityObservation(
                        windowSeconds: 300,
                        messageCount: 4,
                        byteCount: 2048,
                        roomCount: 2,
                        messagesPerSecond: 0.02,
                        bytesPerSecond: 6.8,
                        buckets: [
                            VitalDBRecorderActivityBucket(
                                bucketStartedAt: "2026-05-26T00:01:00Z",
                                bucketSeconds: 60,
                                messageCount: 4,
                                byteCount: 2048,
                                roomCount: 2
                            ),
                        ]
                    )
                ),
                .init(
                    vrcode: "VR_A",
                    ip: "192.168.64.9",
                    lastSeenAt: "2026-05-26T00:00:30Z",
                    version: "1.0.0",
                    online: true
                ),
            ],
            beds: [
                .init(bedID: "bed-a", name: "OR A Updated", vrcode: "VR_A", patientConnected: false, online: true),
            ],
            anomalies: [
                VitalDBAnomalyObservation(
                    id: "anomaly-a",
                    kind: .staleRecorder,
                    severity: VitalDBAnomalySeverity.warning,
                    observedAt: "2026-05-26T00:01:00Z",
                    subject: "VR_A",
                    message: "Recorder latency is above threshold."
                ),
                VitalDBAnomalyObservation(
                    id: "anomaly-bed-a",
                    kind: .offline,
                    severity: VitalDBAnomalySeverity.info,
                    observedAt: "2026-05-26T00:00:30Z",
                    subject: "bed-a",
                    message: "Bed link is recovering."
                ),
            ]
        )

        let history = RuntimeVitalRecorderHistory(observations: [latestObservation, firstObservation])

        XCTAssertEqual(history.updatedAt, "2026-05-26T00:01:00Z")
        XCTAssertEqual(history.recorders.map { $0.vrcode }, ["VR_A", "VR_B"])
        XCTAssertEqual(history.recorders[0].status, RuntimeVitalRecorderStatus.online)
        XCTAssertEqual(history.recorders[0].lastIP, "192.168.64.12")
        XCTAssertEqual(history.recorders[0].version, "1.0.1")
        XCTAssertEqual(history.recorders[0].bedName, "OR A Updated")
        XCTAssertEqual(history.recorders[0].patientConnected, false)
        XCTAssertEqual(history.recorders[0].observationCount, 2)
        XCTAssertEqual(history.recorders[0].presentInLatestObservation, true)
        XCTAssertEqual(history.recorders[0].currentAnomalyCount, 1)
        XCTAssertEqual(history.recorders[0].latestAnomalyKind, VitalDBAnomalyKind.staleRecorder)
        XCTAssertEqual(history.recorders[0].latestAnomalySeverity, VitalDBAnomalySeverity.warning)
        XCTAssertEqual(history.recorders[0].latestAnomalyMessage, "Recorder latency is above threshold.")
        XCTAssertEqual(history.recorders[0].latestAnomalyObservedAt, "2026-05-26T00:01:00Z")
        XCTAssertNil(history.recorders[0].activityTimeline)
        XCTAssertEqual(history.activityHistory.source, .notProvided)
        XCTAssertEqual(history.recorders[1].status, RuntimeVitalRecorderStatus.notObserved)
        XCTAssertEqual(history.recorders[1].bedName, "OR B")
        XCTAssertEqual(history.recorders[1].observationCount, 1)
        XCTAssertEqual(history.recorders[1].presentInLatestObservation, false)
        XCTAssertEqual(history.beds.map(\.bedID), ["bed-a", "bed-b"])
        XCTAssertEqual(history.beds[0].name, "OR A Updated")
        XCTAssertEqual(history.beds[0].vrcode, "VR_A")
        XCTAssertEqual(history.beds[0].linkedRecorderStatus, RuntimeVitalRecorderStatus.online)
        XCTAssertEqual(history.beds[0].linkedRecorderIP, "192.168.64.12")
        XCTAssertEqual(history.beds[0].linkedRecorderLastSeenAt, "2026-05-26T00:01:00Z")
        XCTAssertEqual(history.beds[0].status, RuntimeVitalBedStatus.online)
        XCTAssertEqual(history.beds[0].patientConnected, false)
        XCTAssertEqual(history.beds[0].observationCount, 2)
        XCTAssertEqual(history.beds[0].currentAnomalyCount, 1)
        XCTAssertEqual(history.beds[0].latestAnomalyKind, VitalDBAnomalyKind.offline)
        XCTAssertEqual(history.beds[0].latestAnomalySeverity, VitalDBAnomalySeverity.info)
        XCTAssertEqual(history.beds[0].latestAnomalyMessage, "Bed link is recovering.")
        XCTAssertEqual(history.beds[1].name, "OR B")
        XCTAssertEqual(history.beds[1].status, RuntimeVitalBedStatus.notObserved)
        XCTAssertEqual(history.beds[1].linkedRecorderStatus, RuntimeVitalRecorderStatus.notObserved)
        XCTAssertEqual(history.beds[1].linkedRecorderIP, "192.168.64.11")
        XCTAssertEqual(history.beds[1].observationCount, 1)
        XCTAssertEqual(history.summary.knownRecorders, 2)
        XCTAssertEqual(history.summary.currentRecorders, 1)
        XCTAssertEqual(history.summary.onlineRecorders, 1)
        XCTAssertEqual(history.summary.staleRecorders, 0)
        XCTAssertEqual(history.summary.recorderAnomalies, 1)
        XCTAssertEqual(history.summary.knownBeds, 2)
        XCTAssertEqual(history.summary.onlineBeds, 1)
        XCTAssertEqual(history.summary.staleBeds, 0)
        XCTAssertEqual(history.summary.bedAssignments, 1)
        XCTAssertEqual(history.summary.bedAnomalies, 1)
    }

    func testVitalRecorderHistoryKeepsCurrentOfflineBedDistinctFromNotObserved() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:02:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-offline",
                    name: "OR Offline",
                    lastSeenAt: "2026-05-26T00:01:00Z",
                    online: false
                ),
            ]
        )

        let history = RuntimeVitalRecorderHistory(observations: [observation])

        XCTAssertEqual(history.beds.first?.status, RuntimeVitalBedStatus.offline)
    }

    func testVitalRecorderHistoryTreatsExplicitStaleRecorderAsStaleEvenWhenOnlineFlagRemainsSet() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:12:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_STALE",
                    ip: "192.168.64.20",
                    lastSeenAt: "2026-05-26T00:00:00Z",
                    online: true,
                    stale: true
                ),
            ]
        )

        let history = RuntimeVitalRecorderHistory(observations: [observation])

        XCTAssertEqual(history.recorders.map(\.status), [.stale])
        XCTAssertEqual(history.summary.onlineRecorders, 0)
        XCTAssertEqual(history.summary.staleRecorders, 1)
    }

    func testVitalRecorderHistoryReportsCollapsedDuplicateSourceObservations() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:02:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_DUP",
                    ip: "192.168.64.10",
                    lastSeenAt: "2026-05-26T00:01:00Z",
                    online: true
                ),
                VitalDBRecorderObservation(
                    vrcode: "VR_DUP",
                    ip: "192.168.64.11",
                    lastSeenAt: "2026-05-26T00:01:10Z",
                    online: true
                ),
            ],
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-dup",
                    name: "OR A",
                    lastSeenAt: "2026-05-26T00:01:00Z",
                    online: true
                ),
                VitalDBBedObservation(
                    bedID: "bed-dup",
                    name: "OR A duplicate",
                    lastSeenAt: "2026-05-26T00:01:10Z",
                    online: true
                ),
            ]
        )

        let history = RuntimeVitalRecorderHistory(observations: [observation])

        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_DUP"])
        XCTAssertEqual(history.recorders.first?.lastIP, "192.168.64.11")
        XCTAssertEqual(history.recorders.first?.duplicateObservationCount, 1)
        XCTAssertEqual(history.beds.map(\.bedID), ["bed-dup"])
        XCTAssertEqual(history.beds.first?.name, "OR A duplicate")
        XCTAssertEqual(history.beds.first?.duplicateObservationCount, 1)
    }

    func testVitalRecorderHistoryUsesProjectedActivityBucketsWhenProvided() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:02:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                .init(
                    vrcode: "VR_A",
                    ip: "192.168.64.12",
                    lastSeenAt: "2026-05-26T00:02:00Z",
                    online: true,
                    activity: VitalDBRecorderActivityObservation(
                        windowSeconds: 300,
                        messageCount: 99,
                        byteCount: 99_000,
                        buckets: [
                            VitalDBRecorderActivityBucket(
                                bucketStartedAt: "2026-05-26T00:02:00Z",
                                bucketSeconds: 60,
                                messageCount: 99,
                                byteCount: 99_000
                            ),
                        ]
                    )
                ),
            ]
        )

        let history = RuntimeVitalRecorderHistory(
            observations: [observation],
            activityBuckets: [
                VitalDBRecorderActivityBucketRecord(
                    vrcode: "VR_A",
                    bucketStartedAt: "2026-05-26T00:01:00Z",
                    bucketSeconds: 60,
                    messageCount: 3,
                    byteCount: 900,
                    roomCount: 1,
                    firstObservedAt: "2026-05-26T00:01:05Z",
                    lastObservedAt: "2026-05-26T00:01:55Z"
                ),
            ]
        )

        let activity = history.recorders.first?.activityTimeline
        XCTAssertEqual(activity?.count, 1)
        XCTAssertEqual(activity?.first?.observedAt, "2026-05-26T00:01:55Z")
        XCTAssertEqual(activity?.first?.messageCount, 3)
        XCTAssertEqual(activity?.first?.byteCount, 900)
        XCTAssertEqual(activity?.first?.buckets.first?.bucketStartedAt, "2026-05-26T00:01:00Z")
        XCTAssertEqual(history.activityHistory.source, .sqliteProjection)
        XCTAssertEqual(history.activityHistory.bucketCount, 1)
        XCTAssertEqual(history.activityHistory.latestBucketStartedAt, "2026-05-26T00:01:00Z")
    }

    func testVitalRecorderHistoryOrdersTimestampsByInstantInsteadOfString() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-31T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_OFFSET",
                    ip: "192.168.64.20",
                    lastSeenAt: "2026-05-31T09:00:00+09:00",
                    online: true
                ),
                VitalDBRecorderObservation(
                    vrcode: "VR_UTC",
                    ip: "192.168.64.21",
                    lastSeenAt: "2026-05-31T00:00:01Z",
                    online: true
                ),
            ]
        )

        let history = RuntimeVitalRecorderHistory(observations: [observation])
        let summary = RuntimeVitalRecorderSummary(status: RuntimeStatus(), vitalDBObservation: observation)

        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_UTC", "VR_OFFSET"])
        XCTAssertEqual(summary.latestRecorder?.vrcode, "VR_UTC")
    }

    func testVitalRecorderHistoryDoesNotInferLastSeenFromObservationTimestamp() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-31T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_NO_LAST_SEEN",
                    online: true
                ),
            ],
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-no-last-seen",
                    vrcode: "VR_NO_LAST_SEEN",
                    online: true
                ),
            ]
        )

        let history = RuntimeVitalRecorderHistory(observations: [observation])

        XCTAssertNil(history.recorders.first?.firstSeenAt)
        XCTAssertNil(history.recorders.first?.lastSeenAt)
        XCTAssertNil(history.beds.first?.firstSeenAt)
        XCTAssertNil(history.beds.first?.lastSeenAt)
        XCTAssertEqual(history.recorders.first?.observationCount, 1)
        XCTAssertEqual(history.beds.first?.observationCount, 1)
    }

    func testVitalRecorderHistoryDoesNotPreservePreviousRecorderFieldsWhenLatestOmitsThem() {
        let firstObservation = VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_PARTIAL",
                    ip: "192.168.64.20",
                    lastSeenAt: "2026-05-31T00:00:00Z",
                    version: "1.0.0",
                    online: true
                ),
            ],
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-a",
                    name: "OR A",
                    vrcode: "VR_PARTIAL",
                    patientConnected: true,
                    online: true
                ),
            ]
        )
        let latestObservation = VitalDBObservationDocument(
            observedAt: "2026-05-31T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_PARTIAL",
                    online: true
                ),
            ],
            beds: []
        )

        let recorder = RuntimeVitalRecorderHistory(
            observations: [firstObservation, latestObservation]
        ).recorders.first

        XCTAssertEqual(recorder?.presentInLatestObservation, true)
        XCTAssertNil(recorder?.lastIP)
        XCTAssertNil(recorder?.version)
        XCTAssertNil(recorder?.lastSeenAt)
        XCTAssertNil(recorder?.bedID)
        XCTAssertNil(recorder?.bedName)
        XCTAssertNil(recorder?.patientConnected)
    }

    func testVitalRecorderActivityPointRequiresCompletePayload() throws {
        let completePayload = """
        {
          "observedAt": "2026-05-26T00:01:55Z",
          "windowSeconds": 60,
          "messageCount": 3,
          "byteCount": 900,
          "roomCount": 1,
          "messagesPerSecond": 0.05,
          "bytesPerSecond": 15,
          "buckets": []
        }
        """

        let decoded = try JSONDecoder().decode(
            RuntimeVitalRecorderActivityPoint.self,
            from: Data(completePayload.utf8)
        )

        XCTAssertEqual(decoded.roomCount, 1)
        XCTAssertEqual(decoded.messagesPerSecond, 0.05)
        XCTAssertEqual(decoded.bytesPerSecond, 15)
        XCTAssertEqual(decoded.buckets, [])

        for missingField in ["roomCount", "messagesPerSecond", "bytesPerSecond", "buckets"] {
            XCTAssertThrowsError(try JSONDecoder().decode(
                RuntimeVitalRecorderActivityPoint.self,
                from: Data(activityPointPayload(missing: missingField).utf8)
            ), missingField)
        }
    }

    func testVitalRecorderSummaryCountsUniqueVrcodes() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                .init(
                    vrcode: "VR_A",
                    ip: "192.168.64.10",
                    lastSeenAt: "2026-05-26T00:01:00Z",
                    online: true
                ),
                .init(
                    vrcode: "VR_A",
                    ip: "192.168.64.11",
                    lastSeenAt: "2026-05-26T00:00:30Z",
                    online: true
                ),
                .init(
                    vrcode: "VR_B",
                    ip: "192.168.64.12",
                    lastSeenAt: "2026-05-26T00:00:00Z",
                    online: false,
                    stale: true
                ),
            ]
        )

        let summary = RuntimeVitalRecorderSummary(status: RuntimeStatus(), vitalDBObservation: observation)

        XCTAssertEqual(summary.knownRecorders, 2)
        XCTAssertEqual(summary.onlineRecorders, 1)
        XCTAssertEqual(summary.staleRecorders, 1)
        XCTAssertEqual(summary.latestRecorder?.vrcode, "VR_A")
        XCTAssertEqual(summary.latestRecorder?.ip, "192.168.64.10")
    }

    func testRuntimeControlOverviewDoesNotFallbackToStatusVitalDBObservation() {
        let staleObservation = VitalDBObservationDocument(
            observedAt: "2026-05-24T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(vrcode: "STALE", ip: "192.168.64.10", online: true),
            ]
        )
        let freshObservation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(vrcode: "FRESH", ip: "192.168.64.11", online: true),
            ]
        )
        var status = RuntimeStatus(vitalDBObservation: staleObservation)
        status.containerObservation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: RuntimeAuditProxyStatusDocument(activeRecorderConnections: 1),
            containerLogsPresent: false,
            containerLogsBytes: nil
        )

        let unavailableOverview = RuntimeControlOverview(
            status: status,
            settings: RuntimeSettings(),
            release: RuntimeReleaseInfo(helperVersion: "0.1.0", minimumUpdaterVersion: "0.1.0", vitalServerVersion: "0.0.0", services: []),
            install: RuntimeInstallInfo(),
            vitalDBObservation: nil,
            vitalDBObservationSnapshot: .unavailable(readError: "sqlite=read failed")
        )
        let loadedOverview = RuntimeControlOverview(
            status: status,
            settings: RuntimeSettings(),
            release: RuntimeReleaseInfo(helperVersion: "0.1.0", minimumUpdaterVersion: "0.1.0", vitalServerVersion: "0.0.0", services: []),
            install: RuntimeInstallInfo(),
            vitalDBObservation: freshObservation,
            vitalDBObservationSnapshot: .loaded(freshObservation)
        )

        XCTAssertNil(unavailableOverview.vitalDBObservation)
        XCTAssertNil(unavailableOverview.status.vitalDBObservation)
        XCTAssertEqual(unavailableOverview.vitalDBObservationSnapshot.state, .unavailable)
        XCTAssertEqual(unavailableOverview.vitalRecorder.source, .unavailable)
        XCTAssertNil(unavailableOverview.vitalRecorder.knownRecorders)
        XCTAssertEqual(unavailableOverview.vitalRecorder.activeConnections, 1)
        XCTAssertNil(loadedOverview.status.vitalDBObservation)
        XCTAssertEqual(loadedOverview.vitalDBObservation?.recorders.map(\.vrcode), ["FRESH"])
        XCTAssertEqual(loadedOverview.vitalRecorder.latestRecorder?.vrcode, "FRESH")
    }

    func testVitalRecorderSummaryDoesNotInferRecorderStateFromAuditProxyConnections() {
        let status = RuntimeStatus(
            containerObservation: RuntimeContainerObservation(
                auditProxyHTTP: "200",
                auditProxyStatus: RuntimeAuditProxyStatusDocument(
                    activeRecorderConnections: 2,
                    recorders: [
                        RuntimeRecorderConnectionObservation(
                            vrcode: "VR_A",
                            activeConnections: 1,
                            selectedIp: "192.168.64.10",
                            lastSeenAt: "2026-05-26T00:01:00Z"
                        ),
                        RuntimeRecorderConnectionObservation(
                            vrcode: "VR_B",
                            activeConnections: 1,
                            selectedIp: "192.168.64.11",
                            lastSeenAt: "2026-05-26T00:01:30Z"
                        ),
                    ]
                ),
                containerLogsPresent: false,
                containerLogsBytes: nil
            )
        )

        let summary = RuntimeVitalRecorderSummary(status: status)

        XCTAssertEqual(summary.source, .unavailable)
        XCTAssertEqual(summary.activeConnections, 2)
        XCTAssertNil(summary.knownRecorders)
        XCTAssertNil(summary.onlineRecorders)
        XCTAssertNil(summary.staleRecorders)
        XCTAssertNil(summary.knownBeds)
        XCTAssertNil(summary.recorderAnomalies)
        XCTAssertNil(summary.observedAt)
        XCTAssertNil(summary.latestRecorder)
    }

    func testVitalRecorderSummaryDoesNotDefaultMissingAuditProxyConnectionsToZero() {
        let summary = RuntimeVitalRecorderSummary(status: RuntimeStatus())

        XCTAssertEqual(summary.source, .unavailable)
        XCTAssertNil(summary.activeConnections)
        XCTAssertNil(summary.knownRecorders)
    }
}

private func activityPointPayload(missing field: String) -> String {
    let fields: [(String, String)] = [
        ("observedAt", #""2026-05-26T00:01:55Z""#),
        ("windowSeconds", "60"),
        ("messageCount", "3"),
        ("byteCount", "900"),
        ("roomCount", "1"),
        ("messagesPerSecond", "0.05"),
        ("bytesPerSecond", "15"),
        ("buckets", "[]"),
    ]
    let body = fields
        .filter { $0.0 != field }
        .map { "\"\($0.0)\": \($0.1)" }
        .joined(separator: ",")
    return "{\(body)}"
}

private func runtimeTestKitSession(id: String, state: String) -> RuntimeTestKitSession {
    RuntimeTestKitSession(
        id: id,
        state: state,
        targetURL: "http://testkit.example.test",
        recordersRequested: 1,
        bedsRequested: 1,
        bedRoomNames: ["OR-1"],
        vrcode: nil,
        version: "testkit",
        intervalSeconds: 1,
        durationSeconds: nil,
        maxMessages: nil,
        shiftTime: true,
        generateFrames: true,
        defaultScenario: "normal",
        createdAt: nil,
        startedAt: nil,
        stoppedAt: nil,
        messagesSent: 0,
        bytesSent: 0,
        lastError: nil,
        recorders: []
    )
}
