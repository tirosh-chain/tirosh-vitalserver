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

    func testPlatformStateRoundTripsExplicitCurrentFieldsThroughJSON() throws {
        let status = PlatformState(
            runtimeInstallationState: .executable,
            services: [
                PlatformServiceStatus(role: .runtimeProvider, state: .loaded),
                PlatformServiceStatus(role: .publicProxy, state: .loaded),
                PlatformServiceStatus(role: .watchdog, state: .loaded),
            ],
            platformHealth: .healthy,
            readIssues: [PlatformStateReadIssue(source: "hostProxyHTTP", message: "exitCode=28 stderr=timeout")],
            runtimeProviderState: .running,
            runtimeProviderErrors: [],
            runtimeEndpoint: "192.168.64.2",
            runtimeControllerHTTP: "200",
            publicProxyHTTP: "200"
        )

        XCTAssertTrue(RuntimeReadinessPolicy.isReady(status))

        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(PlatformState.self, from: encoded)

        XCTAssertEqual(decoded.readIssues, [
            PlatformStateReadIssue(source: "hostProxyHTTP", message: "exitCode=28 stderr=timeout"),
        ])
        XCTAssertEqual(decoded.runtimeProviderState, .running)
        XCTAssertEqual(decoded.runtimeProviderErrors ?? [], [])
        XCTAssertEqual(decoded.runtimeInstallationState, .executable)
        XCTAssertEqual(decoded.serviceState(.runtimeProvider), .loaded)
        XCTAssertEqual(decoded.serviceState(.publicProxy), .loaded)
        XCTAssertEqual(decoded.serviceState(.watchdog), .loaded)
        let encodedText = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertTrue(encodedText.contains(#""state":"running""#))
        XCTAssertTrue(encodedText.contains(#""readError":null"#))
        XCTAssertFalse(encodedText.contains(#""state":"loaded""#))
        XCTAssertFalse(encodedText.contains("guestService"))
        XCTAssertFalse(encodedText.contains("guestStackProbeErrors"))
        XCTAssertFalse(encodedText.contains("cpuUsagePercent"))
        XCTAssertFalse(encodedText.contains("vitalServerMemory"))
        XCTAssertFalse(encodedText.contains("systemDisk"))
        XCTAssertTrue(RuntimeReadinessPolicy.isReady(decoded))
    }

    func testPlatformServiceStateRequiresCanonicalStateAndExplicitReadError() throws {
        let missingReadError = Data(#"{"role":"runtime-provider","state":"running"}"#.utf8)
        let legacyLoaded = Data(#"{"role":"runtime-provider","state":"loaded","readError":null}"#.utf8)
        let failedWithoutReason = Data(#"{"role":"runtime-provider","state":"read-failed","readError":null}"#.utf8)
        let unavailableWithoutReason = Data(#"{"role":"runtime-provider","state":"unavailable","readError":null}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(PlatformServiceStatus.self, from: missingReadError))
        XCTAssertThrowsError(try JSONDecoder().decode(PlatformServiceStatus.self, from: legacyLoaded))
        XCTAssertThrowsError(try JSONDecoder().decode(PlatformServiceStatus.self, from: failedWithoutReason))
        XCTAssertThrowsError(try JSONDecoder().decode(PlatformServiceStatus.self, from: unavailableWithoutReason))

        let permissionDenied = PlatformServiceStatus(
            role: .publicProxy,
            state: .permissionDenied,
            readError: "service manager access denied"
        )
        let decoded = try JSONDecoder().decode(
            PlatformServiceStatus.self,
            from: JSONEncoder().encode(permissionDenied)
        )
        XCTAssertEqual(decoded.state, .permissionDenied)
        XCTAssertEqual(decoded.readError, "service manager access denied")
        XCTAssertEqual(decoded.runtimeServiceState, .permissionDenied("service manager access denied"))
    }

    func testPlatformStateRejectsLegacyLoadedBooleanPayload() throws {
        let legacyPayload = Data("""
        {
          "runtimeInstalled": true,
          "vmServiceLoaded": false,
          "proxyServiceLoaded": false,
          "guestLogSyncServiceLoaded": false,
          "watchdogServiceLoaded": false,
          "readIssues": [],
          "failureReasons": []
        }
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(PlatformState.self, from: legacyPayload))
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
            RuntimeLogArchiveSettingsReadInput(
                retentionDays: 10,
                maximumGiB: 3,
                runtimeControlPort: 18444
            ),
            to: RuntimeSettings()
        )

        XCTAssertEqual(settings.logArchiveRetentionDays, 10)
        XCTAssertEqual(settings.logArchiveMaximumGiB, 3)
        XCTAssertEqual(settings.runtimeControlPort, 18444)
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

    func testRuntimeSettingsReadPolicyPreservesInvalidRuntimeControlPortAsExplicitReadIssue() {
        let settings = RuntimeSettingsReadPolicy.applyLogArchiveSettings(
            RuntimeLogArchiveSettingsReadInput(
                retentionDays: 10,
                maximumGiB: 3,
                runtimeControlPort: 65_536
            ),
            to: RuntimeSettings()
        )

        XCTAssertEqual(settings.runtimeControlPort, RuntimeSettingsInitialValues.runtimeControlPort)
        XCTAssertEqual(settings.readIssues, [
            RuntimeSettingsReadIssue(
                source: "runtimeControlSettings.runtimeControlPort",
                message: "runtimeControlPort is out of range: 65536"
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
            logArchiveSettings: .loaded(RuntimeLogArchiveSettingsReadInput(
                retentionDays: 8,
                maximumGiB: 2,
                runtimeControlPort: 18444
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
        XCTAssertEqual(settings.backupScheduleTimes, ["03:15", "15:15"])
        XCTAssertEqual(settings.backupRetentionCount, 12)
        XCTAssertEqual(settings.logArchiveRetentionDays, 8)
        XCTAssertEqual(settings.logArchiveMaximumGiB, 2)
        XCTAssertEqual(settings.runtimeControlPort, 18444)
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

        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeDiagnosticsArtifactFileNames.runtimeStatus)"))
        XCTAssertTrue(destinations.contains("diagnostics/host/runtime-state.sqlite"))
        XCTAssertTrue(destinations.contains("diagnostics/host/\(RuntimeDiagnosticsArtifactFileNames.hostRuntimeStateEvents)"))
        XCTAssertTrue(destinations.contains("diagnostics/host/\(RuntimeDiagnosticsArtifactFileNames.hostRuntimeState)"))
        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeDiagnosticsArtifactFileNames.runtimeEvents)"))
        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeDiagnosticsArtifactFileNames.runtimeObservabilityDB)"))
        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeDiagnosticsArtifactFileNames.runtimeObservabilityDB)-wal"))
        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeDiagnosticsArtifactFileNames.runtimeObservabilityDB)-shm"))
        XCTAssertTrue(destinations.contains("diagnostics/guest/\(RuntimeDiagnosticsArtifactFileNames.runtimeObservation)"))
        XCTAssertTrue(destinations.contains("diagnostics/guest/\(RuntimeBootstrapEvidenceFileNames.vmIP)"))
        XCTAssertTrue(destinations.contains("diagnostics/runtime/vm-config.json"))
        XCTAssertTrue(destinations.contains("diagnostics/runtime/runtime-version.json"))
        XCTAssertTrue(destinations.contains("diagnostics/guest/runtime-config.json"))
        XCTAssertTrue(destinations.contains("diagnostics/host/ai.tirosh.vitalserver.helper.proxy.plist"))
        XCTAssertTrue(destinations.contains("diagnostics/host/vitalserver-nginx.conf"))
        XCTAssertTrue(destinations.contains("guest/guest-observability"))
        XCTAssertTrue(destinations.contains("helper-message.log"))

        let runtimeEventSet = rotated.first { $0.sourceID == .runtimeEvents }
        XCTAssertEqual(runtimeEventSet?.sourceFilePrefix, "\(RuntimeDiagnosticsArtifactFileNames.runtimeEvents).")
        XCTAssertEqual(runtimeEventSet?.relativeDestinationDirectory, "diagnostics/status")
        XCTAssertEqual(runtimeEventSet?.destinationFilePrefix, "\(RuntimeDiagnosticsArtifactFileNames.runtimeEvents).")
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

        XCTAssertEqual(bootstrap?.sourceFileName, RuntimeLogArtifactFileNames.bootstrapLog)
        XCTAssertEqual(bootstrap?.destinationScope, .guestLogs)
        XCTAssertEqual(bootstrap?.destinationFileName, RuntimeLogArtifactFileNames.bootstrapLog)
        XCTAssertEqual(bootstrap?.archivePrefix, "guest-bootstrap.log")

        XCTAssertEqual(command?.sourceFileName, RuntimeLogArtifactFileNames.managerCommandLog)
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

    func testActiveOperationPolicyUsesExplicitOperationForPresentationState() {
        let updating = PlatformState(runtimeInstallationState: .missing, platformHealth: .healthy)
        let recovering = PlatformState(runtimeInstallationState: .missing, platformHealth: .recovering)

        XCTAssertTrue(RuntimeActiveOperationPolicy.isUpdateInProgress(updating, operation: .applyBundle))
        XCTAssertFalse(RuntimeActiveOperationPolicy.isRecoveryInProgress(updating, operation: .applyBundle))
        XCTAssertFalse(RuntimeActiveOperationPolicy.isUpdateInProgress(recovering, operation: .applyBundle))
        XCTAssertTrue(RuntimeActiveOperationPolicy.isRecoveryInProgress(recovering, operation: .applyBundle))
        XCTAssertTrue(RuntimeActiveOperationPolicy.isRecoveryInProgress(recovering, operation: .rollback))
        XCTAssertFalse(RuntimeActiveOperationPolicy.isRecoveryInProgress(recovering, operation: nil))
    }

    func testActiveOperationPolicyTreatsInitializingRuntimeStateAsInitializationInProgress() {
        let initializing = PlatformState(runtimeInstallationState: .missing, platformHealth: .initializing)

        XCTAssertTrue(RuntimeActiveOperationPolicy.isInitializationInProgress(initializing))
    }

    func testActiveOperationPolicyUsesInitializingStatusForProvisionedInstallState() {
        let status = PlatformState(runtimeInstallationState: .missing, platformHealth: .initializing)

        XCTAssertTrue(RuntimeActiveOperationPolicy.isInitializationInProgress(status))
    }

    func testActiveOperationPolicyStopsUsingProvisionedInstallStateAfterRuntimeIsReady() {
        let status = PlatformState(
            runtimeInstallationState: .executable,
            services: [
                PlatformServiceStatus(role: .runtimeProvider, state: .loaded),
                PlatformServiceStatus(role: .publicProxy, state: .loaded),
                PlatformServiceStatus(role: .watchdog, state: .loaded),
            ],
            platformHealth: .healthy,
            runtimeEndpoint: "192.168.64.2",
            runtimeControllerHTTP: "200",
            publicProxyHTTP: "200"
        )

        XCTAssertFalse(RuntimeActiveOperationPolicy.isInitializationInProgress(status))
    }

    func testActiveOperationPolicyTreatsCompletedInstallStateDocumentAsTerminal() {
        let status = PlatformState(runtimeInstallationState: .missing, platformHealth: .degraded)

        XCTAssertFalse(RuntimeActiveOperationPolicy.isInitializationInProgress(status))
    }

    func testRuntimeStatusIncludesDataDirectoryStats() throws {
        let status = PlatformState(
            runtimeInstallationState: .missing,
            dataStorageError: "volume read failed",
            dataDirectoryStats: RuntimeDataDirectoryStats(fileCount: 2, sizeBytes: 1024)
        )

        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(PlatformState.self, from: encoded)

        XCTAssertEqual(decoded.dataStorageError, "volume read failed")
        XCTAssertEqual(decoded.dataDirectoryStats?.fileCount, 2)
        XCTAssertEqual(decoded.dataDirectoryStats?.sizeBytes, 1024)
    }

    func testRuntimeInstallOperationStatePreservesInstallReadMeanings() {
        let installDocument = RuntimeInstallStateDocument(
            state: .stepStarted,
            mode: .full,
            currentStep: .replaceRootfsBase,
            updatedAt: "2026-07-08T00:00:00Z",
            message: "install step running"
        )
        let loaded = RuntimeInstallOperationState.fromInstallStateRead(
            RuntimeInstallStateRead.loaded(installDocument)
        )
        let unavailable = RuntimeInstallOperationState.fromInstallStateRead(
            RuntimeInstallStateRead.unavailable()
        )
        let statusOperationOnly = PlatformOperationState(
            activeOperation: nil,
            install: RuntimeInstallOperationState.fromInstallStateRead(
                RuntimeInstallStateRead.unavailable()
            )
        )
        let installOperationState = PlatformOperationState(
            activeOperation: nil,
            install: loaded
        )
        let failed = RuntimeInstallOperationState.fromInstallStateRead(
            RuntimeInstallStateRead.failed("runtime install state decode failed")
        )

        XCTAssertEqual(loaded.state, .loaded)
        XCTAssertEqual(loaded.document, installDocument)
        XCTAssertNil(loaded.readError)

        XCTAssertEqual(unavailable.state, .unavailable)
        XCTAssertNil(unavailable.document)
        XCTAssertNil(unavailable.readError)

        XCTAssertNil(statusOperationOnly.activeOperation)
        XCTAssertNil(statusOperationOnly.operationForPresentation)
        XCTAssertNil(installOperationState.activeOperation)
        XCTAssertNil(installOperationState.operationForPresentation)

        XCTAssertEqual(failed.state, .failed)
        XCTAssertNil(failed.document)
        XCTAssertEqual(failed.readError, "runtime install state decode failed")
    }

    func testPlatformOperationStateDoesNotTreatProvisionedInstallDocumentAsActiveInstall() {
        let provisioned = RuntimeInstallStateDocument(
            state: .provisioned,
            mode: .provision,
            updatedAt: "2026-07-08T00:00:00Z",
            message: "runtime install provisioned"
        )
        let installRead = RuntimeInstallOperationState.fromInstallStateRead(
            RuntimeInstallStateRead.loaded(provisioned)
        )

        let operationState = PlatformOperationState(
            activeOperation: nil,
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

    func testRuntimeWorkflowOperationStateResourceRoundTripsExplicitOwnerState() throws {
        let document = RuntimeWorkflowOperationStateDocument(
            operationID: "operation-1",
            operation: .applyBundle,
            phase: .running,
            currentStep: .replaceRootfsBase,
            stepStatus: .started,
            message: "replacing rootfs",
            reasonCodes: [],
            startedAt: "2026-07-14T06:00:00Z",
            updatedAt: "2026-07-14T06:01:00Z",
            completedAt: nil,
            revision: 3
        )
        let state = PlatformOperationState(
            activeOperation: nil,
            install: .unavailable(),
            workflow: .loaded(document)
        )

        let decoded = try JSONDecoder().decode(
            PlatformOperationState.self,
            from: JSONEncoder().encode(state)
        )

        XCTAssertEqual(decoded.workflow.state, .loaded)
        XCTAssertEqual(decoded.workflow.document, document)
        XCTAssertNil(decoded.workflow.readError)
    }

    func testPlatformOperationStateUsesOnlyExplicitNonterminalWorkflowAsActiveOperation() {
        let running = RuntimeWorkflowOperationStateDocument(
            operationID: "install-1",
            operation: .install,
            phase: .running,
            currentStep: .provisionVMDisk,
            stepStatus: .started,
            message: "installing",
            reasonCodes: [],
            startedAt: "2026-07-14T06:00:00Z",
            updatedAt: "2026-07-14T06:01:00Z",
            completedAt: nil,
            revision: 2
        )
        let completed = RuntimeWorkflowOperationStateDocument(
            operationID: running.operationID,
            operation: running.operation,
            phase: .completed,
            currentStep: nil,
            stepStatus: nil,
            message: "installed",
            reasonCodes: [],
            startedAt: running.startedAt,
            updatedAt: "2026-07-14T06:02:00Z",
            completedAt: "2026-07-14T06:02:00Z",
            revision: 3
        )

        XCTAssertEqual(PlatformOperationState(
            activeOperation: nil,
            install: .unavailable(),
            workflow: .loaded(running)
        ).activeOperation, .install)
        XCTAssertNil(PlatformOperationState(
            activeOperation: nil,
            install: .unavailable(),
            workflow: .loaded(completed)
        ).activeOperation)
    }

    func testPlatformOperationStateEncodesNullableOperationFieldsAsExplicitNull() throws {
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
        let operationState = PlatformOperationState(
            activeOperation: nil,
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

        XCTAssertEqual(json["activeOperation"] as? String, "apply-bundle")
        XCTAssertTrue(install["readError"] is NSNull)
        XCTAssertTrue(installDocumentJSON["currentStep"] is NSNull)
        XCTAssertTrue(installDocumentJSON["message"] is NSNull)
        XCTAssertTrue(lease["readError"] is NSNull)
        XCTAssertTrue(lease["staleReason"] is NSNull)
        XCTAssertTrue(leaseDocumentJSON["ownerPID"] is NSNull)
        XCTAssertTrue(leaseDocumentJSON["expiresAt"] is NSNull)
        XCTAssertTrue(leaseDocumentJSON["message"] is NSNull)
    }

    func testPlatformOperationStateRequiresExplicitOwnerSubresourceFields() throws {
        for payload in [
            """
            {"install": {"state": "unavailable", "document": null, "readError": null}, "lease": {"state": "unavailable", "document": null, "readError": null, "staleReason": null}}
            """,
            """
            {"activeOperation": null, "lease": {"state": "unavailable", "document": null, "readError": null, "staleReason": null}}
            """,
            """
            {"activeOperation": null, "install": {"state": "unavailable", "readError": null}, "lease": {"state": "unavailable", "document": null, "readError": null, "staleReason": null}}
            """,
            """
            {"activeOperation": null, "install": {"state": "unavailable", "document": null}, "lease": {"state": "unavailable", "document": null, "readError": null, "staleReason": null}}
            """,
            """
            {"activeOperation": null, "install": {"state": "unavailable", "document": null, "readError": null}, "lease": {"state": "unavailable", "readError": null, "staleReason": null}}
            """,
            """
            {"activeOperation": null, "install": {"state": "unavailable", "document": null, "readError": null}, "lease": {"state": "unavailable", "document": null, "staleReason": null}}
            """,
            """
            {"activeOperation": null, "install": {"state": "unavailable", "document": null, "readError": null}, "lease": {"state": "unavailable", "document": null, "readError": null}}
            """,
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(PlatformOperationState.self, from: Data(payload.utf8)))
        }
    }

    func testPlatformOperationStateRejectsInvalidLoadedFailedAndStaleSubresources() throws {
        for payload in [
            """
            {"activeOperation": null, "install": {"state": "loaded", "document": null, "readError": null}, "lease": {"state": "unavailable", "document": null, "readError": null, "staleReason": null}}
            """,
            """
            {"activeOperation": null, "install": {"state": "failed", "document": null, "readError": ""}, "lease": {"state": "unavailable", "document": null, "readError": null, "staleReason": null}}
            """,
            """
            {"activeOperation": null, "install": {"state": "unavailable", "document": null, "readError": null}, "lease": {"state": "loaded", "document": null, "readError": null, "staleReason": null}}
            """,
            """
            {"activeOperation": null, "install": {"state": "unavailable", "document": null, "readError": null}, "lease": {"state": "failed", "document": null, "readError": " ", "staleReason": null}}
            """,
            """
            {"activeOperation": null, "install": {"state": "unavailable", "document": null, "readError": null}, "lease": {"state": "stale", "document": null, "readError": null, "staleReason": "expired"}}
            """,
            """
            {"activeOperation": null, "install": {"state": "unavailable", "document": null, "readError": null}, "lease": {"state": "stale", "document": {"schemaVersion": 1, "operationId": "operation-1", "operation": "apply-bundle", "ownerPID": null, "startedAt": "2026-07-08T00:00:00Z", "heartbeatAt": "2026-07-08T00:00:01Z", "expiresAt": null, "message": null}, "readError": null, "staleReason": ""}}
            """,
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(PlatformOperationState.self, from: Data(payload.utf8)))
        }
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

    func testRuntimeEventHistoryPreservesExplicitReadMetadata() throws {
        let history = RuntimeEventHistory(
            events: [],
            nextCursor: "opaque-cursor",
            matchingCount: 3,
            readError: "sqlite=read failed"
        )

        let encoded = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(RuntimeEventHistory.self, from: encoded)
        let failedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(RuntimeEventHistory.failed(readError: "jsonl=read failed"))
            ) as? [String: Any]
        )

        XCTAssertEqual(decoded.state, .readFailed)
        XCTAssertEqual(decoded.nextCursor, "opaque-cursor")
        XCTAssertEqual(decoded.matchingCount, 3)
        XCTAssertEqual(decoded.readError, "sqlite=read failed")
        XCTAssertTrue(failedJSON["nextCursor"] is NSNull)
        XCTAssertTrue(failedJSON["matchingCount"] is NSNull)
        XCTAssertEqual(failedJSON["readError"] as? String, "jsonl=read failed")
    }

    func testRuntimeEventHistoryRequiresEventsAndPaginationKeys() throws {
        for payload in [
            """
            {"nextCursor": null, "matchingCount": 0}
            """,
            """
            {"events": [], "matchingCount": 0}
            """,
            """
            {"events": [], "nextCursor": null}
            """,
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(RuntimeEventHistory.self, from: Data(payload.utf8)))
        }

        let decoded = try JSONDecoder().decode(RuntimeEventHistory.self, from: Data("""
        {
          "events": [],
          "nextCursor": null,
          "matchingCount": null
        }
        """.utf8))
        XCTAssertEqual(decoded.events, [])
        XCTAssertNil(decoded.nextCursor)
        XCTAssertNil(decoded.matchingCount)
    }

    func testRuntimeCommandResultPreservesOutputIssuesAndRequiresCompletePayload() throws {
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
        let encodedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let decodedLaunchFailure = try JSONDecoder().decode(
            RuntimeCommandResult.self,
            from: JSONEncoder().encode(launchFailure)
        )

        XCTAssertEqual(decoded.outputIssues, result.outputIssues)
        XCTAssertEqual(decoded.executionIssue, nil)
        XCTAssertTrue(encodedJSON["executionIssue"] is NSNull)
        XCTAssertEqual(decodedLaunchFailure.executionIssue, launchFailure.executionIssue)

        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeCommandResult.self, from: Data("""
        {
          "exitCode": 0,
          "stdout": "ok",
          "stderr": "",
          "executionIssue": null
        }
        """.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeCommandResult.self, from: Data("""
        {
          "exitCode": 0,
          "stdout": "ok",
          "stderr": "",
          "outputIssues": []
        }
        """.utf8)))
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

    func testVitalDBObservationSnapshotRequiresExplicitNullableFieldsAndValidReadState() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeVitalDBObservationSnapshot.self, from: Data("""
        {
          "state": "unavailable",
          "readError": null
        }
        """.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeVitalDBObservationSnapshot.self, from: Data("""
        {
          "state": "loaded",
          "observation": null,
          "readError": null
        }
        """.utf8))) { error in
            XCTAssertTrue(String(describing: error).contains("loaded VitalDB observation snapshots must include observation"))
        }
        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeVitalDBObservationSnapshot.self, from: Data("""
        {
          "state": "failed",
          "observation": null,
          "readError": ""
        }
        """.utf8))) { error in
            XCTAssertTrue(String(describing: error).contains("failed VitalDB observation snapshots must include readError"))
        }
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

    func testVitalRelationshipHistoryPreservesExplicitPartialStateAndRequiresCompletePayload() throws {
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

        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeVitalRelationshipHistory.self, from: Data("""
        {
          "assignments": [],
          "events": [],
          "readError": "relationship read failed"
        }
        """.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeVitalRelationshipHistory.self, from: Data("""
        {
          "state": "readFailed",
          "assignments": [],
          "events": [],
          "readError": null
        }
        """.utf8))) { error in
            XCTAssertTrue(String(describing: error).contains("failed VitalDB relationship history must include readError"))
        }
        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeVitalRelationshipHistory.self, from: Data("""
        {
          "state": "partiallyLoaded",
          "assignments": [],
          "events": [],
          "readError": ""
        }
        """.utf8))) { error in
            XCTAssertTrue(
                String(describing: error).contains("partially loaded VitalDB relationship history must include readError")
            )
        }

        XCTAssertEqual(decoded.state, .partiallyLoaded)
        XCTAssertEqual(decoded.assignments.map(\.assignmentID), ["assignment-1"])
        XCTAssertEqual(decoded.readError, "events=read failed")
    }

    func testVitalRecorderHistoryPreservesReadStateAndExplicitNullableFields() throws {
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
        XCTAssertTrue(failedJSON["updatedAt"] is NSNull)
        XCTAssertTrue(failedJSON["recorderIngressStatusRead"] is NSNull)
        XCTAssertEqual(failedJSON["readError"] as? String, "observations=read failed")
    }

    func testVitalRecorderHistoryRequiresCompleteReadDocumentPayload() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeVitalRecorderHistory.self, from: Data("""
        {
          "state": "loaded",
          "updatedAt": null,
          "beds": [],
          "summary": {"totalRecorders": 0, "onlineRecorders": 0, "offlineRecorders": 0, "staleRecorders": 0, "notObservedRecorders": 0, "totalBeds": 0, "onlineBeds": 0, "offlineBeds": 0, "staleBeds": 0, "notObservedBeds": 0, "patientConnectedBeds": 0, "patientDisconnectedBeds": 0, "currentAnomalyCount": 0, "recorderIngressActiveConnections": null, "recorderIngressReadState": "notProvided", "recorderIngressReadError": null},
          "activityHistory": {"source": "notProvided", "bucketCount": 0, "earliestBucketStartedAt": null, "latestBucketStartedAt": null, "readError": null},
          "recorderIngressStatusRead": null,
          "readError": null
        }
        """.utf8)))

        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeVitalRecorderHistory.self, from: Data("""
        {
          "state": "loaded",
          "updatedAt": null,
          "recorders": [],
          "summary": {"totalRecorders": 0, "onlineRecorders": 0, "offlineRecorders": 0, "staleRecorders": 0, "notObservedRecorders": 0, "totalBeds": 0, "onlineBeds": 0, "offlineBeds": 0, "staleBeds": 0, "notObservedBeds": 0, "patientConnectedBeds": 0, "patientDisconnectedBeds": 0, "currentAnomalyCount": 0, "recorderIngressActiveConnections": null, "recorderIngressReadState": "notProvided", "recorderIngressReadError": null},
          "activityHistory": {"source": "notProvided", "bucketCount": 0, "earliestBucketStartedAt": null, "latestBucketStartedAt": null, "readError": null},
          "recorderIngressStatusRead": null,
          "readError": null
        }
        """.utf8)))

        for payload in [
            """
            {"updatedAt": null, "recorders": [], "beds": [], "summary": {"totalRecorders": 0, "onlineRecorders": 0, "offlineRecorders": 0, "staleRecorders": 0, "notObservedRecorders": 0, "totalBeds": 0, "onlineBeds": 0, "offlineBeds": 0, "staleBeds": 0, "notObservedBeds": 0, "patientConnectedBeds": 0, "patientDisconnectedBeds": 0, "currentAnomalyCount": 0, "recorderIngressActiveConnections": null, "recorderIngressReadState": "notProvided", "recorderIngressReadError": null}, "activityHistory": {"source": "notProvided", "bucketCount": 0, "earliestBucketStartedAt": null, "latestBucketStartedAt": null, "readError": null}, "recorderIngressStatusRead": null, "readError": null}
            """,
            """
            {"state": "loaded", "recorders": [], "beds": [], "summary": {"totalRecorders": 0, "onlineRecorders": 0, "offlineRecorders": 0, "staleRecorders": 0, "notObservedRecorders": 0, "totalBeds": 0, "onlineBeds": 0, "offlineBeds": 0, "staleBeds": 0, "notObservedBeds": 0, "patientConnectedBeds": 0, "patientDisconnectedBeds": 0, "currentAnomalyCount": 0, "recorderIngressActiveConnections": null, "recorderIngressReadState": "notProvided", "recorderIngressReadError": null}, "activityHistory": {"source": "notProvided", "bucketCount": 0, "earliestBucketStartedAt": null, "latestBucketStartedAt": null, "readError": null}, "recorderIngressStatusRead": null, "readError": null}
            """,
            """
            {"state": "loaded", "updatedAt": null, "recorders": [], "beds": [], "activityHistory": {"source": "notProvided", "bucketCount": 0, "earliestBucketStartedAt": null, "latestBucketStartedAt": null, "readError": null}, "recorderIngressStatusRead": null, "readError": null}
            """,
            """
            {"state": "loaded", "updatedAt": null, "recorders": [], "beds": [], "summary": {"totalRecorders": 0, "onlineRecorders": 0, "offlineRecorders": 0, "staleRecorders": 0, "notObservedRecorders": 0, "totalBeds": 0, "onlineBeds": 0, "offlineBeds": 0, "staleBeds": 0, "notObservedBeds": 0, "patientConnectedBeds": 0, "patientDisconnectedBeds": 0, "currentAnomalyCount": 0, "recorderIngressActiveConnections": null, "recorderIngressReadState": "notProvided", "recorderIngressReadError": null}, "recorderIngressStatusRead": null, "readError": null}
            """,
            """
            {"state": "loaded", "updatedAt": null, "recorders": [], "beds": [], "summary": {"totalRecorders": 0, "onlineRecorders": 0, "offlineRecorders": 0, "staleRecorders": 0, "notObservedRecorders": 0, "totalBeds": 0, "onlineBeds": 0, "offlineBeds": 0, "staleBeds": 0, "notObservedBeds": 0, "patientConnectedBeds": 0, "patientDisconnectedBeds": 0, "currentAnomalyCount": 0, "recorderIngressActiveConnections": null, "recorderIngressReadState": "notProvided", "recorderIngressReadError": null}, "activityHistory": {"source": "notProvided", "bucketCount": 0, "earliestBucketStartedAt": null, "latestBucketStartedAt": null, "readError": null}, "readError": null}
            """,
            """
            {"state": "loaded", "updatedAt": null, "recorders": [], "beds": [], "summary": {"totalRecorders": 0, "onlineRecorders": 0, "offlineRecorders": 0, "staleRecorders": 0, "notObservedRecorders": 0, "totalBeds": 0, "onlineBeds": 0, "offlineBeds": 0, "staleBeds": 0, "notObservedBeds": 0, "patientConnectedBeds": 0, "patientDisconnectedBeds": 0, "currentAnomalyCount": 0, "recorderIngressActiveConnections": null, "recorderIngressReadState": "notProvided", "recorderIngressReadError": null}, "activityHistory": {"source": "notProvided", "bucketCount": 0, "earliestBucketStartedAt": null, "latestBucketStartedAt": null, "readError": null}, "recorderIngressStatusRead": null}
            """,
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(RuntimeVitalRecorderHistory.self, from: Data(payload.utf8)))
        }
    }

    func testVitalRecorderActivityHistoryRequiresExplicitNullableFields() throws {
        for payload in [
            """
            {"source": "notProvided", "bucketCount": 0, "latestBucketStartedAt": null, "readError": null}
            """,
            """
            {"source": "notProvided", "bucketCount": 0, "earliestBucketStartedAt": null, "readError": null}
            """,
            """
            {"source": "notProvided", "bucketCount": 0, "earliestBucketStartedAt": null, "latestBucketStartedAt": null}
            """,
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(
                RuntimeVitalRecorderActivityHistory.self,
                from: Data(payload.utf8)
            ))
        }
    }

    func testVitalBedHistoryPreservesExplicitNullableFieldsAndRequiresCompletePayload() throws {
        let history = RuntimeVitalBedHistory(beds: [])
        let encoded = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(RuntimeVitalBedHistory.self, from: encoded)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(decoded.state, .loaded)
        XCTAssertTrue(json["updatedAt"] is NSNull)
        XCTAssertTrue(json["readError"] is NSNull)
        XCTAssertNotNil(json["summary"] as? [String: Any])

        for payload in [
            """
            {"updatedAt": null, "beds": [], "summary": {"knownBeds": 0, "onlineBeds": 0, "staleBeds": 0, "bedAssignments": 0, "bedAnomalies": 0}, "readError": null}
            """,
            """
            {"state": "loaded", "beds": [], "summary": {"knownBeds": 0, "onlineBeds": 0, "staleBeds": 0, "bedAssignments": 0, "bedAnomalies": 0}, "readError": null}
            """,
            """
            {"state": "loaded", "updatedAt": null, "beds": [], "readError": null}
            """,
            """
            {"state": "loaded", "updatedAt": null, "beds": [], "summary": {"knownBeds": 0, "onlineBeds": 0, "staleBeds": 0, "bedAssignments": 0, "bedAnomalies": 0}}
            """,
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(RuntimeVitalBedHistory.self, from: Data(payload.utf8)))
        }
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
        let decodedLoaded = try JSONDecoder().decode(
            RuntimeRecorderIngressStatusReadResult.self,
            from: JSONEncoder().encode(loaded)
        )
        let decodedFailed = try JSONDecoder().decode(
            RuntimeRecorderIngressStatusReadResult.self,
            from: JSONEncoder().encode(failed)
        )

        XCTAssertEqual(loadedJSON["readState"] as? String, "loaded")
        XCTAssertEqual(loadedJSON["httpStatus"] as? String, "200")
        XCTAssertNotNil(loadedJSON["document"] as? [String: Any])
        XCTAssertTrue(loadedJSON["readError"] is NSNull)
        XCTAssertEqual(decodedLoaded.readState, .loaded)
        XCTAssertEqual(decodedLoaded.httpStatus, "200")
        XCTAssertNotNil(decodedLoaded.document)
        XCTAssertNil(decodedLoaded.readError)
        XCTAssertEqual(failedJSON["readState"] as? String, "commandFailed")
        XCTAssertEqual(failedJSON["httpStatus"] as? String, RuntimeHTTPStatusText.failed)
        XCTAssertTrue(failedJSON["document"] is NSNull)
        XCTAssertEqual(failedJSON["readError"] as? String, "command-failed recorder ingress status")
        XCTAssertEqual(decodedFailed.readState, .commandFailed)
        XCTAssertEqual(decodedFailed.httpStatus, RuntimeHTTPStatusText.failed)
        XCTAssertNil(decodedFailed.document)
        XCTAssertEqual(decodedFailed.readError, "command-failed recorder ingress status")

        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeRecorderIngressStatusReadResult.self, from: Data("""
        {
          "readState": "readFailed",
          "readError": "recorder ingress read failed"
        }
        """.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeRecorderIngressStatusReadResult.self, from: Data("""
        {
          "readState": "loaded",
          "httpStatus": "200",
          "document": null,
          "readError": null
        }
        """.utf8))) { error in
            XCTAssertTrue(String(describing: error).contains("loaded recorder ingress status reads must include document"))
        }
        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeRecorderIngressStatusReadResult.self, from: Data("""
        {
          "readState": "readFailed",
          "httpStatus": "failed",
          "document": null,
          "readError": ""
        }
        """.utf8))) { error in
            XCTAssertTrue(String(describing: error).contains("readFailed recorder ingress status reads must include readError"))
        }
    }

    func testRedisRelayStatusRequiresCompleteOwnerDocumentPayload() throws {
        let status = RuntimeRedisRelayStatus(
            observedAt: "2026-07-01T00:00:00Z",
            enabled: true,
            state: "running",
            scope: nil,
            targetUrl: nil,
            targetUsernameConfigured: false,
            targetPasswordConfigured: false,
            settingsFingerprint: nil,
            batches: 0,
            totals: RuntimeRedisRelayBatch(),
            lastBatch: nil,
            lastSuccessAt: nil,
            lastErrorAt: nil,
            lastError: nil
        )

        let encodedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as? [String: Any]
        )
        let decoded = try JSONDecoder().decode(
            RuntimeRedisRelayStatus.self,
            from: JSONEncoder().encode(status)
        )

        XCTAssertEqual(encodedJSON["schemaVersion"] as? Int, 1)
        XCTAssertTrue(encodedJSON["scope"] is NSNull)
        XCTAssertTrue(encodedJSON["targetUrl"] is NSNull)
        XCTAssertTrue(encodedJSON["settingsFingerprint"] is NSNull)
        XCTAssertTrue(encodedJSON["lastBatch"] is NSNull)
        XCTAssertTrue(encodedJSON["lastSuccessAt"] is NSNull)
        XCTAssertTrue(encodedJSON["lastErrorAt"] is NSNull)
        XCTAssertTrue(encodedJSON["lastError"] is NSNull)
        XCTAssertEqual(decoded, status)

        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeRedisRelayStatus.self, from: Data("""
        {
          "schemaVersion": 1,
          "enabled": true,
          "state": "running",
          "scope": "vital_reconstruction",
          "targetUrl": null,
          "targetUsernameConfigured": false,
          "targetPasswordConfigured": false,
          "settingsFingerprint": null,
          "batches": 0,
          "totals": {"scanned": 0, "copied": 0, "published": 0, "unchanged": 0, "duplicates": 0, "skipped": 0, "denied": 0, "missing": 0, "errors": 0},
          "lastBatch": null,
          "lastSuccessAt": null,
          "lastErrorAt": null,
          "lastError": null
        }
        """.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeRedisRelayStatus.self, from: Data("""
        {
          "schemaVersion": 1,
          "observedAt": "2026-07-01T00:00:00Z",
          "enabled": true,
          "state": "running",
          "targetUrl": null,
          "targetUsernameConfigured": false,
          "targetPasswordConfigured": false,
          "settingsFingerprint": null,
          "batches": 0,
          "totals": {"scanned": 0, "copied": 0, "published": 0, "unchanged": 0, "duplicates": 0, "skipped": 0, "denied": 0, "missing": 0, "errors": 0},
          "lastBatch": null,
          "lastSuccessAt": null,
          "lastErrorAt": null,
          "lastError": null
        }
        """.utf8))) { error in
            XCTAssertTrue(String(describing: error).contains("scope"))
        }
        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeRedisRelayStatus.self, from: Data("""
        {
          "schemaVersion": 1,
          "observedAt": "2026-07-01T00:00:00Z",
          "enabled": true,
          "state": "running",
          "scope": "vital_reconstruction",
          "targetUsernameConfigured": false,
          "targetPasswordConfigured": false,
          "settingsFingerprint": null,
          "batches": 0,
          "totals": {"scanned": 0, "copied": 0, "published": 0, "unchanged": 0, "duplicates": 0, "skipped": 0, "denied": 0, "missing": 0, "errors": 0},
          "lastBatch": null,
          "lastSuccessAt": null,
          "lastErrorAt": null,
          "lastError": null
        }
        """.utf8))) { error in
            XCTAssertTrue(String(describing: error).contains("targetUrl"))
        }
        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeRedisRelayStatus.self, from: Data("""
        {
          "schemaVersion": 1,
          "observedAt": "2026-07-01T00:00:00Z",
          "enabled": true,
          "state": "running",
          "scope": "vital_reconstruction",
          "targetUrl": null,
          "targetUsernameConfigured": false,
          "targetPasswordConfigured": false,
          "settingsFingerprint": null,
          "batches": 0,
          "totals": {"scanned": 0, "published": 0, "unchanged": 0, "duplicates": 0, "skipped": 0, "denied": 0, "missing": 0, "errors": 0},
          "lastBatch": null,
          "lastSuccessAt": null,
          "lastErrorAt": null,
          "lastError": null
        }
        """.utf8))) { error in
            XCTAssertTrue(String(describing: error).contains("copied"))
        }
    }

    func testRedisRelayStatusReadResultEncodesExplicitReadEvidence() throws {
        let redisRelayStatus = RuntimeRedisRelayStatus(
            observedAt: "2026-07-01T00:00:00Z",
            enabled: true,
            state: "running",
            scope: "vital_reconstruction",
            targetUrl: "redis://relay.example:6379/0",
            targetUsernameConfigured: true,
            targetPasswordConfigured: true,
            settingsFingerprint: "relay-settings",
            batches: 3,
            totals: RuntimeRedisRelayBatch(copied: 8)
        )
        let loaded = RuntimeRedisRelayStatusReadResult(
            document: redisRelayStatus,
            readError: nil
        )
        let failed = RuntimeRedisRelayStatusReadResult(
            document: nil,
            readError: "decode-failed Redis Relay status"
        )

        let loadedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded)) as? [String: Any]
        )
        let failedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(failed)) as? [String: Any]
        )
        let decodedLoaded = try JSONDecoder().decode(
            RuntimeRedisRelayStatusReadResult.self,
            from: JSONEncoder().encode(loaded)
        )
        let decodedFailed = try JSONDecoder().decode(
            RuntimeRedisRelayStatusReadResult.self,
            from: JSONEncoder().encode(failed)
        )

        XCTAssertEqual(loadedJSON["readState"] as? String, "loaded")
        XCTAssertNotNil(loadedJSON["document"] as? [String: Any])
        XCTAssertTrue(loadedJSON["readError"] is NSNull)
        XCTAssertEqual(decodedLoaded.readState, .loaded)
        XCTAssertEqual(decodedLoaded.document, redisRelayStatus)
        XCTAssertNil(decodedLoaded.readError)
        XCTAssertEqual(failedJSON["readState"] as? String, "invalidResponse")
        XCTAssertTrue(failedJSON["document"] is NSNull)
        XCTAssertEqual(failedJSON["readError"] as? String, "decode-failed Redis Relay status")
        XCTAssertEqual(decodedFailed.readState, .invalidResponse)
        XCTAssertNil(decodedFailed.document)
        XCTAssertEqual(decodedFailed.readError, "decode-failed Redis Relay status")

        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeRedisRelayStatusReadResult.self, from: Data("""
        {
          "document": null,
          "readError": "Redis Relay status read failed"
        }
        """.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeRedisRelayStatusReadResult.self, from: Data("""
        {
          "readState": "loaded",
          "readError": null
        }
        """.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeRedisRelayStatusReadResult.self, from: Data("""
        {
          "readState": "loaded",
          "document": null,
          "readError": null
        }
        """.utf8))) { error in
            XCTAssertTrue(String(describing: error).contains("loaded Redis Relay status reads must include document"))
        }
        XCTAssertThrowsError(try JSONDecoder().decode(RuntimeRedisRelayStatusReadResult.self, from: Data("""
        {
          "readState": "readFailed",
          "document": null,
          "readError": ""
        }
        """.utf8))) { error in
            XCTAssertTrue(String(describing: error).contains("readFailed Redis Relay status reads must include readError"))
        }
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
            linkedRecorderVersion: nil,
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
            "linkedRecorderVersion",
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
        XCTAssertNil(legacy.linkedRecorderVersion)
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
