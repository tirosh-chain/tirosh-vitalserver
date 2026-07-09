import Contracts
import RuntimeControl
import XCTest
import Errors

final class RuntimeControlStatusAssemblerTests: XCTestCase {
    func testMakeStatusDoesNotPublishResourceFieldsWithoutGuestStackResourceRead() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            proxyPortReadState: .loaded(19090),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.runtimeInstalled, true)
        XCTAssertEqual(status.runtimeInstallationState, RuntimeFileState.executable)
        XCTAssertEqual(status.vmServiceStateSource, RuntimeServiceStateSource.liveLaunchd)
        XCTAssertEqual(status.proxyServiceStateSource, RuntimeServiceStateSource.liveLaunchd)
        XCTAssertEqual(status.runtimeState, RuntimeState.healthy)
        XCTAssertNil(status.vmIP)
        XCTAssertNil(status.vmState)
        XCTAssertNil(status.vmErrors)
        XCTAssertNil(status.guestHTTP)
        XCTAssertNil(status.hostProxyHTTP)
        XCTAssertNil(status.redisUIHTTP)
        XCTAssertNil(status.swaggerUIHTTP)
        XCTAssertNil(status.cpuUsagePercent)
        XCTAssertNil(status.memory)
        XCTAssertNil(status.systemDisk)
        XCTAssertNil(status.dataStorage)
        XCTAssertNil(status.vitalServerMemory)
        XCTAssertNil(status.recorderIngressMemory)
        XCTAssertNil(status.redisMemory)
        XCTAssertEqual(status.proxyPort, 19090)
        XCTAssertEqual(status.readIssues, [RuntimeStatusReadIssue]())
    }

    func testMakeStatusDoesNotExposeActiveOperationFields() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.runtimeState, .healthy)
        XCTAssertEqual(status.readIssues, [])
    }

    func testMakeStatusDoesNotPromoteStatusDocumentOperationFields() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.runtimeState, .healthy)
        XCTAssertFalse(status.readIssues.contains { $0.source == "activeOperation" })
    }

    func testMakeStatusDoesNotExposeStatusDocumentReadIssueAsStatusField() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.readIssues, [])
        XCTAssertEqual(status.runtimeState, .healthy)
    }

    func testMakeStatusBuildsCurrentHealthFromExplicitOwnerReads() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            proxyPortReadState: .missing("proxy launch daemon missing"),
            guestServicesRead: .loaded(
                services: ["app"],
                statuses: [RuntimeGuestControlServiceStatus(
                    service: "app",
                    state: "exited",
                    health: "unhealthy",
                    observedAt: "2026-07-08T00:00:00Z"
                )],
                resources: [],
                resourceReadIssues: [],
                probeErrors: [],
                cpuUsagePercent: nil,
                memory: nil,
                systemDisk: nil
            ),
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

        XCTAssertEqual(status.runtimeState, .critical)
        XCTAssertTrue(status.failureReasons.contains(.vmService("not loaded")))
        XCTAssertFalse(status.failureReasons.contains(.hostProxyConfigInvalid))
        XCTAssertTrue(status.failureReasons.contains(.guestService(service: "app", state: "exited")))
        XCTAssertTrue(status.failureReasons.contains(.vmLaunchFailed("launch-failed")))
    }

    func testMakeStatusDoesNotExposeProgressFields() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.readIssues, [])
    }

    func testMakeStatusDoesNotPromoteProgressReadFailureToCurrentStatusIssue() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertFalse(status.readIssues.contains(RuntimeStatusReadIssue(
            source: "runtimeProgress",
            message: "decode failed"
        )))
        XCTAssertEqual(status.runtimeState, .healthy)
    }

    func testMakeStatusUsesExplicitGuestAddressReadForCurrentVMIP() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            guestAddressRead: .loaded(address: "192.168.64.44", source: .runtimeControlAPI),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.vmIP, "192.168.64.44")
        XCTAssertEqual(status.readIssues, [])
    }

    func testMakeStatusUsesExplicitVersionAndLatestBackupReads() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            runtimeVersionRead: RuntimeVersionRead(version: "2.0.0", issue: nil),
            latestBackupRead: RuntimeLatestBackupRead(path: "/backups/20260708T010000Z-before-2.0.0", issue: nil),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.runtimeVersion, "2.0.0")
        XCTAssertEqual(status.latestBackup, "/backups/20260708T010000Z-before-2.0.0")
        XCTAssertEqual(status.readIssues, [])
    }

    func testMakeStatusDoesNotPromoteVersionOrLatestBackupReadIssuesIntoCurrentHealth() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            runtimeVersionRead: RuntimeVersionRead(
                version: nil,
                issue: RuntimeStatusReadIssue(
                    source: "runtimeVersion",
                    message: "runtime version document missing path=/runtime/runtime-version.json"
                )
            ),
            latestBackupRead: RuntimeLatestBackupRead(
                path: nil,
                issue: RuntimeStatusReadIssue(
                    source: "latestBackup",
                    message: "backup directory inspection failed path=/runtime/backups reason=permission denied"
                )
            ),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertNil(status.runtimeVersion)
        XCTAssertNil(status.latestBackup)
        XCTAssertTrue(status.readIssues.contains(RuntimeStatusReadIssue(
            source: "runtimeVersion",
            message: "runtime version document missing path=/runtime/runtime-version.json"
        )))
        XCTAssertTrue(status.readIssues.contains(RuntimeStatusReadIssue(
            source: "latestBackup",
            message: "backup directory inspection failed path=/runtime/backups reason=permission denied"
        )))
        XCTAssertEqual(status.runtimeState, .healthy)
        XCTAssertEqual(status.failureReasons, [])
    }

    func testMakeStatusDoesNotPromoteGuestAddressReadFailureAsCurrentIssue() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            guestAddressRead: .readFailed("permission denied"),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertNil(status.vmIP)
        XCTAssertFalse(status.readIssues.contains(RuntimeStatusReadIssue(
            source: "guestAddress",
            message: "guest-address-read-failed:permission denied"
        )))
        XCTAssertFalse(status.failureReasons.contains(.guestHTTP("guest-address-read-failed:permission denied")))
        XCTAssertEqual(status.runtimeState, .healthy)
    }

    func testMakeStatusUsesExplicitVMLifecycleReadForCurrentVMState() {
        let status = RuntimeControlStatusAssembler.makeStatus(
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

        XCTAssertEqual(status.vmState, .failed)
        XCTAssertEqual(status.vmErrors, [.guestDiskIO])
        XCTAssertEqual(status.readIssues, [])
    }

    func testMakeStatusPreservesVMLifecycleReadFailureAsIssue() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            vmLifecycleRead: RuntimeVMLifecycleRead(
                document: nil,
                issue: RuntimeStatusReadIssue(
                    source: "vmLifecycle",
                    message: "permission denied"
                )
            ),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertNil(status.vmState)
        XCTAssertNil(status.vmErrors)
        XCTAssertTrue(status.readIssues.contains(RuntimeStatusReadIssue(
            source: "vmLifecycle",
            message: "permission denied"
        )))
    }

    func testMakeStatusPreservesGuestServicesReadWithoutMixingItWithFileReadIssues() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            guestServicesRead: .loaded(
                services: ["app", "postgres"],
                statuses: [
                    RuntimeGuestControlServiceStatus(
                        service: "app",
                        state: "running",
                        health: "healthy",
                        observedAt: "2026-07-01T00:00:00+00:00",
                        container: "vitalserver-app-1"
                    ),
                    RuntimeGuestControlServiceStatus(
                        service: "postgres",
                        state: "running",
                        health: "healthy",
                        observedAt: "2026-07-01T00:00:00+00:00"
                    ),
                ],
                resources: [
                    RuntimeGuestServiceResource(
                        service: "app",
                        spec: RuntimeGuestServiceSpec(
                            state: "configured",
                            desiredState: "running",
                            updatedAt: "2026-07-01T00:00:00+00:00"
                        ),
                        status: RuntimeGuestServiceStatusRead(
                            state: "loaded",
                            observedState: "running",
                            observedAt: "2026-07-01T00:00:00+00:00",
                            serviceStatus: RuntimeGuestControlServiceStatus(
                                service: "app",
                                state: "running",
                                health: "healthy",
                                observedAt: "2026-07-01T00:00:00+00:00"
                            )
                        ),
                        conditions: [
                            RuntimeGuestServiceCondition(
                                type: "Reconciled",
                                status: "true",
                                reason: "DesiredStateObserved",
                                message: "Guest service already matches desired running state.",
                                observedAt: "2026-07-01T00:00:01+00:00"
                            )
                        ],
                        lastOperationId: "op_app_reconcile_1"
                    )
                ],
                resourceReadIssues: [
                    RuntimeGuestServiceResourceReadIssue(
                        service: "postgres",
                        message: "resource read failed"
                    )
                ],
                probeErrors: [
                    GuestRuntimeProbeError(
                        source: "docker stats",
                        message: "timed out after 1 seconds"
                    )
                ],
                cpuUsagePercent: nil,
                memory: nil,
                systemDisk: nil
            ),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.guestServicesReadState, .loaded)
        XCTAssertEqual(status.guestServices, ["app", "postgres"])
        XCTAssertEqual(status.guestServiceStatuses.map(\.service), ["app", "postgres"])
        XCTAssertEqual(status.guestServiceResources.map(\.service), ["app"])
        XCTAssertEqual(status.guestServiceResources.first?.spec.desiredState, "running")
        XCTAssertEqual(status.guestServiceResources.first?.conditions.first?.reason, "DesiredStateObserved")
        XCTAssertEqual(status.guestServiceResourceReadIssues, [
            RuntimeGuestServiceResourceReadIssue(
                service: "postgres",
                message: "resource read failed"
            )
        ])
        XCTAssertEqual(status.guestStackProbeErrors, [
            GuestRuntimeProbeError(
                source: "docker stats",
                message: "timed out after 1 seconds"
            )
        ])
        XCTAssertNil(status.guestServicesReadError)
        XCTAssertEqual(status.readIssues, [])
    }

    func testMakeStatusPublishesGuestStackResourceRead() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            guestServicesRead: .loaded(
                services: ["app", "recorder-ingress", "redis"],
                statuses: [
                    RuntimeGuestControlServiceStatus(
                        service: "app",
                        state: "running",
                        health: "healthy",
                        observedAt: "2026-07-01T00:00:00+00:00",
                        memory: ResourceUsage(usedBytes: 1, totalBytes: 10)
                    ),
                    RuntimeGuestControlServiceStatus(
                        service: "recorder-ingress",
                        state: "running",
                        health: "healthy",
                        observedAt: "2026-07-01T00:00:00+00:00",
                        memory: ResourceUsage(usedBytes: 2, totalBytes: 10)
                    ),
                    RuntimeGuestControlServiceStatus(
                        service: "redis",
                        state: "running",
                        health: "healthy",
                        observedAt: "2026-07-01T00:00:00+00:00",
                        memory: ResourceUsage(usedBytes: 3, totalBytes: 10)
                    ),
                ],
                cpuUsagePercent: 12.5,
                memory: ResourceUsage(usedBytes: 4, totalBytes: 10),
                systemDisk: ResourceUsage(usedBytes: 5, totalBytes: 10)
            ),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.cpuUsagePercent, 12.5)
        XCTAssertEqual(status.memory, ResourceUsage(usedBytes: 4, totalBytes: 10))
        XCTAssertEqual(status.systemDisk, ResourceUsage(usedBytes: 5, totalBytes: 10))
        XCTAssertEqual(status.vitalServerMemory, RuntimeContainerMemoryUsage(usedBytes: 1, limitBytes: 10))
        XCTAssertEqual(status.recorderIngressMemory, RuntimeContainerMemoryUsage(usedBytes: 2, limitBytes: 10))
        XCTAssertEqual(status.redisMemory, RuntimeContainerMemoryUsage(usedBytes: 3, limitBytes: 10))
    }

    func testMakeStatusUsesGuestServiceDesiredStateBeforeAddingFailureReason() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            guestServicesRead: .loaded(
                services: ["app", "worker"],
                statuses: [
                    RuntimeGuestControlServiceStatus(
                        service: "app",
                        state: "stopped",
                        health: "unknown",
                        observedAt: "2026-07-01T00:00:00+00:00"
                    ),
                    RuntimeGuestControlServiceStatus(
                        service: "worker",
                        state: "stopped",
                        health: "unknown",
                        observedAt: "2026-07-01T00:00:00+00:00"
                    ),
                ],
                resources: [
                    RuntimeGuestServiceResource(
                        service: "app",
                        spec: RuntimeGuestServiceSpec(
                            state: "configured",
                            desiredState: "stopped"
                        ),
                        status: RuntimeGuestServiceStatusRead(
                            state: "loaded",
                            observedState: "stopped",
                            observedAt: "2026-07-01T00:00:00+00:00"
                        ),
                        conditions: [],
                        lastOperationId: "op-app-stop"
                    ),
                    RuntimeGuestServiceResource(
                        service: "worker",
                        spec: RuntimeGuestServiceSpec(
                            state: "configured",
                            desiredState: "running"
                        ),
                        status: RuntimeGuestServiceStatusRead(
                            state: "loaded",
                            observedState: "stopped",
                            observedAt: "2026-07-01T00:00:00+00:00"
                        ),
                        conditions: [],
                        lastOperationId: "op-worker-start"
                    ),
                ],
                cpuUsagePercent: nil,
                memory: nil,
                systemDisk: nil
            ),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertFalse(status.failureReasons.contains(.guestService(service: "app", state: "stopped")))
        XCTAssertTrue(status.failureReasons.contains(.guestService(service: "worker", state: "stopped")))
    }

    func testMakeStatusPreservesGuestServicesReadFailureSeparately() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            guestServicesRead: .failed("guest control API timed out"),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.guestServicesReadState, .failed)
        XCTAssertNil(status.guestServices)
        XCTAssertEqual(status.guestServiceStatuses, [])
        XCTAssertEqual(status.guestServicesReadError, "guest control API timed out")
        XCTAssertEqual(status.readIssues, [])
    }

    func testMakeStatusDoesNotPublishContainerObservationAsProductStatus() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            guestServicesRead: .unavailable,
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.guestServicesReadState, .unavailable)
        XCTAssertNil(status.guestServices)
        XCTAssertEqual(status.guestServiceStatuses, [])
        XCTAssertNil(status.guestServicesReadError)
    }

    func testMakeStatusUsesExplicitProxyPortReadForCurrentProxyPort() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            proxyPortReadState: .loaded(19090),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.proxyPort, 19090)
        XCTAssertEqual(status.proxyPortReadState, .loaded(19090))
        XCTAssertEqual(status.readIssues, [])
    }

    func testMakeStatusDoesNotPromoteStatusDocumentOrProxyPortReadFailure() {
        let status = RuntimeControlStatusAssembler.makeStatus(
            proxyPortReadState: .missing("proxy launch daemon plist missing path=/runtime/proxy.plist"),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertNil(status.proxyPort)
        XCTAssertEqual(
            status.proxyPortReadState,
            .missing("proxy launch daemon plist missing path=/runtime/proxy.plist")
        )
        XCTAssertFalse(status.readIssues.contains(RuntimeStatusReadIssue(
            source: "proxyPort",
            message: "proxy launch daemon plist missing path=/runtime/proxy.plist"
        )))
        XCTAssertFalse(status.failureReasons.contains(.hostProxyConfigInvalid))
        XCTAssertEqual(status.runtimeState, .healthy)
    }

    func testLiveDiagnosticsAssemblerUsesLiveLaunchdForManagedServices() {
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

        XCTAssertEqual(diagnostics.runtimeInstalled, true)
        XCTAssertEqual(diagnostics.vmService, RuntimeServiceStateRead(state: .notLoaded, source: .liveLaunchd))
        XCTAssertEqual(
            diagnostics.proxyService,
            RuntimeServiceStateRead(state: .readFailed("launchctl proxy failed"), source: .liveLaunchd)
        )
        XCTAssertEqual(diagnostics.watchdogService, RuntimeServiceStateRead(state: .unknown("weird"), source: .liveLaunchd))
        XCTAssertEqual(diagnostics.guestLogSyncService, RuntimeServiceStateRead(state: .loaded, source: .liveLaunchd))
        XCTAssertEqual(diagnostics.sleepPreventionService, RuntimeServiceStateRead(state: .notLoaded, source: .liveLaunchd))
        XCTAssertTrue(diagnostics.readIssues.contains(RuntimeStatusReadIssue(
            source: "proxyService",
            message: "launchctl proxy failed"
        )))
        XCTAssertTrue(diagnostics.readIssues.contains(RuntimeStatusReadIssue(
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

    func testHealthStatusAssemblerMarksMissingProxyPortAsDisplayStatusWithoutReadIssue() {
        let status = RuntimeHealthStatusAssembler.applyingHealthProbeReads(
            to: RuntimeStatus(vmIP: "192.168.64.8", proxyPort: nil),
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
        XCTAssertEqual(status.readIssues, [])
    }

    func testHealthStatusAssemblerMarksMissingVMIPAsDisplayStatusWithoutReadIssue() {
        let status = RuntimeHealthStatusAssembler.applyingHealthProbeReads(
            to: RuntimeStatus(proxyPort: 19090),
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
        XCTAssertEqual(status.readIssues, [])
    }

    func testLocalAPIStatusAssemblerAppliesExplicitHostReadWithoutChangingOtherStatusFields() {
        let status = RuntimeControlLocalAPIStatusAssembler.applyingLocalAPIStatus(
            to: RuntimeStatus(
                runtimeInstalled: true,
                runtimeInstallationState: .executable,
                runtimeState: .degraded,
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
            redisRelayStatusRead: RuntimeRedisRelayStatusRead(
                document: redisRelayStatus,
                error: nil,
                issue: nil
            ),
            liveDiagnostics: liveDiagnostics()
        )

        XCTAssertEqual(status.redisRelayStatus, redisRelayStatus)
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
            vmService: RuntimeServiceStateRead(state: vm, source: .liveLaunchd),
            proxyService: RuntimeServiceStateRead(state: proxy, source: .liveLaunchd),
            guestLogSyncService: RuntimeServiceStateRead(state: .loaded, source: .liveLaunchd),
            sleepPreventionService: RuntimeServiceStateRead(state: .loaded, source: .liveLaunchd),
            watchdogService: RuntimeServiceStateRead(state: watchdog, source: .liveLaunchd),
            readIssues: []
        )
    }
}
