import RuntimeControl
import Contracts
import XCTest
import Errors

final class RuntimeControlContractsTests: XCTestCase {
    func testRuntimeLogArchiveRetentionPolicyPrunesByAgeAndManagedSize() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try fixedDate(year: 2026, month: 6, day: 14, calendar: calendar)
        let archives = [
            RuntimeLogArchiveDay(
                url: URL(fileURLWithPath: "/logs/archive/2026-05-30"),
                day: try fixedDate(year: 2026, month: 5, day: 30, calendar: calendar),
                sizeBytes: 1
            ),
            RuntimeLogArchiveDay(
                url: URL(fileURLWithPath: "/logs/archive/2026-06-01"),
                day: try fixedDate(year: 2026, month: 6, day: 1, calendar: calendar),
                sizeBytes: 6
            ),
            RuntimeLogArchiveDay(
                url: URL(fileURLWithPath: "/logs/archive/2026-06-02"),
                day: try fixedDate(year: 2026, month: 6, day: 2, calendar: calendar),
                sizeBytes: 6
            ),
            RuntimeLogArchiveDay(
                url: URL(fileURLWithPath: "/logs/archive/2026-06-03"),
                day: try fixedDate(year: 2026, month: 6, day: 3, calendar: calendar),
                sizeBytes: 1
            ),
        ]

        let pruned = RuntimeLogArchiveRetentionPolicy.pruneCandidates(
            archives: archives,
            configuration: RuntimeLogArchiveRetentionConfiguration(retentionDays: 14, maximumBytes: 7),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(pruned.map(\.lastPathComponent), ["2026-05-30", "2026-06-01"])
    }

    func testRuntimeLogArchiveRetentionConfigurationRejectsInvalidValues() {
        XCTAssertTrue(RuntimeLogArchiveRetentionPolicy.isValidRetentionDays(1))
        XCTAssertTrue(RuntimeLogArchiveRetentionPolicy.isValidRetentionDays(30))
        XCTAssertFalse(RuntimeLogArchiveRetentionPolicy.isValidRetentionDays(0))
        XCTAssertFalse(RuntimeLogArchiveRetentionPolicy.isValidRetentionDays(31))
        XCTAssertTrue(RuntimeLogArchiveRetentionPolicy.isValidMaximumBytes(1))
        XCTAssertFalse(RuntimeLogArchiveRetentionPolicy.isValidMaximumBytes(0))
    }

    func testRuntimeStatePreservesUnknownValues() throws {
        let state = RuntimeState(rawValue: "maintenance")

        XCTAssertEqual(state.rawValue, "maintenance")

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(RuntimeState.self, from: encoded)

        XCTAssertEqual(decoded, .unknown("maintenance"))
    }

    func testGuestControlStackStatusRoundTripsThroughJSON() throws {
        let status = RuntimeGuestControlStackStatus(
            state: "loaded",
            observedAt: "2026-07-01T00:00:00+00:00",
            services: [
                RuntimeGuestControlServiceStatus(
                    service: "app",
                    state: "running",
                    health: "healthy",
                    observedAt: "2026-07-01T00:00:00+00:00",
                    container: "vitalserver-app-1",
                    exitCode: 0,
                    memory: ResourceUsage(usedBytes: 1, totalBytes: 10)
                ),
                RuntimeGuestControlServiceStatus(
                    service: "redis",
                    state: "absent",
                    health: "not_reported",
                    observedAt: "2026-07-01T00:00:00+00:00"
                ),
            ],
            cpuUsagePercent: 12.5,
            memory: ResourceUsage(usedBytes: 2, totalBytes: 10),
            systemDisk: ResourceUsage(usedBytes: 3, totalBytes: 10),
            vitalFilesDisk: ResourceUsage(usedBytes: 4, totalBytes: 10)
        )

        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(RuntimeGuestControlStackStatus.self, from: encoded)

        XCTAssertEqual(decoded, status)
        XCTAssertEqual(decoded.services.map(\.service), ["app", "redis"])
        XCTAssertEqual(decoded.services.first?.container, "vitalserver-app-1")
        XCTAssertEqual(decoded.services.first?.memory, ResourceUsage(usedBytes: 1, totalBytes: 10))
        XCTAssertEqual(decoded.services.last?.state, "absent")
        XCTAssertEqual(decoded.cpuUsagePercent, 12.5)
        XCTAssertEqual(decoded.memory, ResourceUsage(usedBytes: 2, totalBytes: 10))
        XCTAssertEqual(decoded.systemDisk, ResourceUsage(usedBytes: 3, totalBytes: 10))
        XCTAssertEqual(decoded.vitalFilesDisk, ResourceUsage(usedBytes: 4, totalBytes: 10))
    }

    func testGuestControlVitalDBObservationReadRoundTripsThroughJSON() throws {
        let read = RuntimeGuestControlVitalDBObservationRead(
            state: .loaded,
            observation: VitalDBObservationDocument(
                observedAt: "2026-07-01T00:00:00+00:00",
                ready: true,
                recorderOnlineThresholdSeconds: 60
            ),
            readError: nil
        )

        let encoded = try JSONEncoder().encode(read)
        let decoded = try JSONDecoder().decode(
            RuntimeGuestControlVitalDBObservationRead.self,
            from: encoded
        )

        XCTAssertEqual(decoded, read)
        XCTAssertEqual(decoded.state, .loaded)
        XCTAssertEqual(decoded.observation?.observedAt, "2026-07-01T00:00:00+00:00")
    }

    func testGuestControlVitalDBRecorderAndBedReadsRoundTripThroughJSON() throws {
        let recorderRead = RuntimeGuestControlVitalDBRecorderRead(
            state: .loaded,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR-001", online: true),
            ],
            observedAt: "2026-07-01T00:00:00+00:00",
            ready: true,
            recorderOnlineThresholdSeconds: 60
        )
        let bedRead = RuntimeGuestControlVitalDBBedRead(
            state: .loaded,
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-a",
                    name: "OR-A",
                    vrcode: "VR-001",
                    online: true
                ),
            ],
            observedAt: "2026-07-01T00:00:00+00:00",
            ready: true,
            recorderOnlineThresholdSeconds: 60
        )

        let recorderData = try JSONEncoder().encode(recorderRead)
        let bedData = try JSONEncoder().encode(bedRead)

        XCTAssertEqual(
            try JSONDecoder().decode(RuntimeGuestControlVitalDBRecorderRead.self, from: recorderData),
            recorderRead
        )
        XCTAssertEqual(
            try JSONDecoder().decode(RuntimeGuestControlVitalDBBedRead.self, from: bedData),
            bedRead
        )
    }

    func testGuestControlVitalDBRelationshipReadRoundTripsThroughJSON() throws {
        let read = RuntimeGuestControlVitalDBRelationshipRead(
            state: .partiallyLoaded,
            assignments: [
                RuntimeVitalBedAssignmentRecord(
                    assignmentID: "assignment-1",
                    bedID: "bed-a",
                    bedName: "OR-A",
                    vrcode: "VR-001",
                    startedAt: "2026-07-01T00:00:00+00:00",
                    endedAt: nil,
                    lastSeenAt: "2026-07-01T00:00:05+00:00",
                    lastObservedAt: "2026-07-01T00:00:05+00:00",
                    status: .online,
                    patientConnected: true,
                    observationCount: 2
                ),
            ],
            events: [],
            readError: "events unavailable"
        )

        let encoded = try JSONEncoder().encode(read)
        let decoded = try JSONDecoder().decode(
            RuntimeGuestControlVitalDBRelationshipRead.self,
            from: encoded
        )

        XCTAssertEqual(decoded, read)
        XCTAssertEqual(decoded.state, .partiallyLoaded)
        XCTAssertEqual(decoded.assignments.map(\.assignmentID), ["assignment-1"])
        XCTAssertEqual(decoded.readError, "events unavailable")
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
            hostProxyHTTP: "200",
            guestStackProbeErrors: [
                GuestRuntimeProbeError(
                    source: "docker stats",
                    message: "timed out after 1 seconds"
                )
            ],
            vitalServerMemory: RuntimeContainerMemoryUsage(usedBytes: 1_073_741_824, limitBytes: 4_294_967_296),
            recorderIngressMemory: RuntimeContainerMemoryUsage(usedBytes: 134_217_728, limitBytes: nil),
            redisMemory: RuntimeContainerMemoryUsage(usedBytes: 67_108_864, limitBytes: 536_870_912)
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
        XCTAssertEqual(decoded.guestStackProbeErrors, [
            GuestRuntimeProbeError(
                source: "docker stats",
                message: "timed out after 1 seconds"
            ),
        ])
        XCTAssertEqual(decoded.vitalServerMemory?.percent, 25)
        XCTAssertEqual(decoded.recorderIngressMemory, RuntimeContainerMemoryUsage(usedBytes: 134_217_728, limitBytes: nil))
        XCTAssertEqual(decoded.redisMemory?.percent, 12.5)
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
        XCTAssertEqual(legacyInstalled.guestStackProbeErrors, [])
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

    func testRuntimeSettingsReadPolicyPreservesInvalidGuestRetentionAsExplicitReadIssue() {
        let settings = RuntimeSettingsReadPolicy.applyGuestRuntimeSettings(
            RuntimeGuestRuntimeSettingsReadInput(
                vitalServerURL: "https://settings.example.test/",
                remoteConsoleURL: "https://console.settings.example.test/",
                publicHost: "settings.example.test",
                publicPort: 8443,
                automaticBackupEnabled: true,
                backupScheduleTimes: ["03:15"],
                backupRetentionCount: 31
            ),
            to: RuntimeSettings()
        )

        XCTAssertEqual(settings.vitalServerURL, "https://settings.example.test/")
        XCTAssertEqual(settings.remoteConsoleURL, "https://console.settings.example.test/")
        XCTAssertEqual(settings.publicHost, "settings.example.test")
        XCTAssertEqual(settings.publicPort, 8443)
        XCTAssertEqual(settings.backupRetentionCount, 31)
        XCTAssertEqual(settings.readIssues, [
            RuntimeSettingsReadIssue(
                source: "guestRuntimeSettings.backupRetentionCount",
                message: "backupRetentionCount is out of range: 31"
            ),
        ])
    }

    func testRuntimeSettingsReadPolicyAppliesLogArchiveSettings() {
        let settings = RuntimeSettingsReadPolicy.applyLogArchiveSettings(
            RuntimeLogArchiveSettingsReadInput(retentionDays: 10, maximumGiB: 3),
            to: RuntimeSettings()
        )

        XCTAssertEqual(settings.logArchiveRetentionDays, 10)
        XCTAssertEqual(settings.logArchiveMaximumGiB, 3)
        XCTAssertEqual(settings.readIssues, [])
    }

    func testRuntimeSettingsReadPolicyPreservesInvalidLogArchiveSettingsAsReadIssues() {
        let settings = RuntimeSettingsReadPolicy.applyLogArchiveSettings(
            RuntimeLogArchiveSettingsReadInput(retentionDays: 31, maximumGiB: 21),
            to: RuntimeSettings()
        )

        XCTAssertEqual(settings.logArchiveRetentionDays, 31)
        XCTAssertEqual(settings.logArchiveMaximumGiB, 21)
        XCTAssertEqual(settings.readIssues, [
            RuntimeSettingsReadIssue(
                source: "logArchiveSettings.logArchiveRetentionDays",
                message: "logArchiveRetentionDays is out of range: 31"
            ),
            RuntimeSettingsReadIssue(
                source: "logArchiveSettings.logArchiveMaximumGiB",
                message: "logArchiveMaximumGiB is out of range: 21"
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
                automaticBackupEnabled: true,
                backupScheduleTimes: ["03:15", "15:15"],
                backupRetentionCount: 12
            )),
            logArchiveSettings: .loaded(RuntimeLogArchiveSettingsReadInput(retentionDays: 8, maximumGiB: 2)),
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
        XCTAssertEqual(settings.backupScheduleTimes, ["03:15", "15:15"])
        XCTAssertEqual(settings.backupRetentionCount, 12)
        XCTAssertEqual(settings.logArchiveRetentionDays, 8)
        XCTAssertEqual(settings.logArchiveMaximumGiB, 2)
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

        XCTAssertTrue(RuntimeActiveOperationPolicy.isUpdateProgressInProgress(status.progress))
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

        XCTAssertTrue(RuntimeActiveOperationPolicy.isInstallProgressInProgress(status.progress))
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

        XCTAssertFalse(RuntimeActiveOperationPolicy.isUpdateProgressInProgress(status.progress))
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

        XCTAssertTrue(RuntimeActiveOperationPolicy.isRecoveryProgressInProgress(status.progress))
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

        XCTAssertFalse(RuntimeActiveOperationPolicy.isRecoveryProgressInProgress(status.progress))
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

        XCTAssertFalse(RuntimeActiveOperationPolicy.isInstallProgressInProgress(status.progress))
    }

    func testActiveOperationPolicyDoesNotInferUpdateOrRecoveryFromLegacyStatusOperation() {
        let updating = RuntimeStatus(runtimeState: .updating, operation: .applyBundle)
        let recoveringUpdate = RuntimeStatus(runtimeState: .recovering, operation: .activateGuestUpdate)
        let recoveringRollback = RuntimeStatus(runtimeState: .recovering, operation: .rollback)
        let healthy = RuntimeStatus(runtimeState: .healthy, operation: .applyBundle)
        let nonUpdate = RuntimeStatus(runtimeState: .updating, operation: .repairVMDisk)

        XCTAssertFalse(RuntimeActiveOperationPolicy.isUpdateProgressInProgress(updating.progress))
        XCTAssertFalse(RuntimeActiveOperationPolicy.isUpdateProgressInProgress(recoveringUpdate.progress))
        XCTAssertFalse(RuntimeActiveOperationPolicy.isRecoveryProgressInProgress(recoveringUpdate.progress))
        XCTAssertFalse(RuntimeActiveOperationPolicy.isRecoveryProgressInProgress(recoveringRollback.progress))
        XCTAssertFalse(RuntimeActiveOperationPolicy.isUpdateProgressInProgress(healthy.progress))
        XCTAssertFalse(RuntimeActiveOperationPolicy.isUpdateProgressInProgress(nonUpdate.progress))
    }

    func testActiveOperationPolicyUsesExplicitOperationForPresentationState() {
        let updating = RuntimeStatus(runtimeState: .healthy, operation: .watchdog)
        let recovering = RuntimeStatus(runtimeState: .recovering, operation: .watchdog)

        XCTAssertTrue(RuntimeActiveOperationPolicy.isUpdateInProgress(updating, operation: .applyBundle))
        XCTAssertFalse(RuntimeActiveOperationPolicy.isRecoveryInProgress(updating, operation: .applyBundle))
        XCTAssertFalse(RuntimeActiveOperationPolicy.isUpdateInProgress(recovering, operation: .applyBundle))
        XCTAssertTrue(RuntimeActiveOperationPolicy.isRecoveryInProgress(recovering, operation: .applyBundle))
        XCTAssertTrue(RuntimeActiveOperationPolicy.isRecoveryInProgress(recovering, operation: .rollback))
        XCTAssertFalse(RuntimeActiveOperationPolicy.isRecoveryInProgress(recovering, operation: nil))
    }

    func testActiveOperationPolicyTreatsInitializingRuntimeStateAsInitializationInProgress() {
        let initializing = RuntimeStatus(runtimeState: .initializing, operation: .install)

        XCTAssertFalse(RuntimeActiveOperationPolicy.isInstallProgressInProgress(initializing.progress))
        XCTAssertTrue(RuntimeActiveOperationPolicy.isInitializationInProgress(initializing))
    }

    func testActiveOperationPolicyDoesNotInferInstallProgressFromLegacyDegradedInstall() {
        let installing = RuntimeStatus(runtimeState: .degraded, operation: .install)
        let degradedWithoutInstallOperation = RuntimeStatus(runtimeState: .degraded, operation: .health)

        XCTAssertFalse(RuntimeActiveOperationPolicy.isInstallProgressInProgress(installing.progress))
        XCTAssertFalse(RuntimeActiveOperationPolicy.isInstallProgressInProgress(degradedWithoutInstallOperation.progress))
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

        XCTAssertFalse(RuntimeActiveOperationPolicy.isInstallProgressInProgress(status.progress))
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

        XCTAssertFalse(RuntimeActiveOperationPolicy.isInstallProgressInProgress(status.progress))
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

        XCTAssertFalse(RuntimeActiveOperationPolicy.isInstallProgressInProgress(status.progress))
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

    func testRuntimeInstallOperationStatePreservesStatusInstallReadMeanings() {
        let installDocument = RuntimeInstallStateDocument(
            state: .stepStarted,
            mode: .full,
            currentStep: .replaceRootfsBase,
            updatedAt: "2026-07-08T00:00:00Z",
            message: "install step running"
        )
        let loaded = RuntimeInstallOperationState.fromRuntimeStatusInstallRead(RuntimeStatus(
            installStateDocument: installDocument,
            updatedAt: "2026-07-08T00:00:02Z"
        ))
        let unavailable = RuntimeInstallOperationState.fromRuntimeStatusInstallRead(RuntimeStatus())
        let statusOperationOnly = RuntimeOperationState(
            activeOperation: nil,
            runtimeStatusUpdatedAt: nil,
            install: RuntimeInstallOperationState.fromRuntimeStatusInstallRead(RuntimeStatus(operation: .applyBundle))
        )
        let installOperationState = RuntimeOperationState(
            activeOperation: nil,
            runtimeStatusUpdatedAt: "2026-07-08T00:00:02Z",
            install: loaded
        )
        let failed = RuntimeInstallOperationState.fromRuntimeStatusInstallRead(RuntimeStatus(
            installStateDocumentError: "runtime install state decode failed"
        ))

        XCTAssertEqual(loaded.state, .loaded)
        XCTAssertEqual(loaded.document, installDocument)
        XCTAssertNil(loaded.readError)

        XCTAssertEqual(unavailable.state, .unavailable)
        XCTAssertNil(unavailable.document)
        XCTAssertNil(unavailable.readError)

        XCTAssertNil(statusOperationOnly.activeOperation)
        XCTAssertNil(statusOperationOnly.operationForPresentation)
        XCTAssertEqual(installOperationState.activeOperation, .install)
        XCTAssertEqual(installOperationState.operationForPresentation, .install)
        XCTAssertEqual(installOperationState.runtimeStatusUpdatedAt, "2026-07-08T00:00:02Z")

        XCTAssertEqual(failed.state, .failed)
        XCTAssertNil(failed.document)
        XCTAssertEqual(failed.readError, "runtime install state decode failed")
    }

    func testRuntimeOperationStateDoesNotTreatProvisionedInstallDocumentAsActiveInstall() {
        let provisioned = RuntimeInstallStateDocument(
            state: .provisioned,
            mode: .provision,
            updatedAt: "2026-07-08T00:00:00Z",
            message: "runtime install provisioned"
        )
        let installRead = RuntimeInstallOperationState.fromRuntimeStatusInstallRead(RuntimeStatus(
            installStateDocument: provisioned,
            updatedAt: "2026-07-08T00:00:02Z"
        ))

        let operationState = RuntimeOperationState(
            activeOperation: nil,
            runtimeStatusUpdatedAt: "2026-07-08T00:00:02Z",
            install: installRead
        )

        XCTAssertEqual(operationState.install.state, .loaded)
        XCTAssertEqual(operationState.install.document, provisioned)
        XCTAssertNil(operationState.activeOperation)
        XCTAssertNil(operationState.operationForPresentation)
    }

    func testRuntimeOperationLeaseStatePreservesReadAndStaleMeanings() {
        let document = RuntimeOperationLeaseDocument(
            operationId: "operation-1",
            operation: .applyBundle,
            ownerPID: 123,
            startedAt: "2026-07-08T00:00:00Z",
            heartbeatAt: "2026-07-08T00:00:01Z",
            expiresAt: "2026-07-08T00:00:02Z",
            message: "applying bundle"
        )
        let loaded = RuntimeOperationLeaseState.loaded(document)
        let unavailable = RuntimeOperationLeaseState.unavailable()
        let failed = RuntimeOperationLeaseState.failed(readError: "lease decode failed")
        let stale = RuntimeOperationLeaseState.stale(document, staleReason: "expired")

        XCTAssertEqual(loaded.state, .loaded)
        XCTAssertEqual(loaded.document, document)
        XCTAssertNil(loaded.readError)
        XCTAssertNil(loaded.staleReason)

        XCTAssertEqual(unavailable.state, .unavailable)
        XCTAssertNil(unavailable.document)
        XCTAssertNil(unavailable.readError)

        XCTAssertEqual(failed.state, .failed)
        XCTAssertNil(failed.document)
        XCTAssertEqual(failed.readError, "lease decode failed")

        XCTAssertEqual(stale.state, .stale)
        XCTAssertEqual(stale.document, document)
        XCTAssertEqual(stale.staleReason, "expired")
        XCTAssertNil(stale.readError)
    }

    func testRuntimeOperationStateEncodesNullableOperationFieldsAsExplicitNull() throws {
        let installDocument = RuntimeInstallStateDocument(
            state: .started,
            mode: .full,
            updatedAt: "2026-07-08T00:00:00Z"
        )
        let leaseDocument = RuntimeOperationLeaseDocument(
            operationId: "operation-1",
            operation: .applyBundle,
            ownerPID: nil,
            startedAt: "2026-07-08T00:00:00Z",
            heartbeatAt: "2026-07-08T00:00:01Z",
            expiresAt: nil,
            message: nil
        )
        let operationState = RuntimeOperationState(
            activeOperation: nil,
            runtimeStatusUpdatedAt: nil,
            install: .loaded(installDocument),
            lease: .loaded(leaseDocument)
        )

        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(operationState)) as? [String: Any]
        )
        let install = try XCTUnwrap(json["install"] as? [String: Any])
        let installDocumentJSON = try XCTUnwrap(install["document"] as? [String: Any])
        let lease = try XCTUnwrap(json["lease"] as? [String: Any])
        let leaseDocumentJSON = try XCTUnwrap(lease["document"] as? [String: Any])

        XCTAssertEqual(json["activeOperation"] as? String, "install")
        XCTAssertTrue(json["runtimeStatusUpdatedAt"] is NSNull)
        XCTAssertTrue(install["readError"] is NSNull)
        XCTAssertTrue(installDocumentJSON["currentStep"] is NSNull)
        XCTAssertTrue(installDocumentJSON["message"] is NSNull)
        XCTAssertTrue(lease["readError"] is NSNull)
        XCTAssertTrue(lease["staleReason"] is NSNull)
        XCTAssertTrue(leaseDocumentJSON["ownerPID"] is NSNull)
        XCTAssertTrue(leaseDocumentJSON["expiresAt"] is NSNull)
        XCTAssertTrue(leaseDocumentJSON["message"] is NSNull)
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

    func testVitalDBObservationSnapshotPreservesUnavailableState() throws {
        let snapshot = RuntimeVitalDBObservationSnapshot.unavailable(readError: "sqlite=read failed")

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RuntimeVitalDBObservationSnapshot.self, from: encoded)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(decoded.state, .unavailable)
        XCTAssertNil(decoded.observation)
        XCTAssertEqual(decoded.readError, "sqlite=read failed")
        XCTAssertTrue(json["observation"] is NSNull)
        XCTAssertEqual(json["readError"] as? String, "sqlite=read failed")
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
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(decoded.state, .readFailed)
        XCTAssertEqual(decoded.assignments, [])
        XCTAssertEqual(decoded.events, [])
        XCTAssertEqual(decoded.readError, "assignments=read failed")
        XCTAssertEqual(json["readError"] as? String, "assignments=read failed")
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
        let decodedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let activityHistoryJSON = try XCTUnwrap(decodedJSON["activityHistory"] as? [String: Any])
        let failedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(failed)) as? [String: Any]
        )
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
        XCTAssertEqual(decodedJSON["state"] as? String, "partiallyLoaded")
        XCTAssertEqual(decodedJSON["readError"] as? String, "currentObservation=runtimeState=missing")
        XCTAssertEqual(decodedJSON["updatedAt"] as? String, "2026-05-26T00:00:00Z")
        XCTAssertTrue(decodedJSON["recorderIngressStatusRead"] is NSNull)
        XCTAssertTrue(activityHistoryJSON["earliestBucketStartedAt"] is NSNull)
        XCTAssertTrue(activityHistoryJSON["latestBucketStartedAt"] is NSNull)
        XCTAssertTrue(activityHistoryJSON["readError"] is NSNull)
        XCTAssertEqual(failedJSON["state"] as? String, "readFailed")
        XCTAssertEqual(failedJSON["readError"] as? String, "observations=read failed")
        XCTAssertEqual(legacy.state, .readFailed)
        XCTAssertEqual(legacy.readError, "legacy recorder read failed")
    }

    func testRecorderIngressStatusReadResultEncodesExplicitReadEvidence() throws {
        let loaded = RuntimeRecorderIngressStatusReadResult(
            httpStatus: "200",
            document: RuntimeRecorderIngressStatusDocument(activeRecorderConnections: 1),
            readError: nil
        )
        let failed = RuntimeRecorderIngressStatusReadResult(
            httpStatus: RuntimeHTTPStatusText.failed,
            document: nil,
            readError: "command-failed recorder ingress status"
        )

        let loadedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded)) as? [String: Any]
        )
        let failedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(failed)) as? [String: Any]
        )
        let legacy = try JSONDecoder().decode(RuntimeRecorderIngressStatusReadResult.self, from: Data("""
        {
          "readState": "readFailed",
          "readError": "legacy read failed"
        }
        """.utf8))

        XCTAssertEqual(loadedJSON["readState"] as? String, "loaded")
        XCTAssertEqual(loadedJSON["httpStatus"] as? String, "200")
        XCTAssertNotNil(loadedJSON["document"] as? [String: Any])
        XCTAssertTrue(loadedJSON["readError"] is NSNull)
        XCTAssertEqual(failedJSON["readState"] as? String, "commandFailed")
        XCTAssertEqual(failedJSON["httpStatus"] as? String, RuntimeHTTPStatusText.failed)
        XCTAssertTrue(failedJSON["document"] is NSNull)
        XCTAssertEqual(failedJSON["readError"] as? String, "command-failed recorder ingress status")
        XCTAssertEqual(legacy.readState, .readFailed)
        XCTAssertEqual(legacy.httpStatus, "")
        XCTAssertEqual(legacy.readError, "legacy read failed")
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

    func testVitalRecorderHistoryTreatsOutdatedOnlineRecorderAsStale() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:12:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_STALE_BY_AGE",
                    ip: "192.168.64.21",
                    lastSeenAt: "2026-05-26T00:10:30Z",
                    online: true,
                    stale: false
                ),
            ]
        )

        let history = RuntimeVitalRecorderHistory(observations: [observation])

        XCTAssertEqual(history.recorders.map(\.status), [.stale])
        XCTAssertEqual(history.summary.onlineRecorders, 0)
        XCTAssertEqual(history.summary.staleRecorders, 1)
    }

    func testVitalRecorderHistoryUsesExplicitStatusEvaluationTimeForStaleObservation() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:12:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_STALE_OBSERVATION",
                    ip: "192.168.64.21",
                    lastSeenAt: "2026-05-26T00:11:59Z",
                    online: true,
                    stale: false
                ),
            ]
        )

        let history = RuntimeVitalRecorderHistory(
            observations: [observation],
            statusEvaluationTime: "2026-05-26T00:31:00Z"
        )

        XCTAssertEqual(history.recorders.map(\.status), [.stale])
        XCTAssertEqual(history.summary.onlineRecorders, 0)
        XCTAssertEqual(history.summary.staleRecorders, 1)
    }

    func testVitalRecorderHistoryDoesNotUseRecorderIngressActivityToOverrideRecorderState() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:12:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_SENDING",
                    ip: "192.168.64.20",
                    lastSeenAt: "2026-05-26T00:00:00Z",
                    online: true,
                    stale: true
                ),
            ]
        )
        let ingressRead = RuntimeRecorderIngressStatusReadResult(
            readState: .loaded,
            httpStatus: "200",
            document: RuntimeRecorderIngressStatusDocument(
                recorders: [
                    RuntimeRecorderConnectionObservation(
                        vrcode: "VR_SENDING",
                        activeConnections: 1,
                        selectedIp: "192.168.64.20",
                        ipSource: "x-forwarded-for",
                        lastSeenAt: "2026-05-26T00:11:45Z"
                    ),
                ]
            ),
            readError: nil
        )

        let history = RuntimeVitalRecorderHistory(
            observations: [observation],
            recorderIngressStatusRead: ingressRead
        )

        XCTAssertEqual(history.recorders.first?.status, .stale)
        XCTAssertEqual(history.recorders.first?.lastSeenAt, "2026-05-26T00:00:00Z")
        XCTAssertEqual(history.summary.onlineRecorders, 0)
        XCTAssertEqual(history.summary.staleRecorders, 1)
        XCTAssertEqual(history.recorderIngressStatusRead, ingressRead)
    }

    func testVitalRecorderHistoryUsesExplicitRecorderIngressStatusReadWithoutContainerObservation() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:12:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_SENDING",
                    ip: "192.168.64.20",
                    lastSeenAt: "2026-05-26T00:00:00Z",
                    online: true,
                    stale: true
                ),
            ]
        )
        let ingressRead = RuntimeRecorderIngressStatusReadResult(
            readState: .loaded,
            httpStatus: "200",
            document: RuntimeRecorderIngressStatusDocument(
                recorders: [
                    RuntimeRecorderConnectionObservation(
                        vrcode: "VR_SENDING",
                        activeConnections: 1,
                        selectedIp: "192.168.64.20",
                        ipSource: "x-forwarded-for",
                        lastSeenAt: "2026-05-26T00:11:45Z"
                    ),
                ]
            ),
            readError: nil
        )

        let history = RuntimeVitalRecorderHistory(
            observations: [observation],
            recorderIngressStatusRead: ingressRead
        )

        XCTAssertEqual(history.recorders.first?.status, .stale)
        XCTAssertEqual(history.recorders.first?.lastSeenAt, "2026-05-26T00:00:00Z")
        XCTAssertEqual(history.summary.onlineRecorders, 0)
        XCTAssertEqual(history.summary.staleRecorders, 1)
        XCTAssertEqual(history.recorderIngressStatusRead, ingressRead)
    }

    func testVitalRecorderHistoryCodablePreservesRecorderIngressStatusRead() throws {
        let ingressRead = RuntimeRecorderIngressStatusReadResult(
            readState: .loaded,
            httpStatus: "200",
            document: RuntimeRecorderIngressStatusDocument(
                activeRecorderConnections: 1,
                recorders: [
                    RuntimeRecorderConnectionObservation(
                        vrcode: "VR_CONTRACT",
                        activeConnections: 1,
                        selectedIp: "192.168.64.22",
                        ipSource: "x-forwarded-for",
                        lastSeenAt: "2026-05-26T00:11:45Z"
                    ),
                ]
            ),
            readError: nil
        )
        let history = RuntimeVitalRecorderHistory(
            observations: [],
            recorderIngressStatusRead: ingressRead
        )

        let data = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(RuntimeVitalRecorderHistory.self, from: data)

        XCTAssertEqual(decoded.recorderIngressStatusRead, ingressRead)
    }

    func testVitalRecorderHistoryDoesNotCreateRecorderObservedOnlyByRecorderIngressActivity() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:12:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60
        )
        let ingressRead = RuntimeRecorderIngressStatusReadResult(
            readState: .loaded,
            httpStatus: "200",
            document: RuntimeRecorderIngressStatusDocument(
                recorders: [
                    RuntimeRecorderConnectionObservation(
                        vrcode: "VR_INGRESS_ONLY",
                        activeConnections: 1,
                        selectedIp: "192.168.64.21",
                        ipSource: "socket",
                        lastSeenAt: "2026-05-26T00:11:30Z"
                    ),
                ]
            ),
            readError: nil
        )

        let history = RuntimeVitalRecorderHistory(
            observations: [observation],
            recorderIngressStatusRead: ingressRead
        )

        XCTAssertEqual(history.recorders, [])
        XCTAssertEqual(history.summary.knownRecorders, 0)
        XCTAssertEqual(history.summary.onlineRecorders, 0)
        XCTAssertEqual(history.recorderIngressStatusRead, ingressRead)
    }

    func testVitalRecorderHistoryMergesRecorderRedisIPSyncFromRecorderIngressStatus() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:12:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_A",
                    ip: "192.168.64.20",
                    lastSeenAt: "2026-05-26T00:12:00Z",
                    online: true
                ),
                VitalDBRecorderObservation(
                    vrcode: "VR_B",
                    ip: "192.168.64.21",
                    lastSeenAt: "2026-05-26T00:12:00Z",
                    online: true
                ),
            ]
        )
        let ingressRead = RuntimeRecorderIngressStatusReadResult(
            readState: .loaded,
            httpStatus: "200",
            document: RuntimeRecorderIngressStatusDocument(
                recorders: [
                    RuntimeRecorderConnectionObservation(
                        vrcode: "VR_A",
                        activeConnections: 1,
                        selectedIp: "192.168.64.20",
                        ipSource: "x-forwarded-for",
                        lastSeenAt: "2026-05-26T00:12:00Z",
                        redisIpSync: RuntimeRecorderRedisIPSyncObservation(
                            status: .verified,
                            redisKey: "ip_VR_A",
                            selectedIp: "192.168.64.20",
                            ipSource: "x-forwarded-for",
                            redisValue: "192.168.64.20",
                            lastVerifiedAt: "2026-05-26T00:12:01Z"
                        )
                    ),
                ]
            ),
            readError: nil
        )

        let history = RuntimeVitalRecorderHistory(
            observations: [observation],
            recorderIngressStatusRead: ingressRead
        )

        XCTAssertEqual(history.recorders.first { $0.vrcode == "VR_A" }?.redisIPSync?.status, .verified)
        XCTAssertEqual(history.recorders.first { $0.vrcode == "VR_A" }?.redisIPSync?.redisKey, "ip_VR_A")
        XCTAssertEqual(history.recorders.first { $0.vrcode == "VR_A" }?.redisIPSync?.ipSource, "x-forwarded-for")
        XCTAssertEqual(history.recorders.first { $0.vrcode == "VR_B" }?.redisIPSync?.status, .unknown)
        XCTAssertEqual(history.recorders.first { $0.vrcode == "VR_B" }?.redisIPSync?.redisKey, "ip_VR_B")
    }

    func testVitalRecorderHistoryKeepsRecorderIngressStatusUnavailableDistinctFromUnknown() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:12:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_A",
                    ip: "192.168.64.20",
                    lastSeenAt: "2026-05-26T00:12:00Z",
                    online: true
                ),
            ]
        )
        let ingressRead = RuntimeRecorderIngressStatusReadResult(
            readState: .commandFailed,
            httpStatus: RuntimeHTTPStatusText.failed,
            document: nil,
            readError: "curl failed"
        )

        let history = RuntimeVitalRecorderHistory(
            observations: [observation],
            recorderIngressStatusRead: ingressRead
        )

        XCTAssertEqual(history.recorders.first?.redisIPSync?.status, .unavailable)
        XCTAssertEqual(history.recorders.first?.redisIPSync?.lastFailure, "curl failed")
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
        XCTAssertEqual(history.activityHistory.source, .readModelProjection)
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
        let summary = RuntimeVitalRecorderSummary(
            recorderIngressStatusRead: nil,
            vitalDBObservation: observation
        )

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

    func testVitalRecorderActivityWindowEncodesNullableReadFieldsAsExplicitNull() throws {
        let window = RuntimeVitalRecorderActivityWindow(
            state: .empty,
            query: RuntimeVitalRecorderActivityWindowQuery(vrcode: "VR_A", pageIndex: nil),
            page: RuntimeVitalRecorderActivityWindowPage(
                index: 0,
                count: 1,
                windowSeconds: 3600,
                windowStartedAt: nil,
                windowEndedAt: nil,
                firstBucketStartedAt: nil,
                latestBucketStartedAt: nil
            ),
            buckets: [],
            latestSampleAt: nil,
            readError: nil
        )

        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(window)) as? [String: Any]
        )
        let pageJSON = try XCTUnwrap(json["page"] as? [String: Any])
        let decoded = try JSONDecoder().decode(
            RuntimeVitalRecorderActivityWindow.self,
            from: JSONEncoder().encode(window)
        )

        XCTAssertEqual(decoded.state, .empty)
        XCTAssertTrue(pageJSON["windowStartedAt"] is NSNull)
        XCTAssertTrue(pageJSON["windowEndedAt"] is NSNull)
        XCTAssertTrue(pageJSON["firstBucketStartedAt"] is NSNull)
        XCTAssertTrue(pageJSON["latestBucketStartedAt"] is NSNull)
        XCTAssertTrue(json["latestSampleAt"] is NSNull)
        XCTAssertTrue(json["readError"] is NSNull)
    }

    func testVitalRecorderActivityWindowPreservesReadFailure() throws {
        let window = RuntimeVitalRecorderActivityWindow(
            state: .readFailed,
            query: RuntimeVitalRecorderActivityWindowQuery(vrcode: "VR_A"),
            page: RuntimeVitalRecorderActivityWindowPage(
                index: 0,
                count: 1,
                windowSeconds: 3600,
                windowStartedAt: nil,
                windowEndedAt: nil,
                firstBucketStartedAt: nil,
                latestBucketStartedAt: nil
            ),
            buckets: [],
            latestSampleAt: nil,
            readError: "activity projection read failed"
        )

        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(window)) as? [String: Any]
        )
        let decoded = try JSONDecoder().decode(
            RuntimeVitalRecorderActivityWindow.self,
            from: JSONEncoder().encode(window)
        )

        XCTAssertEqual(decoded.state, .readFailed)
        XCTAssertEqual(decoded.readError, "activity projection read failed")
        XCTAssertEqual(json["readError"] as? String, "activity projection read failed")
        XCTAssertTrue(json["latestSampleAt"] is NSNull)
    }

    func testVitalRecorderRecordEncodesNullableFieldsAsExplicitNull() throws {
        let record = RuntimeVitalRecorderRecord(
            vrcode: "VR_NULL",
            status: .notObserved,
            lastIP: nil,
            version: nil,
            bedID: nil,
            bedName: nil,
            patientConnected: nil,
            firstSeenAt: nil,
            lastSeenAt: nil,
            observationCount: 0,
            duplicateObservationCount: 0,
            currentAnomalyCount: 0,
            latestAnomalyKind: nil,
            latestAnomalySeverity: nil,
            latestAnomalyMessage: nil,
            latestAnomalyObservedAt: nil,
            presentInLatestObservation: false,
            visibility: .visible,
            activityTimeline: nil,
            redisIPSync: nil
        )

        let encoded = try JSONEncoder().encode(record)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let decoded = try JSONDecoder().decode(RuntimeVitalRecorderRecord.self, from: encoded)
        let legacy = try JSONDecoder().decode(RuntimeVitalRecorderRecord.self, from: Data("""
        {
          "vrcode": "VR_LEGACY",
          "status": "notObserved",
          "visibility": "visible",
          "observationCount": 0,
          "duplicateObservationCount": 0,
          "currentAnomalyCount": 0,
          "presentInLatestObservation": false
        }
        """.utf8))

        XCTAssertEqual(decoded.vrcode, "VR_NULL")
        for field in [
            "lastIP",
            "version",
            "bedID",
            "bedName",
            "patientConnected",
            "firstSeenAt",
            "lastSeenAt",
            "latestAnomalyKind",
            "latestAnomalySeverity",
            "latestAnomalyMessage",
            "latestAnomalyObservedAt",
            "activityTimeline",
            "redisIPSync",
        ] {
            XCTAssertTrue(json[field] is NSNull, field)
        }
        XCTAssertEqual(legacy.vrcode, "VR_LEGACY")
        XCTAssertNil(legacy.activityTimeline)
        XCTAssertNil(legacy.redisIPSync)
    }

    func testVitalBedRecordEncodesNullableFieldsAsExplicitNull() throws {
        let record = RuntimeVitalBedRecord(
            bedID: "bed-null",
            name: nil,
            vrcode: nil,
            linkedRecorderStatus: nil,
            linkedRecorderIP: nil,
            linkedRecorderLastSeenAt: nil,
            status: .notObserved,
            patientConnected: nil,
            firstSeenAt: nil,
            lastSeenAt: nil,
            observationCount: 0,
            duplicateObservationCount: 0,
            currentAnomalyCount: 0,
            latestAnomalyKind: nil,
            latestAnomalySeverity: nil,
            latestAnomalyMessage: nil,
            latestAnomalyObservedAt: nil,
            visibility: .visible
        )

        let encoded = try JSONEncoder().encode(record)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let decoded = try JSONDecoder().decode(RuntimeVitalBedRecord.self, from: encoded)
        let legacy = try JSONDecoder().decode(RuntimeVitalBedRecord.self, from: Data("""
        {
          "bedID": "bed-legacy",
          "visibility": "visible",
          "status": "notObserved",
          "observationCount": 0,
          "duplicateObservationCount": 0,
          "currentAnomalyCount": 0
        }
        """.utf8))

        XCTAssertEqual(decoded.bedID, "bed-null")
        for field in [
            "name",
            "vrcode",
            "linkedRecorderStatus",
            "linkedRecorderIP",
            "linkedRecorderLastSeenAt",
            "patientConnected",
            "firstSeenAt",
            "lastSeenAt",
            "latestAnomalyKind",
            "latestAnomalySeverity",
            "latestAnomalyMessage",
            "latestAnomalyObservedAt",
        ] {
            XCTAssertTrue(json[field] is NSNull, field)
        }
        XCTAssertEqual(legacy.bedID, "bed-legacy")
        XCTAssertNil(legacy.linkedRecorderStatus)
    }

    func testRecorderRedisIPSyncObservationEncodesNullableFieldsAsExplicitNull() throws {
        let observation = RuntimeRecorderRedisIPSyncObservation(status: .unavailable)

        let encoded = try JSONEncoder().encode(observation)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let decoded = try JSONDecoder().decode(RuntimeRecorderRedisIPSyncObservation.self, from: encoded)

        XCTAssertEqual(decoded.status, .unavailable)
        for field in [
            "redisKey",
            "selectedIp",
            "ipSource",
            "redisValue",
            "lastWriteAt",
            "lastVerifiedAt",
            "lastFailure",
        ] {
            XCTAssertTrue(json[field] is NSNull, field)
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

        let summary = RuntimeVitalRecorderSummary(
            recorderIngressStatusRead: nil,
            vitalDBObservation: observation
        )

        XCTAssertEqual(summary.knownRecorders, 2)
        XCTAssertEqual(summary.onlineRecorders, 1)
        XCTAssertEqual(summary.staleRecorders, 1)
        XCTAssertEqual(summary.latestRecorder?.vrcode, "VR_A")
        XCTAssertEqual(summary.latestRecorder?.ip, "192.168.64.10")
    }

    func testVitalRecorderSummaryUsesExplicitStatusEvaluationTime() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                .init(
                    vrcode: "VR_STALE_SUMMARY",
                    ip: "192.168.64.10",
                    lastSeenAt: "2026-05-26T00:01:00Z",
                    online: true
                ),
            ]
        )

        let summary = RuntimeVitalRecorderSummary(
            recorderIngressStatusRead: nil,
            vitalDBObservation: observation,
            statusEvaluationTime: "2026-05-26T00:20:00Z"
        )

        XCTAssertEqual(summary.knownRecorders, 1)
        XCTAssertEqual(summary.onlineRecorders, 0)
        XCTAssertEqual(summary.staleRecorders, 1)
    }

    func testVitalRecorderSummaryDoesNotUseRecorderIngressActivityForCurrentRecorderStatus() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:12:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                .init(
                    vrcode: "VR_RECONNECTED",
                    ip: "192.168.64.20",
                    lastSeenAt: "2026-05-26T00:00:00Z",
                    online: true,
                    stale: true
                ),
            ]
        )
        let recorderIngressStatusRead = RuntimeRecorderIngressStatusReadResult(
            httpStatus: "200",
            document: RuntimeRecorderIngressStatusDocument(
                activeRecorderConnections: 1,
                recorders: [
                    RuntimeRecorderConnectionObservation(
                        vrcode: "VR_RECONNECTED",
                        activeConnections: 1,
                        selectedIp: "192.168.64.20",
                        lastSeenAt: "2026-05-26T00:11:45Z"
                    ),
                ]
            ),
            readError: nil
        )

        let summary = RuntimeVitalRecorderSummary(
            recorderIngressStatusRead: recorderIngressStatusRead,
            vitalDBObservation: observation
        )

        XCTAssertEqual(summary.activeConnections, 1)
        XCTAssertEqual(summary.knownRecorders, 1)
        XCTAssertEqual(summary.onlineRecorders, 0)
        XCTAssertEqual(summary.staleRecorders, 1)
        XCTAssertEqual(summary.latestRecorder?.vrcode, "VR_RECONNECTED")
        XCTAssertEqual(summary.latestRecorder?.lastSeenAt, "2026-05-26T00:00:00Z")
    }

    func testVitalRecorderSummaryRequiresExplicitRecorderIngressStatusRead() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:12:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                .init(
                    vrcode: "VR_RECONNECTED",
                    ip: "192.168.64.20",
                    lastSeenAt: "2026-05-26T00:00:00Z",
                    online: true,
                    stale: true
                ),
            ]
        )

        let summary = RuntimeVitalRecorderSummary(
            recorderIngressStatusRead: nil,
            vitalDBObservation: observation
        )

        XCTAssertNil(summary.activeConnections)
        XCTAssertEqual(summary.knownRecorders, 1)
        XCTAssertEqual(summary.onlineRecorders, 0)
        XCTAssertEqual(summary.staleRecorders, 1)
        XCTAssertEqual(summary.latestRecorder?.vrcode, "VR_RECONNECTED")
        XCTAssertEqual(summary.latestRecorder?.lastSeenAt, "2026-05-26T00:00:00Z")
    }

    func testRuntimeControlOverviewDoesNotFallbackToStatusVitalDBObservation() throws {
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
        let status = RuntimeStatus()

        let unavailableOverview = RuntimeControlOverview(
            status: status,
            settings: RuntimeSettings(),
            release: RuntimeReleaseInfo(helperVersion: "0.1.0", minimumUpdaterVersion: "0.1.0", vitalServerVersion: "0.0.0", services: []),
            install: RuntimeInstallInfo(),
            vitalDBObservation: staleObservation,
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
        XCTAssertEqual(unavailableOverview.vitalDBObservationSnapshot.state, .unavailable)
        XCTAssertEqual(unavailableOverview.vitalRecorder.source, .unavailable)
        XCTAssertNil(unavailableOverview.vitalRecorder.knownRecorders)
        XCTAssertNil(unavailableOverview.vitalRecorder.activeConnections)
        XCTAssertEqual(unavailableOverview.conditions, [
            RuntimeControlCondition(
                type: "VitalDBObservationReady",
                status: .unknown,
                reason: "Unavailable",
                message: "sqlite=read failed"
            ),
        ])
        let unavailableJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(unavailableOverview)) as? [String: Any]
        )
        let unavailableSnapshotJSON = try XCTUnwrap(
            unavailableJSON["vitalDBObservationSnapshot"] as? [String: Any]
        )
        let unavailableConditionsJSON = try XCTUnwrap(unavailableJSON["conditions"] as? [[String: Any]])
        XCTAssertTrue(unavailableJSON["vitalDBObservation"] is NSNull)
        XCTAssertTrue(unavailableSnapshotJSON["observation"] is NSNull)
        XCTAssertEqual(unavailableSnapshotJSON["readError"] as? String, "sqlite=read failed")
        XCTAssertEqual(unavailableConditionsJSON.first?["message"] as? String, "sqlite=read failed")
        XCTAssertTrue(unavailableConditionsJSON.first?["observedAt"] is NSNull)
        XCTAssertEqual(loadedOverview.vitalDBObservation?.recorders.map(\.vrcode), ["FRESH"])
        XCTAssertEqual(loadedOverview.vitalRecorder.latestRecorder?.vrcode, "FRESH")
        XCTAssertEqual(loadedOverview.conditions, [
            RuntimeControlCondition(
                type: "VitalDBObservationReady",
                status: .trueValue,
                reason: "Loaded",
                observedAt: "2026-05-26T00:00:00Z"
            ),
        ])
    }

    func testVitalRecorderSummaryDoesNotInferRecorderStateFromRecorderIngressConnections() {
        let recorderIngressStatusRead = RuntimeRecorderIngressStatusReadResult(
            httpStatus: "200",
            document: RuntimeRecorderIngressStatusDocument(
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
            readError: nil
        )

        let summary = RuntimeVitalRecorderSummary(
            recorderIngressStatusRead: recorderIngressStatusRead,
            vitalDBObservation: nil
        )

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

    func testVitalRecorderSummaryWithoutExplicitInputsIsUnavailable() {
        let summary = RuntimeVitalRecorderSummary(
            recorderIngressStatusRead: nil,
            vitalDBObservation: nil
        )

        XCTAssertEqual(summary.source, .unavailable)
        XCTAssertNil(summary.activeConnections)
        XCTAssertNil(summary.knownRecorders)
        XCTAssertNil(summary.onlineRecorders)
        XCTAssertNil(summary.staleRecorders)
        XCTAssertNil(summary.knownBeds)
        XCTAssertNil(summary.recorderAnomalies)
        XCTAssertNil(summary.observedAt)
        XCTAssertNil(summary.latestRecorder)
    }

    func testVitalRecorderSummaryDoesNotDefaultMissingRecorderIngressConnectionsToZero() {
        let summary = RuntimeVitalRecorderSummary(
            recorderIngressStatusRead: nil,
            vitalDBObservation: nil
        )

        XCTAssertEqual(summary.source, .unavailable)
        XCTAssertNil(summary.activeConnections)
        XCTAssertNil(summary.knownRecorders)
    }

    private func fixedDate(
        year: Int,
        month: Int,
        day: Int,
        calendar: Calendar
    ) throws -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        return try XCTUnwrap(calendar.date(from: components))
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
