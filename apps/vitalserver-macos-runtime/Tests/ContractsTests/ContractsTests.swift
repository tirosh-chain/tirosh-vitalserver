import Foundation
import Contracts
import XCTest
import Errors

final class ContractsTests: XCTestCase {
    func testRuntimeFileModifiedAtReadResultPreservesExplicitReadState() {
        XCTAssertEqual(
            RuntimeFileModifiedAtReadResult.notRead().readState,
            .notRead
        )
        XCTAssertEqual(
            RuntimeFileModifiedAtReadResult(updatedAt: "2026-06-08T00:00:00Z", readError: nil).readState,
            .loaded
        )
        XCTAssertEqual(
            RuntimeFileModifiedAtReadResult(updatedAt: nil, readError: "mtime-read-failed").readState,
            .readFailed
        )
    }

    func testRuntimeContainerObservationPreservesRuntimeStateFileMetadataReadState() throws {
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: nil,
            runtimeStateFileMetadataReadState: .notRead,
            containerLogsPresent: false,
            containerLogsBytes: nil
        )

        let data = try JSONEncoder().encode(observation)
        let decoded = try JSONDecoder().decode(RuntimeContainerObservation.self, from: data)

        XCTAssertEqual(decoded.runtimeStateFileMetadataReadState, .notRead)
        XCTAssertNil(decoded.runtimeStateFileUpdatedAt)
        XCTAssertNil(decoded.runtimeStateFileMetadataError)
    }

    func testAuditProxyStatusReadResultPreservesExplicitReadState() {
        XCTAssertEqual(
            RuntimeAuditProxyStatusReadResult(
                httpStatus: "200",
                document: RuntimeAuditProxyStatusDocument(activeRecorderConnections: 1),
                readError: nil
            ).readState,
            .loaded
        )
        XCTAssertEqual(
            RuntimeAuditProxyStatusReadResult(
                httpStatus: RuntimeHTTPStatusText.failed,
                document: nil,
                readError: "command-failed-7"
            ).readState,
            .commandFailed
        )
        XCTAssertEqual(
            RuntimeAuditProxyStatusReadResult(
                httpStatus: RuntimeHTTPStatusText.missingProxyPort,
                document: nil,
                readError: RuntimeHTTPStatusText.missingProxyPort
            ).readState,
            .skippedMissingProxyPort
        )
    }

    func testRuntimeContainerObservationPreservesAuditProxyStatusReadState() throws {
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: RuntimeHTTPStatusText.failed,
            auditProxyStatus: nil,
            auditProxyStatusReadState: .commandFailed,
            auditProxyStatusReadError: "command-failed-7",
            containerLogsPresent: false,
            containerLogsBytes: nil
        )

        let data = try JSONEncoder().encode(observation)
        let decoded = try JSONDecoder().decode(RuntimeContainerObservation.self, from: data)

        XCTAssertEqual(decoded.auditProxyStatusReadState, .commandFailed)
        XCTAssertEqual(decoded.auditProxyStatusReadError, "command-failed-7")
    }

    func testDecodesRuntimeStatusV1() throws {
        let document = try decodeFixture(RuntimeStatusDocument.self, named: "runtime-status-v1-healthy")

        XCTAssertNil(document.schemaVersion)
        XCTAssertEqual(document.status, .healthy)
        XCTAssertEqual(document.operation, .health)
        XCTAssertEqual(document.proxyPort, 80)
        XCTAssertNil(document.vmState)
        XCTAssertNil(document.vmErrors)
        XCTAssertEqual(document.failureReasons, [])
        XCTAssertNil(document.progress)
    }

    func testDecodesRuntimeStatusV2Progress() throws {
        let document = try decodeFixture(RuntimeStatusDocument.self, named: "runtime-status-v2-updating")

        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.status, .updating)
        XCTAssertEqual(document.progress?.operation, .applyBundle)
        XCTAssertEqual(document.progress?.step, .activateGuestUpdate)
        XCTAssertEqual(document.progress?.stepStatus, .started)
        XCTAssertEqual(document.progress?.reasonCodes, ["guest-activation-pending"])
    }

    func testRuntimeServiceOperationsRoundTrip() throws {
        XCTAssertEqual(RuntimeOperation(rawValue: "start-services"), .startServices)
        XCTAssertEqual(RuntimeOperation.startServices.rawValue, "start-services")
        XCTAssertEqual(RuntimeOperation(rawValue: "stop-services"), .stopServices)
        XCTAssertEqual(RuntimeOperation.stopServices.rawValue, "stop-services")
        XCTAssertEqual(RuntimeOperation(rawValue: "repair-services"), .repairServices)
        XCTAssertEqual(RuntimeOperation.repairServices.rawValue, "repair-services")
        XCTAssertEqual(RuntimeOperation(rawValue: "prepare-update-shutdown"), .prepareUpdateShutdown)
        XCTAssertEqual(RuntimeOperation.prepareUpdateShutdown.rawValue, "prepare-update-shutdown")
    }

    func testManagedRuntimeBackupManifestFactoryPreservesRootfsBackupMeaning() {
        let withRootfs = BackupManifest.managedRuntimeBackup(
            product: "ai.tirosh.vitalserver.helper",
            createdAt: "2026-06-08T00:00:00Z",
            reason: "before-0.1.4",
            rootfsBaseName: "rootfs-base.raw.gz",
            backsUpRootfsBase: true,
            vmDiskName: "vm-disk.img"
        )
        let withoutRootfs = BackupManifest.managedRuntimeBackup(
            product: "ai.tirosh.vitalserver.helper",
            createdAt: "2026-06-08T00:00:00Z",
            reason: "before-0.1.4",
            rootfsBaseName: "rootfs-base.raw.gz",
            backsUpRootfsBase: false,
            vmDiskName: "vm-disk.img"
        )

        XCTAssertEqual(withRootfs.rootfsBase, "rootfs-base.raw.gz")
        XCTAssertNil(withoutRootfs.rootfsBase)
        XCTAssertEqual(withRootfs.vmDisk, "vm-disk.img")
        XCTAssertTrue(withRootfs.vmDiskPreserved)
        XCTAssertTrue(withoutRootfs.vmDiskPreserved)
    }

    func testManagedBackupArtifactContractMapsUpdateArtifactTypesAndBackupDirectoryNames() {
        XCTAssertEqual(
            RuntimeManagedBackupArtifact.allCases.map(\.updateArtifactType),
            [.appBundle, .nginxBundle, .guestDeploy, .runtimeTools]
        )
        XCTAssertEqual(
            RuntimeManagedBackupArtifact.directoryArtifacts.map(\.updateArtifactType),
            [.appBundle, .nginxBundle, .guestDeploy]
        )
        XCTAssertEqual(RuntimeManagedBackupArtifact.appBundle.backupDirectoryName, "app-bundle")
        XCTAssertEqual(RuntimeManagedBackupArtifact.nginxBundle.backupDirectoryName, "nginx-bundle")
        XCTAssertEqual(RuntimeManagedBackupArtifact.guestDeploy.backupDirectoryName, "guest-deploy")
        XCTAssertEqual(RuntimeManagedBackupArtifact.runtimeTools.backupDirectoryName, "runtime-tools")
    }

    func testVMLifecycleDocumentDecodesExplicitStateAndTerminalReason() throws {
        let json = """
        {
          "schemaVersion": 1,
          "state": "failed",
          "operation": "install",
          "startedAt": "2026-05-31T00:00:00Z",
          "updatedAt": "2026-05-31T00:00:05Z",
          "terminalReason": "disk-attachment-invalid",
          "message": "storage attachment failed"
        }
        """

        let document = try JSONDecoder().decode(RuntimeVMLifecycleDocument.self, from: Data(json.utf8))

        XCTAssertEqual(document.state, .failed)
        XCTAssertEqual(document.operation, .install)
        XCTAssertEqual(document.terminalReason, .diskAttachmentInvalid)
        XCTAssertEqual(document.reportedVMErrors, [.diskAttachmentInvalid])
    }

    func testDecodesGuestRuntimeState() throws {
        let document = try decodeFixture(GuestRuntimeStateDocument.self, named: "runtime-state-ready")

        XCTAssertEqual(document.vmIP, "192.168.64.2")
        XCTAssertEqual(document.bootID, "7b6a6afd-64f8-4dd5-91f1-6dcbf58f8f7d")
        XCTAssertEqual(document.memory?.percent, 25.0)
        XCTAssertEqual(document.systemDisk?.percent, 31.25)
        XCTAssertEqual(document.vitalFilesDisk?.percent, 25.0)
        XCTAssertEqual(
            document.capabilities,
            GuestRuntimeCapabilities(
                prepareUpdateShutdown: true,
                activateUpdate: true,
                redisBackup: true,
                repairDatastore: true
            )
        )
    }

    func testDecodesGuestRuntimeStateContainerServices() throws {
        let json = """
        {
          "schemaVersion": 1,
          "vmIP": "192.168.64.2",
          "guestHTTP": "200",
          "redisUIHTTP": "200",
          "swaggerUIHTTP": "200",
          "updatedAt": "2026-05-24T00:00:00Z",
          "containerServices": [
            {
              "service": "audit-proxy",
              "name": "vitalserver-audit-proxy-1",
              "state": "running",
              "health": "healthy",
              "exitCode": 0
            }
          ]
        }
        """
        let document = try JSONDecoder().decode(GuestRuntimeStateDocument.self, from: Data(json.utf8))

        XCTAssertEqual(document.containerServices, [
            RuntimeContainerServiceObservation(
                service: "audit-proxy",
                name: "vitalserver-audit-proxy-1",
                state: "running",
                health: "healthy",
                exitCode: 0
            ),
        ])
    }

    func testDecodesGuestRuntimeStateProbeErrors() throws {
        let json = """
        {
          "schemaVersion": 1,
          "vmIP": null,
          "guestHTTP": "failed",
          "redisUIHTTP": null,
          "swaggerUIHTTP": null,
          "updatedAt": "2026-05-24T00:00:00Z",
          "probeErrors": [
            {
              "source": "vmIP",
              "message": "no non-loopback IP address found"
            }
          ]
        }
        """
        let document = try JSONDecoder().decode(GuestRuntimeStateDocument.self, from: Data(json.utf8))

        XCTAssertNil(document.vmIP)
        XCTAssertEqual(document.probeErrors, [
            GuestRuntimeProbeError(
                source: "vmIP",
                message: "no non-loopback IP address found"
            ),
        ])
    }

    func testDecodesGuestRuntimeStateDiskHealth() throws {
        let json = """
        {
          "schemaVersion": 1,
          "vmIP": "192.168.64.2",
          "guestHTTP": "200",
          "redisUIHTTP": "200",
          "swaggerUIHTTP": "200",
          "updatedAt": "2026-05-24T00:00:00Z",
          "diskHealth": {
            "rootFilesystemReadOnly": true,
            "kernelErrors": [
              "EXT4-fs error (device vda1): checksum invalid"
            ]
          }
        }
        """
        let document = try JSONDecoder().decode(GuestRuntimeStateDocument.self, from: Data(json.utf8))

        XCTAssertEqual(document.diskHealth, GuestDiskHealthDocument(
            rootFilesystemReadOnly: true,
            kernelErrors: ["EXT4-fs error (device vda1): checksum invalid"]
        ))
    }

    func testRuntimeContainerObservationPreservesReadErrors() throws {
        let json = """
        {
          "auditProxyHTTP": "invalid-response",
          "auditProxyStatus": null,
          "auditProxyStatusReadError": "decode-failed",
          "runtimeStateFileUpdatedAt": null,
          "runtimeStateFileMetadataError": "mtime-read-failed",
          "containerLogsPresent": true,
          "containerLogsBytes": null,
          "containerLogsMetadataError": "size-read-failed",
          "composeServices": [],
          "composeServicesReadError": "guest-runtime-state-invalid"
        }
        """

        let observation = try JSONDecoder().decode(RuntimeContainerObservation.self, from: Data(json.utf8))

        XCTAssertEqual(observation.auditProxyStatusReadError, "decode-failed")
        XCTAssertEqual(observation.auditProxyStatusReadState, .invalidResponse)
        XCTAssertEqual(observation.runtimeStateFileMetadataError, "mtime-read-failed")
        XCTAssertEqual(observation.containerLogsMetadataError, "size-read-failed")
        XCTAssertEqual(observation.composeServicesReadState, .invalid)
        XCTAssertEqual(observation.composeServices, [])
        XCTAssertEqual(observation.composeServicesReadError, "guest-runtime-state-invalid")

        let encoded = try JSONDecoder().decode(
            RuntimeContainerObservation.self,
            from: JSONEncoder().encode(observation)
        )
        XCTAssertEqual(encoded, observation)
    }

    func testRuntimeContainerObservationDistinguishesLoadedEmptyComposeServicesFromMissingState() throws {
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: nil,
            containerLogsPresent: false,
            containerLogsBytes: nil,
            composeServicesReadState: .loaded,
            composeServices: []
        )

        XCTAssertEqual(observation.composeServicesReadState, .loaded)
        XCTAssertEqual(observation.composeServices, [])
        XCTAssertNil(observation.composeServicesReadError)

        let encoded = try JSONDecoder().decode(
            RuntimeContainerObservation.self,
            from: JSONEncoder().encode(observation)
        )
        XCTAssertEqual(encoded.composeServicesReadState, .loaded)
        XCTAssertEqual(encoded.composeServices, [])
        XCTAssertNil(encoded.composeServicesReadError)
    }

    func testDecodesActivationResultV1() throws {
        let document = try decodeFixture(
            GuestUpdateActivationResultDocument.self,
            named: "activate-update-result-v1-completed"
        )

        XCTAssertNil(document.schemaVersion)
        XCTAssertTrue(document.completed)
        XCTAssertFalse(document.failed)
        XCTAssertEqual(document.status, .completed)
    }

    func testDecodesActivationResultV2() throws {
        let document = try decodeFixture(
            GuestUpdateActivationResultDocument.self,
            named: "activate-update-result-v2-running"
        )

        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.requestId, "4A3D7063-5E81-4BA1-9E74-74E44347F6E5")
        XCTAssertEqual(document.operation, .activateGuestUpdate)
        XCTAssertEqual(document.step, "load-docker-images")
        XCTAssertFalse(document.completed)
        XCTAssertFalse(document.failed)
    }

    func testDecodesDatastoreRepairResultV2() throws {
        let json = """
        {
          "schemaVersion": 2,
          "requestId": "repair-1",
          "operation": "repair-datastore",
          "status": "running",
          "message": "Datastore repair is running.",
          "updatedAt": "2026-05-21T12:33:57Z"
        }
        """
        let document = try JSONDecoder().decode(DatastoreRepairResultDocument.self, from: Data(json.utf8))

        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.requestId, "repair-1")
        XCTAssertEqual(document.operation, .repairDatastore)
        XCTAssertEqual(document.status, .running)
        XCTAssertFalse(document.completed)
        XCTAssertFalse(document.failed)
    }

    func testUnknownEnumValuesRoundTrip() throws {
        let json = """
        {
          "schemaVersion": 2,
          "product": "VitalServerHelper",
          "status": "paused",
          "operation": "future-operation",
          "message": "future state",
          "updatedAt": "2026-05-21T12:33:57Z",
          "productRoot": "/Library/Application Support/VitalServerHelper",
          "runtimeHome": "/Library/Application Support/VitalServerHelper/vm",
          "runtimeVersion": "0.1.4",
          "vmService": "loaded",
          "proxyService": "loaded",
          "watchdogService": "loaded",
          "vmState": "hibernating",
          "vmErrors": ["vm-runtime-state-stale", "vm-service-state-paused"],
          "vmIP": null,
          "proxyPort": 80,
          "hostProxyHTTP": "failed",
          "guestHTTP": "failed",
          "redisUIHTTP": null,
          "swaggerUIHTTP": null,
          "rootfsBase": "present",
          "vmDisk": "present",
          "failureReasons": [],
          "latestBackup": null,
          "progress": {
            "operation": "future-operation",
            "phase": "future-phase",
            "step": "future-step",
            "stepStatus": "future-step-status",
            "message": "future progress",
            "reasonCodes": [],
            "startedAt": null,
            "updatedAt": "2026-05-21T12:33:57Z"
          }
        }
        """
        let document = try JSONDecoder().decode(RuntimeStatusDocument.self, from: Data(json.utf8))

        XCTAssertEqual(document.status.rawValue, "paused")
        XCTAssertEqual(document.operation.rawValue, "future-operation")
        XCTAssertEqual(document.vmService, .loaded)
        XCTAssertEqual(document.vmState?.rawValue, "hibernating")
        XCTAssertEqual(document.vmErrors ?? [], [.runtimeStateStale, .serviceNotLoaded("paused")])
        XCTAssertEqual(document.rootfsBase, .present)
        XCTAssertEqual(document.progress?.phase.rawValue, "future-phase")
        XCTAssertEqual(document.progress?.stepStatus?.rawValue, "future-step-status")

        let encoded = try JSONEncoder().encode(document)
        let roundTripped = try JSONDecoder().decode(RuntimeStatusDocument.self, from: encoded)
        XCTAssertEqual(roundTripped.status.rawValue, "paused")
        XCTAssertEqual(roundTripped.vmService.rawValue, "loaded")
        XCTAssertEqual(roundTripped.vmState?.rawValue, "hibernating")
        XCTAssertEqual(roundTripped.vmErrors ?? [], [.runtimeStateStale, .serviceNotLoaded("paused")])
        XCTAssertEqual(roundTripped.rootfsBase.rawValue, "present")
        XCTAssertEqual(roundTripped.progress?.phase.rawValue, "future-phase")
    }

    func testRuntimeVMStateDefinesObservedStatesAndPreservesUnknownValues() throws {
        let states: [RuntimeVMState] = [
            .notInstalled,
            .stopped,
            .starting,
            .running,
            .stale,
            .unreachable,
            .failed,
        ]

        XCTAssertEqual(states.map(\.rawValue), [
            "not-installed",
            "stopped",
            "starting",
            "running",
            "stale",
            "unreachable",
            "failed",
        ])

        let encoded = try JSONEncoder().encode(RuntimeVMState.unknown("hibernating"))
        let decoded = try JSONDecoder().decode(RuntimeVMState.self, from: encoded)

        XCTAssertEqual(decoded, .unknown("hibernating"))
    }

    func testRuntimeVMErrorDefinesObservedErrorsAndPreservesUnknownValues() throws {
        let errors: [RuntimeVMError] = [
            .missingExecutable,
            .missingRootfsBase,
            .missingDisk,
            .serviceNotLoaded("not loaded"),
            .missingIPAddress,
            .runtimeStateMissing,
            .runtimeStateInvalid,
            .runtimeStateStale,
            .launchFailed("virtualization"),
            .invalidConfiguration("network"),
            .hostResourceUnavailable("memory"),
            .diskAttachmentInvalid,
            .guestFilesystemError,
            .guestFilesystemReadOnly,
            .guestDiskIO,
            .guestHTTP("failed"),
            .guestHTTPProbeFailed("failed"),
            .guestBootstrapResultMissing,
            .guestBootstrapResultUnavailable,
            .guestBootstrapMissingRuntimePackages,
            .guestBootstrapFailed,
        ]

        XCTAssertEqual(errors.map(\.rawValue), [
            "vm-missing-executable",
            "vm-missing-rootfs-base",
            "vm-missing-disk",
            "vm-service-state-not loaded",
            "vm-missing-ip-address",
            "vm-runtime-state-missing",
            "vm-runtime-state-invalid",
            "vm-runtime-state-stale",
            "vm-launch-failed-virtualization",
            "vm-invalid-configuration-network",
            "vm-host-resource-unavailable-memory",
            "vm-disk-attachment-invalid",
            "vm-guest-filesystem-error",
            "vm-guest-filesystem-read-only",
            "vm-guest-disk-io-error",
            "vm-guest-http-failed",
            "vm-guest-http-probe-failed-failed",
            "vm-guest-bootstrap-result-missing",
            "vm-guest-bootstrap-result-unavailable",
            "vm-guest-bootstrap-missing-runtime-packages",
            "vm-guest-bootstrap-failed",
        ])

        let encoded = try JSONEncoder().encode(RuntimeVMError.unknown("vm-future-error"))
        let decoded = try JSONDecoder().decode(RuntimeVMError.self, from: encoded)

        XCTAssertEqual(decoded, .unknown("vm-future-error"))
    }

    func testRuntimeVMErrorDefinesCategoryAndRecoveryAction() {
        XCTAssertEqual(RuntimeVMError.diskAttachmentInvalid.category, .guestStorage)
        XCTAssertEqual(RuntimeVMError.diskAttachmentInvalid.recoveryAction, .backupAndRecreateVM)
        XCTAssertTrue(RuntimeVMError.diskAttachmentInvalid.requiresDataPreservationBeforeRecovery)

        XCTAssertEqual(RuntimeVMError.runtimeStateMissing.category, .guestAgent)
        XCTAssertEqual(RuntimeVMError.runtimeStateMissing.recoveryAction, .restartGuestAgent)
        XCTAssertFalse(RuntimeVMError.runtimeStateMissing.requiresDataPreservationBeforeRecovery)
        XCTAssertEqual(RuntimeVMError.runtimeStateInvalid.category, .guestAgent)
        XCTAssertEqual(RuntimeVMError.runtimeStateInvalid.recoveryAction, .restartGuestAgent)
        XCTAssertEqual(RuntimeVMError.guestHTTPProbeFailed("failed").category, .networking)
        XCTAssertEqual(RuntimeVMError.guestHTTPProbeFailed("failed").recoveryAction, .waitForGuest)

        XCTAssertEqual(RuntimeVMError.guestBootstrapResultMissing.category, .guestBootstrap)
        XCTAssertEqual(RuntimeVMError.guestBootstrapResultMissing.recoveryAction, .waitForGuest)
        XCTAssertEqual(RuntimeVMError.guestBootstrapResultUnavailable.category, .guestBootstrap)
        XCTAssertEqual(RuntimeVMError.guestBootstrapResultUnavailable.recoveryAction, .inspectLogs)
    }

    func testRuntimeFailureReasonsDecodeAsTypedCodes() throws {
        let json = """
        [
          "missing-vm-bin",
          "vm-service-not loaded",
          "guest-log-sync-service-not-loaded",
          "host-proxy-http-502",
          "guest-http-probe-failed-failed",
          "audit-proxy-http-failed",
          "container-service-app-state-unhealthy",
          "container-observation-missing",
          "container-observation-read-failed-permission_denied",
          "vitaldb-anomaly-duplicate-ip-subject-10.0.0.10",
          "vitaldb-observation-missing",
          "vitaldb-observation-read-failed-decode_failed",
          "proxy-port-80-in-use-by-nginx-1234",
          "host-proxy-listener-scan-unavailable",
          "host-proxy-listener-scan-inspection-failed-path=/usr/sbin/lsof reason=permission denied",
          "host-proxy-listener-scan-failed-port-80-exit-1",
          "guest-bootstrap-result-missing",
          "guest-bootstrap-result-unavailable",
          "guest-bootstrap-missing-runtime-packages",
          "future-reason"
        ]
        """
        let reasons = try JSONDecoder().decode([RuntimeFailureReason].self, from: Data(json.utf8))

        XCTAssertEqual(reasons[0], .missingVMBin)
        XCTAssertEqual(reasons[1], .vmService("not loaded"))
        XCTAssertEqual(reasons[2], .guestLogSyncService("not-loaded"))
        XCTAssertEqual(reasons[3], .hostProxyHTTP("502"))
        XCTAssertEqual(reasons[4], .guestHTTPProbeFailed("failed"))
        XCTAssertEqual(reasons[5], .auditProxyHTTP("failed"))
        XCTAssertEqual(reasons[6], .containerService(service: "app", state: "unhealthy"))
        XCTAssertEqual(reasons[7], .containerObservationMissing)
        XCTAssertEqual(reasons[8], .containerObservationReadFailed("permission_denied"))
        XCTAssertEqual(reasons[9], .vitalDBAnomaly(kind: "duplicate-ip", subject: "10.0.0.10"))
        XCTAssertEqual(reasons[10], .vitalDBObservationMissing)
        XCTAssertEqual(reasons[11], .vitalDBObservationReadFailed("decode_failed"))
        XCTAssertEqual(reasons[12], .proxyPortInUse(port: 80, listeners: "nginx-1234"))
        XCTAssertEqual(reasons[13], .hostProxyListenerScanUnavailable)
        XCTAssertEqual(
            reasons[14],
            .hostProxyListenerScanInspectionFailed("path=/usr/sbin/lsof reason=permission denied")
        )
        XCTAssertEqual(reasons[15], .hostProxyListenerScanFailed(port: 80, exitCode: 1))
        XCTAssertEqual(reasons[16], .guestBootstrapResultMissing)
        XCTAssertEqual(reasons[17], .guestBootstrapResultUnavailable)
        XCTAssertEqual(reasons[18], .guestBootstrapMissingRuntimePackages)
        XCTAssertEqual(reasons[19], .unknown("future-reason"))

        let encoded = try JSONEncoder().encode(reasons)
        let roundTripped = try JSONDecoder().decode([RuntimeFailureReason].self, from: encoded)
        XCTAssertEqual(roundTripped.map(\.rawValue), [
            "missing-vm-bin",
            "vm-service-not loaded",
            "guest-log-sync-service-not-loaded",
            "host-proxy-http-502",
            "guest-http-probe-failed-failed",
            "audit-proxy-http-failed",
            "container-service-app-state-unhealthy",
            "container-observation-missing",
            "container-observation-read-failed-permission_denied",
            "vitaldb-anomaly-duplicate-ip-subject-10.0.0.10",
            "vitaldb-observation-missing",
            "vitaldb-observation-read-failed-decode_failed",
            "proxy-port-80-in-use-by-nginx-1234",
            "host-proxy-listener-scan-unavailable",
            "host-proxy-listener-scan-inspection-failed-path=/usr/sbin/lsof reason=permission denied",
            "host-proxy-listener-scan-failed-port-80-exit-1",
            "guest-bootstrap-result-missing",
            "guest-bootstrap-result-unavailable",
            "guest-bootstrap-missing-runtime-packages",
            "future-reason",
        ])
    }

    func testRuntimeFailureReasonsDefineDomainClassificationAndRecovery() {
        XCTAssertEqual(RuntimeFailureReason.proxyPortInUse(port: 80, listeners: "nginx-1234").domainCategory, .hostProxy)
        XCTAssertEqual(RuntimeFailureReason.proxyPortInUse(port: 80, listeners: "nginx-1234").recoveryAction, .freeProxyPort)
        XCTAssertEqual(RuntimeFailureReason.proxyPortInUse(port: 80, listeners: "nginx-1234").domainSeverity, .critical)

        XCTAssertEqual(RuntimeFailureReason.auditProxyHTTP("failed").domainCategory, .container)
        XCTAssertEqual(RuntimeFailureReason.auditProxyHTTP("failed").recoveryAction, .restartContainerServices)

        XCTAssertEqual(RuntimeFailureReason.vitalDBAnomaly(kind: "duplicate-ip", subject: "10.0.0.10").domainCategory, .vitalDB)
        XCTAssertEqual(RuntimeFailureReason.vitalDBAnomaly(kind: "duplicate-ip", subject: "10.0.0.10").domainSeverity, .warning)
        XCTAssertEqual(
            RuntimeFailureReason.vitalDBAnomaly(kind: "duplicate-ip", subject: "10.0.0.10").recoveryAction,
            .inspectVitalDBObservation
        )

        XCTAssertEqual(RuntimeFailureReason.vitalDBAnomaly(kind: "observer-unhealthy", subject: "vitaldb").domainCategory, .vitalDB)
        XCTAssertEqual(
            RuntimeFailureReason.vitalDBAnomaly(kind: "observer-unhealthy", subject: "vitaldb").recoveryAction,
            .inspectVitalDBObservation
        )

        XCTAssertEqual(RuntimeFailureReason.unknown("vm-disk-attachment-invalid").domainCategory, .guestStorage)
        XCTAssertEqual(RuntimeFailureReason.unknown("vm-disk-attachment-invalid").recoveryAction, .backupAndRecreateVM)
        XCTAssertTrue(RuntimeFailureReason.unknown("vm-disk-attachment-invalid").requiresDataPreservationBeforeRecovery)

        XCTAssertEqual(RuntimeFailureReason.redisUIHTTP("failed").domainSeverity, .warning)
        XCTAssertEqual(RuntimeFailureReason.redisUIHTTP("failed").recoveryAction, .inspectLogs)

        XCTAssertEqual(RuntimeFailureReason.guestHTTPProbeFailed("failed").domainCategory, .guestNetworking)
        XCTAssertEqual(RuntimeFailureReason.guestHTTPProbeFailed("failed").domainSeverity, .warning)
        XCTAssertEqual(RuntimeFailureReason.guestHTTPProbeFailed("failed").recoveryAction, .waitForGuest)

        XCTAssertEqual(RuntimeFailureReason.runtimeStatusDocumentInvalid.domainCategory, .observability)
        XCTAssertEqual(RuntimeFailureReason.runtimeStatusDocumentInvalid.domainSeverity, .critical)
        XCTAssertEqual(RuntimeFailureReason.runtimeStatusDocumentInvalid.recoveryAction, .inspectLogs)

        XCTAssertEqual(RuntimeFailureReason.launchdServiceCrashed(service: "vm", exitCode: 78).domainCategory, .vmLifecycle)
        XCTAssertEqual(RuntimeFailureReason.launchdServiceCrashed(service: "vm", exitCode: 78).recoveryAction, .restartVMService)

        XCTAssertEqual(RuntimeFailureReason.hostProxyConfigInvalid.domainCategory, .hostProxy)
        XCTAssertEqual(RuntimeFailureReason.hostProxyConfigInvalid.recoveryAction, .repairProxyConfiguration)

        XCTAssertEqual(RuntimeFailureReason.hostProxyListenerScanUnavailable.domainCategory, .hostProxy)
        XCTAssertEqual(RuntimeFailureReason.hostProxyListenerScanUnavailable.domainSeverity, .warning)
        XCTAssertEqual(RuntimeFailureReason.hostProxyListenerScanUnavailable.recoveryAction, .inspectLogs)

        XCTAssertEqual(RuntimeFailureReason.hostProxyListenerScanInspectionFailed("permission denied").domainCategory, .hostProxy)
        XCTAssertEqual(RuntimeFailureReason.hostProxyListenerScanInspectionFailed("permission denied").domainSeverity, .warning)
        XCTAssertEqual(RuntimeFailureReason.hostProxyListenerScanInspectionFailed("permission denied").recoveryAction, .inspectLogs)

        XCTAssertEqual(RuntimeFailureReason.hostProxyListenerScanFailed(port: 80, exitCode: 1).domainCategory, .hostProxy)
        XCTAssertEqual(RuntimeFailureReason.hostProxyListenerScanFailed(port: 80, exitCode: 1).domainSeverity, .warning)
        XCTAssertEqual(RuntimeFailureReason.hostProxyListenerScanFailed(port: 80, exitCode: 1).recoveryAction, .inspectLogs)

        XCTAssertEqual(RuntimeFailureReason.containerRestartLoop(service: "redis").domainCategory, .container)
        XCTAssertEqual(RuntimeFailureReason.containerRestartLoop(service: "redis").recoveryAction, .restartContainerServices)

        XCTAssertEqual(RuntimeFailureReason.containerObservationMissing.domainCategory, .observability)
        XCTAssertEqual(RuntimeFailureReason.containerObservationMissing.domainSeverity, .warning)
        XCTAssertEqual(RuntimeFailureReason.containerObservationMissing.recoveryAction, .inspectLogs)

        XCTAssertEqual(RuntimeFailureReason.vitalDBObservationReadFailed("decode_failed").domainCategory, .vitalDB)
        XCTAssertEqual(RuntimeFailureReason.vitalDBObservationReadFailed("decode_failed").domainSeverity, .warning)
        XCTAssertEqual(
            RuntimeFailureReason.vitalDBObservationReadFailed("decode_failed").recoveryAction,
            .inspectVitalDBObservation
        )

        XCTAssertEqual(RuntimeFailureReason.vitalDBObservationStale.domainSeverity, .warning)

        XCTAssertEqual(RuntimeFailureReason.guestBootstrapResultMissing.domainCategory, .guestBootstrap)
        XCTAssertEqual(RuntimeFailureReason.guestBootstrapResultMissing.recoveryAction, .waitForGuest)
        XCTAssertEqual(RuntimeFailureReason.guestBootstrapResultUnavailable.domainCategory, .guestBootstrap)
        XCTAssertEqual(RuntimeFailureReason.guestBootstrapResultUnavailable.recoveryAction, .inspectLogs)
    }

    func testRuntimeDomainErrorDocumentOwnsCodeCategorySeverityAndRecoveryAction() throws {
        let error = RuntimeDomainError(.guestBootstrapFailed)

        XCTAssertEqual(error.code, .guestBootstrapFailed)
        XCTAssertEqual(error.category, .guestBootstrap)
        XCTAssertEqual(error.severity, .critical)
        XCTAssertEqual(error.recoveryAction, .repairGuestBootstrap)

        let encoded = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(RuntimeDomainError.self, from: encoded)
        XCTAssertEqual(decoded, error)
    }

    func testRuntimeEventTypeDefinesOperationalTaxonomyAndPreservesUnknownValues() throws {
        let knownTypes: [RuntimeEventType] = [
            .statusChanged,
            .progressUpdated,
            .healthObserved,
            .recoveryTriggered,
            .recoveryCompleted,
            .recoverySuppressed,
            .recoveryDeferred,
            .domainErrorObserved,
            .vmErrorObserved,
            .containerObserved,
            .auditProxyObserved,
            .vitalDBObserved,
            .vitalDBObserverUnhealthy,
            .vitalDBAnomalyDetected,
            .watchdogSkipped,
            .recoveryPlanned,
            .serviceRestartDispatched,
            .observabilityStoreFailed,
            .runtimeStatusObserved,
            .guestStateObserved,
            .runtimeCommandStarted,
            .runtimeCommandCompleted,
            .runtimeCommandFailed,
        ]

        XCTAssertEqual(knownTypes.map(\.rawValue), [
            "status-changed",
            "progress-updated",
            "health-observed",
            "recovery-triggered",
            "recovery-completed",
            "recovery-suppressed",
            "recovery-deferred",
            "domain-error-observed",
            "vm-error-observed",
            "container-observed",
            "audit-proxy-observed",
            "vitaldb-observed",
            "vitaldb-observer-unhealthy",
            "vitaldb-anomaly-detected",
            "watchdog-skipped",
            "recovery-planned",
            "service-restart-dispatched",
            "observability-store-failed",
            "runtime-status-observed",
            "guest-state-observed",
            "runtime-command-started",
            "runtime-command-completed",
            "runtime-command-failed",
        ])

        let encoded = try JSONEncoder().encode(RuntimeEventType.unknown("vendor-event"))
        let decoded = try JSONDecoder().decode(RuntimeEventType.self, from: encoded)

        XCTAssertEqual(decoded, .unknown("vendor-event"))
    }

    func testRuntimeEventQueryClampsLimitAndPreservesCursor() {
        let cursor = RuntimeEventCursor(timestamp: "2026-05-24T00:01:00Z", id: "event-2")

        XCTAssertEqual(RuntimeEventQuery(limit: 0).limit, 1)
        XCTAssertEqual(RuntimeEventQuery(limit: 1_000).limit, RuntimeEventQuery.maximumLimit)

        let query = RuntimeEventQuery(
            limit: 25,
            eventType: .auditProxyObserved,
            since: "2026-05-24T00:00:00Z",
            before: cursor
        )

        XCTAssertEqual(query.limit, 25)
        XCTAssertEqual(query.eventType, .auditProxyObserved)
        XCTAssertEqual(query.since, "2026-05-24T00:00:00Z")
        XCTAssertEqual(query.before, cursor)
    }

    func testRuntimeEventDocumentAllowsEventsWithoutRuntimeStatusContext() throws {
        let json = """
        {
          "schemaVersion": 1,
          "id": "event-1",
          "source": "host-command",
          "eventType": "runtime-command-started",
          "timestamp": "2026-05-30T01:00:00Z",
          "product": "ai.tirosh.vitalserver.helper",
          "message": "command started",
          "runtimeVersion": "0.1.9",
          "failureReasons": []
        }
        """

        let event = try JSONDecoder().decode(RuntimeEventDocument.self, from: Data(json.utf8))

        XCTAssertNil(event.status)
        XCTAssertNil(event.operation)
        XCTAssertEqual(event.source, "host-command")
        XCTAssertEqual(event.eventType, .runtimeCommandStarted)

        let roundTripped = try JSONDecoder().decode(RuntimeEventDocument.self, from: try JSONEncoder().encode(event))
        XCTAssertNil(roundTripped.status)
        XCTAssertNil(roundTripped.operation)
    }

    private func decodeFixture<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
