import Contracts
import RuntimeControl
import XCTest
import Errors

final class RuntimeControlStatusAssemblerTests: XCTestCase {
    func testMakeStatusBuildsRuntimeControlReadModelFromExplicitReads() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            statusRead: RuntimeStatusDocumentRead(
                document: statusDocument(proxyPort: 19090),
                error: nil,
                issue: nil
            ),
            guestStateRead: GuestRuntimeStateRead(
                document: GuestRuntimeStateDocument(
                    vmIP: "192.168.64.2",
                    updatedAt: "2026-06-01T00:00:01Z",
                    guestHTTP: "200",
                    redisUIHTTP: "200",
                    swaggerUIHTTP: "200",
                    cpuUsagePercent: 12.5,
                    containerServices: [
                        RuntimeContainerServiceObservation(
                            service: "app",
                            memoryUsedBytes: 1_073_741_824,
                            memoryLimitBytes: 4_294_967_296
                        ),
                        RuntimeContainerServiceObservation(
                            service: "recorder-ingress",
                            memoryUsedBytes: 134_217_728
                        ),
                        RuntimeContainerServiceObservation(
                            service: "redis",
                            memoryUsedBytes: 67_108_864,
                            memoryLimitBytes: 536_870_912
                        ),
                    ]
                ),
                error: nil,
                issue: nil
            ),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.runtimeInstalled, true)
        XCTAssertEqual(status.runtimeInstallationState, RuntimeFileState.executable)
        XCTAssertEqual(status.vmServiceStateSource, RuntimeServiceStateSource.statusDocument)
        XCTAssertEqual(status.proxyServiceStateSource, RuntimeServiceStateSource.liveLaunchd)
        XCTAssertEqual(status.runtimeState, RuntimeState.healthy)
        XCTAssertEqual(status.operation, RuntimeOperation.health)
        XCTAssertEqual(status.startedAt, "2026-06-01T00:00:00Z")
        XCTAssertEqual(status.cpuUsagePercent, 12.5)
        XCTAssertEqual(status.vitalServerMemory, RuntimeContainerMemoryUsage(usedBytes: 1_073_741_824, limitBytes: 4_294_967_296))
        XCTAssertEqual(status.vitalServerMemory?.percent, 25)
        XCTAssertEqual(status.recorderIngressMemory, RuntimeContainerMemoryUsage(usedBytes: 134_217_728))
        XCTAssertNil(status.recorderIngressMemory?.percent)
        XCTAssertEqual(status.redisMemory?.percent, 12.5)
        XCTAssertEqual(status.proxyPort, 19090)
        XCTAssertEqual(status.readIssues, [RuntimeStatusReadIssue]())
    }

    func testMakeStatusPreservesMissingProxyPortAsExplicitReadIssue() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            statusRead: RuntimeStatusDocumentRead(
                document: statusDocument(proxyPort: nil),
                error: nil,
                issue: nil
            ),
            guestStateRead: GuestRuntimeStateRead(document: nil, error: nil, issue: nil),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertNil(status.proxyPort)
        XCTAssertTrue(status.readIssues.contains(RuntimeStatusReadIssue(
            source: "proxyPort",
            message: "proxy port is missing from runtime status document"
        )))
    }

    func testLiveDiagnosticsAssemblerPrefersStatusDocumentManagedServicesAndReadsMissingServicesLive() {
        let diagnostics = RuntimeLiveDiagnosticsAssembler.makeDiagnostics(
            runtimeLauncherPath: "/product/launcher",
            runtimeExecutableState: .executable,
            statusDocument: statusDocument(proxyPort: 19090),
            liveServiceStates: RuntimeLiveServiceStateReads(
                vm: .notLoaded,
                proxy: .readFailed("launchctl proxy failed"),
                guestLogSync: .loaded,
                sleepPrevention: .notLoaded,
                watchdog: .unknown("weird")
            )
        )

        XCTAssertEqual(diagnostics.runtimeInstalled, true)
        XCTAssertEqual(diagnostics.vmService, RuntimeServiceStateRead(state: .loaded, source: .statusDocument))
        XCTAssertEqual(diagnostics.proxyService, RuntimeServiceStateRead(state: .loaded, source: .statusDocument))
        XCTAssertEqual(diagnostics.watchdogService, RuntimeServiceStateRead(state: .loaded, source: .statusDocument))
        XCTAssertEqual(diagnostics.guestLogSyncService, RuntimeServiceStateRead(state: .loaded, source: .liveLaunchd))
        XCTAssertEqual(diagnostics.sleepPreventionService, RuntimeServiceStateRead(state: .notLoaded, source: .liveLaunchd))
        XCTAssertTrue(diagnostics.readIssues.isEmpty)
    }

    func testLiveDiagnosticsAssemblerReportsLiveServiceReadIssuesAndRuntimeInstallationIssue() {
        let diagnostics = RuntimeLiveDiagnosticsAssembler.makeDiagnostics(
            runtimeLauncherPath: "/product/launcher",
            runtimeExecutableState: .present,
            statusDocument: nil,
            liveServiceStates: RuntimeLiveServiceStateReads(
                vm: .readFailed("launchctl vm failed"),
                proxy: .permissionDenied("launchctl proxy denied"),
                guestLogSync: .unknown("strange"),
                sleepPrevention: .loaded,
                watchdog: .notLoaded
            )
        )

        XCTAssertEqual(diagnostics.runtimeInstalled, false)
        XCTAssertEqual(diagnostics.runtimeInstallationIssue, RuntimeStatusReadIssue(
            source: "runtimeInstallation",
            message: "runtime launcher is present but not executable path=/product/launcher"
        ))
        XCTAssertTrue(diagnostics.readIssues.contains(RuntimeStatusReadIssue(
            source: "vmService",
            message: "launchctl vm failed"
        )))
        XCTAssertTrue(diagnostics.readIssues.contains(RuntimeStatusReadIssue(
            source: "proxyService",
            message: "launchctl proxy denied"
        )))
        XCTAssertTrue(diagnostics.readIssues.contains(RuntimeStatusReadIssue(
            source: "guestLogSyncService",
            message: "unknown service state: strange"
        )))
    }

    func testHealthStatusAssemblerAppliesExplicitProbeReads() {
        let status = RuntimeHealthStatusAssembler.applyingHealthProbeReads(
            to: RuntimeStatus(vmIP: "192.168.64.8", proxyPort: 19090),
            reads: RuntimeHealthProbeReads(
                guestHTTP: RuntimeHTTPStatusRead(
                    status: "200",
                    issue: nil
                ),
                hostProxyHTTP: RuntimeHTTPStatusRead(
                    status: nil,
                    issue: RuntimeStatusReadIssue(source: "hostProxyHTTP", message: "exitCode=28 stderr=timeout")
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

        XCTAssertEqual(status.guestHTTP, "200")
        XCTAssertNil(status.hostProxyHTTP)
        XCTAssertEqual(status.redisUIHTTP, "200")
        XCTAssertEqual(status.swaggerUIHTTP, "503")
        XCTAssertEqual(status.readIssues, [
            RuntimeStatusReadIssue(source: "hostProxyHTTP", message: "exitCode=28 stderr=timeout"),
        ])
    }

    func testHealthStatusAssemblerPreservesMissingProxyPortAsExplicitHTTPStatusWithoutProbeReads() {
        let existingIssue = RuntimeStatusReadIssue(
            source: "proxyPort",
            message: "proxy port is missing from runtime status document"
        )
        let status = RuntimeHealthStatusAssembler.applyingHealthProbeReads(
            to: RuntimeStatus(readIssues: [existingIssue], vmIP: "192.168.64.8", proxyPort: nil),
            reads: RuntimeHealthProbeReads(
                guestHTTP: nil,
                hostProxyHTTP: nil,
                redisUIHTTP: nil,
                swaggerUIHTTP: nil
            )
        )

        XCTAssertEqual(status.hostProxyHTTP, RuntimeHTTPStatusText.missingProxyPort)
        XCTAssertEqual(status.redisUIHTTP, RuntimeHTTPStatusText.missingProxyPort)
        XCTAssertEqual(status.swaggerUIHTTP, RuntimeHTTPStatusText.missingProxyPort)
        XCTAssertEqual(status.readIssues, [existingIssue])
    }

    func testHealthStatusAssemblerPreservesMissingVMIPAsExplicitGuestHTTPStatusWithoutProbeRead() {
        let existingIssue = RuntimeStatusReadIssue(
            source: "vmIP",
            message: "vm ip is missing from runtime status document"
        )
        let status = RuntimeHealthStatusAssembler.applyingHealthProbeReads(
            to: RuntimeStatus(readIssues: [existingIssue], proxyPort: 19090),
            reads: RuntimeHealthProbeReads(
                guestHTTP: nil,
                hostProxyHTTP: RuntimeHTTPStatusRead(status: "200", issue: nil),
                redisUIHTTP: RuntimeHTTPStatusRead(status: "200", issue: nil),
                swaggerUIHTTP: RuntimeHTTPStatusRead(status: "200", issue: nil)
            )
        )

        XCTAssertEqual(status.guestHTTP, RuntimeHTTPStatusText.missingVMIP)
        XCTAssertEqual(status.hostProxyHTTP, "200")
        XCTAssertEqual(status.redisUIHTTP, "200")
        XCTAssertEqual(status.swaggerUIHTTP, "200")
        XCTAssertEqual(status.readIssues, [existingIssue])
    }

    func testLocalAPIStatusAssemblerAppliesExplicitHostReadWithoutChangingOtherStatusFields() {
        let status = RuntimeControlLocalAPIStatusAssembler.applyingLocalAPIStatus(
            to: RuntimeStatus(
                runtimeInstalled: true,
                runtimeState: .degraded,
                statusMessage: "ready",
                runtimeControlHTTP: "500",
                runtimeControlStartedAt: "stale"
            ),
            read: RuntimeControlLocalAPIStatusRead(
                http: "204",
                startedAt: "2026-05-30T00:02:00Z"
            )
        )

        XCTAssertEqual(status.runtimeInstalled, true)
        XCTAssertEqual(status.runtimeState, .degraded)
        XCTAssertEqual(status.statusMessage, "ready")
        XCTAssertEqual(status.runtimeControlHTTP, "204")
        XCTAssertEqual(status.runtimeControlStartedAt, "2026-05-30T00:02:00Z")
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
            to: RuntimeStatus(
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
            to: RuntimeStatus(
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
            to: RuntimeStatus(dataDirectoryStats: RuntimeDataDirectoryStats(fileCount: 1, sizeBytes: 2)),
            reads: RuntimeDataDirectoryMetricReads(
                storageUsage: .unavailable,
                directoryStats: .missing(path: "/data")
            )
        )
        XCTAssertNil(missing.dataDirectoryStats)
        XCTAssertEqual(missing.dataDirectoryStatsError, "data directory missing path=/data")

        let failed = RuntimeDataDirectoryMetricsAssembler.applyingMetricReads(
            to: RuntimeStatus(dataStorage: ResourceUsage(usedBytes: 1, totalBytes: 2)),
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

    func testMakeStatusIncludesRedisRelayStatusRead() {
        let redisRelayStatus = RuntimeRedisRelayStatus(
            observedAt: "2026-06-18T05:00:00Z",
            enabled: true,
            state: "running",
            scope: "vital_reconstruction",
            targetUrl: "redis://127.0.0.1:16381/0",
            batches: 3,
            totals: RuntimeRedisRelayBatch(scanned: 30, copied: 4, unchanged: 20),
            lastBatch: RuntimeRedisRelayBatch(scanned: 10, copied: 0, unchanged: 10)
        )

        let status = RuntimeControlStatusAssembler.makeStatus(
            statusRead: RuntimeStatusDocumentRead(
                document: statusDocument(proxyPort: 80),
                error: nil,
                issue: nil
            ),
            guestStateRead: GuestRuntimeStateRead(document: nil, error: nil, issue: nil),
            redisRelayStatusRead: RuntimeRedisRelayStatusRead(
                document: redisRelayStatus,
                error: nil,
                issue: nil
            ),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.redisRelayStatus, redisRelayStatus)
    }

    private func statusDocument(proxyPort: Int?) -> RuntimeStatusDocument {
        RuntimeStatusDocument(
            product: "VitalServerHelper",
            status: .healthy,
            operation: .health,
            message: "ready",
            updatedAt: "2026-06-01T00:00:02Z",
            productRoot: "/product",
            runtimeHome: "/product/vm",
            runtimeVersion: "0.1.0",
            vmService: .loaded,
            proxyService: .loaded,
            watchdogService: .loaded,
            vmState: .running,
            vmErrors: [],
            vmIP: "192.168.64.2",
            proxyPort: proxyPort,
            proxyPortReadState: proxyPort.map(RuntimeProxyPortReadState.loaded),
            hostProxyHTTP: "200",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            rootfsBase: .present,
            vmDisk: .present,
            failureReasons: [],
            latestBackup: nil,
            containerObservation: RuntimeContainerObservation(
                recorderIngressHTTP: "200",
                recorderIngressStatus: nil,
                recorderIngressStatusReadError: nil,
                runtimeStateUpdatedAt: nil,
                runtimeStateFileUpdatedAt: nil,
                runtimeStateFileMetadataError: nil,
                containerLogsPresent: false,
                containerLogsBytes: nil,
                containerLogsUpdatedAt: nil,
                containerLogsMetadataError: nil,
                composeServicesReadState: .loaded,
                composeServices: [
                    RuntimeContainerServiceObservation(service: "app", startedAt: "2026-06-01T00:00:00Z"),
                ],
                composeServicesReadError: nil
            )
        )
    }

    private func liveDiagnostics() -> RuntimeLiveDiagnostics {
        RuntimeLiveDiagnostics(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            runtimeInstallationIssue: nil,
            vmService: RuntimeServiceStateRead(state: .loaded, source: .statusDocument),
            proxyService: RuntimeServiceStateRead(state: .loaded, source: .liveLaunchd),
            guestLogSyncService: RuntimeServiceStateRead(state: .loaded, source: .liveLaunchd),
            sleepPreventionService: RuntimeServiceStateRead(state: .loaded, source: .liveLaunchd),
            watchdogService: RuntimeServiceStateRead(state: .loaded, source: .statusDocument),
            readIssues: []
        )
    }
}
