import Contracts
import RuntimeControl
import XCTest
import Errors

final class RuntimeControlStatusAssemblerTests: XCTestCase {
    func testMakeStatusDoesNotPublishResourceFieldsWithoutGuestStackResourceRead() {
        let status = PlatformStateAssembler.makePlatformState(
            proxyPortReadState: .loaded(19090),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.runtimeInstallationState, RuntimeFileState.executable)
        XCTAssertEqual(status.serviceState(.runtimeProvider), .loaded)
        XCTAssertEqual(status.serviceState(.publicProxy), .loaded)
        XCTAssertEqual(status.serviceState(.logSync), .loaded)
        XCTAssertEqual(status.serviceState(.sleepPrevention), .loaded)
        XCTAssertEqual(status.serviceState(.watchdog), .loaded)
        XCTAssertEqual(status.platformHealth, RuntimeState.healthy)
        XCTAssertNil(status.runtimeEndpoint)
        XCTAssertNil(status.runtimeProviderState)
        XCTAssertNil(status.runtimeProviderErrors)
        XCTAssertNil(status.runtimeControllerHTTP)
        XCTAssertNil(status.publicProxyHTTP)
        XCTAssertNil(status.dataStorage)
        XCTAssertEqual(status.publicProxyPort, 19090)
        XCTAssertEqual(status.readIssues, [PlatformStateReadIssue]())
    }

    func testMakeStatusDoesNotExposeActiveOperationFields() {
        let status = PlatformStateAssembler.makePlatformState(
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.platformHealth, .healthy)
        XCTAssertEqual(status.readIssues, [])
    }

    func testMakeStatusDoesNotPromoteStatusDocumentOperationFields() {
        let status = PlatformStateAssembler.makePlatformState(
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.platformHealth, .healthy)
        XCTAssertFalse(status.readIssues.contains { $0.source == "activeOperation" })
    }

    func testMakeStatusDoesNotExposeStatusDocumentReadIssueAsStatusField() {
        let status = PlatformStateAssembler.makePlatformState(
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.readIssues, [])
        XCTAssertEqual(status.platformHealth, .healthy)
    }

    func testMakeStatusBuildsCurrentHealthFromExplicitOwnerReads() {
        let status = PlatformStateAssembler.makePlatformState(
            proxyPortReadState: .missing("proxy launch daemon missing"),
            vmLifecycleRead: RuntimeVMLifecycleRead(
                document: RuntimeVMLifecycleDocument(
                    state: .failed,
                    startedAt: "2026-07-08T00:00:00Z",
                    updatedAt: "2026-07-08T00:00:05Z",
                    terminalReason: .launchFailed
                ),
                issue: nil
            ),
            liveDiagnostics: liveDiagnostics(vm: .notLoaded)
        )

        XCTAssertEqual(status.platformHealth, .critical)
        XCTAssertTrue(status.healthIssues.contains(.vmService("not loaded")))
        XCTAssertFalse(status.healthIssues.contains(.hostProxyConfigInvalid))
        XCTAssertFalse(status.healthIssues.contains { reason in
            if case .guestService = reason { return true }
            return false
        })
        XCTAssertTrue(status.healthIssues.contains(.vmLaunchFailed("launch-failed")))
    }

    func testMakeStatusDoesNotExposeProgressFields() {
        let status = PlatformStateAssembler.makePlatformState(
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.readIssues, [])
    }

    func testMakeStatusDoesNotPromoteProgressReadFailureToCurrentStatusIssue() {
        let status = PlatformStateAssembler.makePlatformState(
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertFalse(status.readIssues.contains(PlatformStateReadIssue(
            source: "runtimeProgress",
            message: "decode failed"
        )))
        XCTAssertEqual(status.platformHealth, .healthy)
    }

    func testMakeStatusUsesExplicitGuestAddressReadForCurrentVMIP() {
        let status = PlatformStateAssembler.makePlatformState(
            guestAddressRead: .loaded(address: "192.168.64.44", source: .platformAgent),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.runtimeEndpoint, "192.168.64.44")
        XCTAssertEqual(status.readIssues, [])
    }

    func testMakeStatusUsesExplicitVersionAndLatestBackupReads() {
        let status = PlatformStateAssembler.makePlatformState(
            runtimeVersionRead: RuntimeVersionRead(version: "2.0.0", issue: nil),
            latestBackupRead: RuntimeLatestBackupRead(path: "/backups/20260708T010000Z-before-2.0.0", issue: nil),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.installedVersion, "2.0.0")
        XCTAssertEqual(status.latestBackup, "/backups/20260708T010000Z-before-2.0.0")
        XCTAssertEqual(status.readIssues, [])
    }

    func testMakeStatusDoesNotPromoteVersionOrLatestBackupReadIssuesIntoCurrentHealth() {
        let status = PlatformStateAssembler.makePlatformState(
            runtimeVersionRead: RuntimeVersionRead(
                version: nil,
                issue: PlatformStateReadIssue(
                    source: "runtimeVersion",
                    message: "runtime version document missing path=/runtime/runtime-version.json"
                )
            ),
            latestBackupRead: RuntimeLatestBackupRead(
                path: nil,
                issue: PlatformStateReadIssue(
                    source: "latestBackup",
                    message: "backup directory inspection failed path=/runtime/backups reason=permission denied"
                )
            ),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertNil(status.installedVersion)
        XCTAssertNil(status.latestBackup)
        XCTAssertTrue(status.readIssues.contains(PlatformStateReadIssue(
            source: "runtimeVersion",
            message: "runtime version document missing path=/runtime/runtime-version.json"
        )))
        XCTAssertTrue(status.readIssues.contains(PlatformStateReadIssue(
            source: "latestBackup",
            message: "backup directory inspection failed path=/runtime/backups reason=permission denied"
        )))
        XCTAssertEqual(status.platformHealth, .healthy)
        XCTAssertEqual(status.healthIssues, [])
    }

    func testMakeStatusDoesNotPromoteGuestAddressReadFailureAsCurrentIssue() {
        let status = PlatformStateAssembler.makePlatformState(
            guestAddressRead: .readFailed("permission denied"),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertNil(status.runtimeEndpoint)
        XCTAssertFalse(status.readIssues.contains(PlatformStateReadIssue(
            source: "guestAddress",
            message: "guest-address-read-failed:permission denied"
        )))
        XCTAssertFalse(status.healthIssues.contains(.guestHTTP("guest-address-read-failed:permission denied")))
        XCTAssertEqual(status.platformHealth, .healthy)
    }

    func testMakeStatusUsesExplicitVMLifecycleReadForCurrentVMState() {
        let status = PlatformStateAssembler.makePlatformState(
            vmLifecycleRead: RuntimeVMLifecycleRead(
                document: RuntimeVMLifecycleDocument(
                    state: .failed,
                    startedAt: "2026-07-08T00:00:00Z",
                    updatedAt: "2026-07-08T00:01:00Z",
                    terminalReason: .guestDiskIO
                ),
                issue: nil
            ),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.runtimeProviderState, .failed)
        XCTAssertEqual(status.runtimeProviderErrors, [.guestDiskIO])
        XCTAssertEqual(status.readIssues, [])
    }

    func testMakeStatusPreservesVMLifecycleReadFailureAsIssue() {
        let status = PlatformStateAssembler.makePlatformState(
            vmLifecycleRead: RuntimeVMLifecycleRead(
                document: nil,
                issue: PlatformStateReadIssue(
                    source: "vmLifecycle",
                    message: "permission denied"
                )
            ),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertNil(status.runtimeProviderState)
        XCTAssertNil(status.runtimeProviderErrors)
        XCTAssertTrue(status.readIssues.contains(PlatformStateReadIssue(
            source: "vmLifecycle",
            message: "permission denied"
        )))
    }

    func testMakeStatusDoesNotAggregateRuntimeStackState() {
        let status = PlatformStateAssembler.makePlatformState(
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertFalse(status.healthIssues.contains { reason in
            if case .guestService = reason { return true }
            return false
        })
        XCTAssertFalse(status.healthIssues.contains { reason in
            if case .guestServiceObservationReadFailed = reason { return true }
            return false
        })
    }

    func testMakeStatusUsesExplicitProxyPortReadForCurrentProxyPort() {
        let status = PlatformStateAssembler.makePlatformState(
            proxyPortReadState: .loaded(19090),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.publicProxyPort, 19090)
        XCTAssertEqual(status.publicProxyPortReadState, .loaded(19090))
        XCTAssertEqual(status.readIssues, [])
    }

    func testMakeStatusDoesNotPromoteStatusDocumentOrProxyPortReadFailure() {
        let status = PlatformStateAssembler.makePlatformState(
            proxyPortReadState: .missing("proxy launch daemon plist missing path=/runtime/proxy.plist"),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertNil(status.publicProxyPort)
        XCTAssertEqual(
            status.publicProxyPortReadState,
            .missing("proxy launch daemon plist missing path=/runtime/proxy.plist")
        )
        XCTAssertFalse(status.readIssues.contains(PlatformStateReadIssue(
            source: "proxyPort",
            message: "proxy launch daemon plist missing path=/runtime/proxy.plist"
        )))
        XCTAssertFalse(status.healthIssues.contains(.hostProxyConfigInvalid))
        XCTAssertEqual(status.platformHealth, .healthy)
    }

    func testLiveDiagnosticsAssemblerPreservesExplicitManagedServiceStates() {
        let diagnostics = RuntimeLiveDiagnosticsAssembler.makeDiagnostics(
            runtimeLauncherPath: "/product/launcher",
            runtimeExecutableState: .executable,
            liveServiceStates: RuntimeLiveServiceStateReads(
                vm: .notLoaded,
                proxy: .readFailed("launchctl proxy failed"),
                guestLogSync: .loaded,
                sleepPrevention: .notLoaded,
                watchdog: .unknown("weird")
            )
        )

        XCTAssertEqual(diagnostics.runtimeInstallationState.isExecutable, true)
        XCTAssertEqual(diagnostics.vmService, RuntimeServiceStateRead(state: .notLoaded))
        XCTAssertEqual(
            diagnostics.proxyService,
            RuntimeServiceStateRead(state: .readFailed("launchctl proxy failed"))
        )
        XCTAssertEqual(diagnostics.watchdogService, RuntimeServiceStateRead(state: .unknown("weird")))
        XCTAssertEqual(diagnostics.guestLogSyncService, RuntimeServiceStateRead(state: .loaded))
        XCTAssertEqual(diagnostics.sleepPreventionService, RuntimeServiceStateRead(state: .notLoaded))
        XCTAssertTrue(diagnostics.readIssues.contains(PlatformStateReadIssue(
            source: "proxyService",
            message: "launchctl proxy failed"
        )))
        XCTAssertTrue(diagnostics.readIssues.contains(PlatformStateReadIssue(
            source: "watchdogService",
            message: "unknown service state: weird"
        )))
    }

    func testLiveDiagnosticsAssemblerReportsLiveServiceReadIssuesAndRuntimeInstallationIssue() {
        let diagnostics = RuntimeLiveDiagnosticsAssembler.makeDiagnostics(
            runtimeLauncherPath: "/product/launcher",
            runtimeExecutableState: .present,
            liveServiceStates: RuntimeLiveServiceStateReads(
                vm: .readFailed("launchctl vm failed"),
                proxy: .permissionDenied("launchctl proxy denied"),
                guestLogSync: .unknown("strange"),
                sleepPrevention: .loaded,
                watchdog: .notLoaded
            )
        )

        XCTAssertEqual(diagnostics.runtimeInstallationState.isExecutable, false)
        XCTAssertEqual(diagnostics.runtimeInstallationIssue, PlatformStateReadIssue(
            source: "runtimeInstallation",
            message: "runtime launcher is present but not executable path=/product/launcher"
        ))
        XCTAssertTrue(diagnostics.readIssues.contains(PlatformStateReadIssue(
            source: "vmService",
            message: "launchctl vm failed"
        )))
        XCTAssertTrue(diagnostics.readIssues.contains(PlatformStateReadIssue(
            source: "proxyService",
            message: "launchctl proxy denied"
        )))
        XCTAssertTrue(diagnostics.readIssues.contains(PlatformStateReadIssue(
            source: "guestLogSyncService",
            message: "unknown service state: strange"
        )))
    }

    func testHealthStatusAssemblerAppliesExplicitProbeReads() {
        let status = RuntimeHealthStatusAssembler.applyingHealthProbeReads(
            to: PlatformState(runtimeInstallationState: .missing, runtimeEndpoint: "192.168.64.8", publicProxyPort: 19090),
            reads: RuntimeHealthProbeReads(
                guestHTTP: RuntimeHTTPStatusRead(
                    status: "200",
                    issue: nil
                ),
                hostProxyHTTP: RuntimeHTTPStatusRead(
                    status: nil,
                    issue: PlatformStateReadIssue(source: "hostProxyHTTP", message: "exitCode=28 stderr=timeout")
                ),
                redisUIHTTP: RuntimeHTTPStatusRead(
                    status: "200",
                    issue: nil
                ),
                swaggerUIHTTP: RuntimeHTTPStatusRead(
                    status: "503",
                    issue: nil
                )
            )
        )

        XCTAssertEqual(status.runtimeControllerHTTP, "200")
        XCTAssertNil(status.publicProxyHTTP)
        XCTAssertEqual(status.readIssues, [
            PlatformStateReadIssue(source: "hostProxyHTTP", message: "exitCode=28 stderr=timeout"),
        ])
    }

    func testHealthStatusAssemblerMarksMissingProxyPortAsDisplayStatusWithoutReadIssue() {
        let status = RuntimeHealthStatusAssembler.applyingHealthProbeReads(
            to: PlatformState(runtimeInstallationState: .missing, runtimeEndpoint: "192.168.64.8", publicProxyPort: nil),
            reads: RuntimeHealthProbeReads(
                guestHTTP: nil,
                hostProxyHTTP: nil,
                redisUIHTTP: nil,
                swaggerUIHTTP: nil
            )
        )

        XCTAssertEqual(status.publicProxyHTTP, RuntimeHTTPStatusText.missingProxyPort)
        XCTAssertEqual(status.readIssues, [])
    }

    func testHealthStatusAssemblerMarksMissingVMIPAsDisplayStatusWithoutReadIssue() {
        let status = RuntimeHealthStatusAssembler.applyingHealthProbeReads(
            to: PlatformState(runtimeInstallationState: .missing, publicProxyPort: 19090),
            reads: RuntimeHealthProbeReads(
                guestHTTP: nil,
                hostProxyHTTP: RuntimeHTTPStatusRead(status: "200", issue: nil),
                redisUIHTTP: RuntimeHTTPStatusRead(status: "200", issue: nil),
                swaggerUIHTTP: RuntimeHTTPStatusRead(status: "200", issue: nil)
            )
        )

        XCTAssertEqual(status.runtimeControllerHTTP, RuntimeHTTPStatusText.missingVMIP)
        XCTAssertEqual(status.publicProxyHTTP, "200")
        XCTAssertEqual(status.readIssues, [])
    }

    func testLocalAPIStatusAssemblerAppliesExplicitHostReadWithoutChangingOtherStatusFields() {
        let status = RuntimeControlLocalAPIStatusAssembler.applyingLocalAPIStatus(
            to: PlatformState(
                runtimeInstallationState: .executable,
                platformHealth: .degraded,
                platformAPIHTTP: "500",
                platformAPIStartedAt: "stale"
            ),
            read: RuntimeControlLocalAPIStatusRead(
                http: "204",
                startedAt: "2026-05-30T00:02:00Z"
            )
        )

        XCTAssertEqual(status.runtimeInstallationState, .executable)
        XCTAssertEqual(status.platformHealth, .degraded)
        XCTAssertEqual(status.platformAPIHTTP, "204")
        XCTAssertEqual(status.platformAPIStartedAt, "2026-05-30T00:02:00Z")
    }

    func testLocalAPIStatusReadFactoriesPreserveReachableAndFailedState() {
        let reachable = RuntimeControlLocalAPIStatusRead.reachable(startedAt: "2026-05-30T00:02:00Z")
        XCTAssertEqual(reachable.http, "200")
        XCTAssertEqual(reachable.startedAt, "2026-05-30T00:02:00Z")

        let failed = RuntimeControlLocalAPIStatusRead.failed()
        XCTAssertEqual(failed.http, RuntimeHTTPStatusText.failed)
        XCTAssertNil(failed.startedAt)
    }

    func testDataDirectoryMetricsAssemblerAppliesLoadedMetricsAndClearsPreviousErrors() {
        let status = RuntimeDataDirectoryMetricsAssembler.applyingMetricReads(
            to: PlatformState(
                runtimeInstallationState: .missing,
                dataStorage: nil,
                dataStorageError: "previous storage failure",
                dataDirectoryStats: nil,
                dataDirectoryStatsError: "previous stats failure"
            ),
            reads: RuntimeDataDirectoryMetricReads(
                storageUsage: .loaded(ResourceUsage(usedBytes: 4, totalBytes: 10)),
                directoryStats: .loaded(RuntimeDataDirectoryStats(fileCount: 2, sizeBytes: 8))
            )
        )

        XCTAssertEqual(status.dataStorage, ResourceUsage(usedBytes: 4, totalBytes: 10))
        XCTAssertNil(status.dataStorageError)
        XCTAssertEqual(status.dataDirectoryStats, RuntimeDataDirectoryStats(fileCount: 2, sizeBytes: 8))
        XCTAssertNil(status.dataDirectoryStatsError)
    }

    func testDataDirectoryMetricsAssemblerPreservesUnavailableAndFailedMeanings() {
        let unavailable = RuntimeDataDirectoryMetricsAssembler.applyingMetricReads(
            to: PlatformState(
                runtimeInstallationState: .missing,
                dataStorage: ResourceUsage(usedBytes: 1, totalBytes: 2),
                dataStorageError: "previous storage failure"
            ),
            reads: RuntimeDataDirectoryMetricReads(
                storageUsage: .unavailable,
                directoryStats: .unavailable
            )
        )
        XCTAssertEqual(unavailable.dataStorage, ResourceUsage(usedBytes: 1, totalBytes: 2))
        XCTAssertNil(unavailable.dataStorageError)
        XCTAssertNil(unavailable.dataDirectoryStats)
        XCTAssertNil(unavailable.dataDirectoryStatsError)

        let missing = RuntimeDataDirectoryMetricsAssembler.applyingMetricReads(
            to: PlatformState(runtimeInstallationState: .missing, dataDirectoryStats: RuntimeDataDirectoryStats(fileCount: 1, sizeBytes: 2)),
            reads: RuntimeDataDirectoryMetricReads(
                storageUsage: .unavailable,
                directoryStats: .missing(path: "/data")
            )
        )
        XCTAssertNil(missing.dataDirectoryStats)
        XCTAssertEqual(missing.dataDirectoryStatsError, "data directory missing path=/data")

        let failed = RuntimeDataDirectoryMetricsAssembler.applyingMetricReads(
            to: PlatformState(runtimeInstallationState: .missing, dataStorage: ResourceUsage(usedBytes: 1, totalBytes: 2)),
            reads: RuntimeDataDirectoryMetricReads(
                storageUsage: .failed("volume read failed"),
                directoryStats: .failed("permission denied")
            )
        )
        XCTAssertNil(failed.dataStorage)
        XCTAssertEqual(failed.dataStorageError, "volume read failed")
        XCTAssertNil(failed.dataDirectoryStats)
        XCTAssertEqual(failed.dataDirectoryStatsError, "permission denied")
    }

    private func liveDiagnostics(
        vm: RuntimeServiceState = .loaded,
        proxy: RuntimeServiceState = .loaded,
        watchdog: RuntimeServiceState = .loaded
    ) -> RuntimeLiveDiagnostics {
        RuntimeLiveDiagnostics(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            runtimeInstallationIssue: nil,
            vmService: RuntimeServiceStateRead(state: vm),
            proxyService: RuntimeServiceStateRead(state: proxy),
            guestLogSyncService: RuntimeServiceStateRead(state: .loaded),
            sleepPreventionService: RuntimeServiceStateRead(state: .loaded),
            watchdogService: RuntimeServiceStateRead(state: watchdog),
            readIssues: []
        )
    }
}
