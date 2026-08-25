import Foundation
import Contracts
import XCTest
import Errors

final class ContractsTests: XCTestCase {
    func testRecorderObservabilityDetailPreservesRequiredNullableFields() throws {
        let detail = RuntimeRecorderObservabilityDetail.unavailable(
            vrcode: "06311eba",
            readError: "Guest Control unavailable"
        )
        let data = try JSONEncoder().encode(detail)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var support = try XCTUnwrap(object["support"] as? [String: Any])
        let report = try XCTUnwrap(object["report"] as? [String: Any])
        let profile = try XCTUnwrap(object["profile"] as? [String: Any])
        let reading = try XCTUnwrap(
            (object["readings"] as? [String: Any])?["temperatureCelsius"]
                as? [String: Any]
        )

        XCTAssertTrue(support["source"] is NSNull)
        XCTAssertTrue(support["expectedSince"] is NSNull)
        XCTAssertTrue(report["receivedAt"] is NSNull)
        XCTAssertTrue(profile["collection"] is NSNull)
        XCTAssertTrue(reading["value"] is NSNull)
        XCTAssertTrue(reading["observedAt"] is NSNull)
        XCTAssertEqual(
            try JSONDecoder().decode(RuntimeRecorderObservabilityDetail.self, from: data),
            detail
        )

        support.removeValue(forKey: "source")
        object["support"] = support
        let missingSource = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RuntimeRecorderObservabilityDetail.self,
                from: missingSource
            )
        )
    }

    func testRecorderObservabilityHistoryPreservesRequiredNullableFields() throws {
        let timeline = RuntimeRecorderObservabilityTimeline.unavailable(
            vrcode: "06311eba",
            readError: "timeline unavailable"
        )
        let timelineData = try JSONEncoder().encode(timeline)
        var timelineObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: timelineData) as? [String: Any]
        )

        XCTAssertTrue(timelineObject["supportState"] is NSNull)
        XCTAssertTrue(timelineObject["query"] is NSNull)
        XCTAssertEqual(timelineObject["readError"] as? String, "timeline unavailable")
        XCTAssertEqual(
            try JSONDecoder().decode(RuntimeRecorderObservabilityTimeline.self, from: timelineData),
            timeline
        )

        timelineObject.removeValue(forKey: "readError")
        let missingTimelineReadError = try JSONSerialization.data(withJSONObject: timelineObject)
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RuntimeRecorderObservabilityTimeline.self,
                from: missingTimelineReadError
            )
        )

        let incidents = try JSONDecoder().decode(
            RuntimeRecorderObservabilityIncidents.self,
            from: Data(
                #"{"state":"loaded","vrcode":"06311eba","timeBasis":"receivedAt","incidents":[],"nextCursor":null,"readError":null}"#.utf8
            )
        )
        let incidentsData = try JSONEncoder().encode(incidents)
        var incidentsObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: incidentsData) as? [String: Any]
        )

        XCTAssertTrue(incidentsObject["nextCursor"] is NSNull)
        XCTAssertTrue(incidentsObject["readError"] is NSNull)
        XCTAssertEqual(
            try JSONDecoder().decode(RuntimeRecorderObservabilityIncidents.self, from: incidentsData),
            incidents
        )

        incidentsObject.removeValue(forKey: "nextCursor")
        let missingNextCursor = try JSONSerialization.data(withJSONObject: incidentsObject)
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RuntimeRecorderObservabilityIncidents.self,
                from: missingNextCursor
            )
        )
    }

    func testLabArchiveFinalizationPreservesRequiredNullableFields() throws {
        let finalization = RuntimeLabArchiveFinalization(
            state: .exported,
            updatedAt: nil,
            readError: nil
        )

        let data = try JSONEncoder().encode(finalization)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["state"] as? String, "exported")
        XCTAssertTrue(object["updatedAt"] is NSNull)
        XCTAssertTrue(object["readError"] is NSNull)
        XCTAssertEqual(
            try JSONDecoder().decode(RuntimeLabArchiveFinalization.self, from: data),
            finalization
        )
    }

    func testLabArchiveFinalizationRejectsMissingRequiredNullableFields() throws {
        let missingUpdatedAt = Data(
            #"{"state":"exported","readError":null}"#.utf8
        )
        let missingReadError = Data(
            #"{"state":"published","updatedAt":null}"#.utf8
        )

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RuntimeLabArchiveFinalization.self,
                from: missingUpdatedAt
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RuntimeLabArchiveFinalization.self,
                from: missingReadError
            )
        )
    }

    func testRecorderIngressStatusReadResultPreservesExplicitReadState() {
        XCTAssertEqual(
            RuntimeRecorderIngressStatusReadResult(
                httpStatus: "200",
                document: RuntimeRecorderIngressStatusDocument(activeRecorderConnections: 1),
                readError: nil
            ).readState,
            .loaded
        )
        XCTAssertEqual(
            RuntimeRecorderIngressStatusReadResult(
                httpStatus: RuntimeHTTPStatusText.failed,
                document: nil,
                readError: "command-failed-7"
            ).readState,
            .commandFailed
        )
        XCTAssertEqual(
            RuntimeRecorderIngressStatusReadResult(
                httpStatus: RuntimeHTTPStatusText.missingProxyPort,
                document: nil,
                readError: nil
            ).readState,
            .notRead
        )
    }

    func testRecorderIngressStatusDecodesSpoolAndReplayStateWithoutDefaultingMissingQueueState() throws {
        let json = """
        {
          "activeWebSockets": 1,
          "activeRecorderConnections": 1,
          "recorders": [
            {
              "vrcode": "VR001",
              "activeConnections": 1,
              "spool": {
                "pendingItems": 3
              },
              "replay": {
                "retryableFailures": 1
              }
            }
          ],
          "httpRequests": 0,
          "socketIoEventsSeen": 0,
          "socketIoParseFailures": 0,
          "auditWriteFailures": 0,
          "auditFileWriteFailures": 0,
          "auditStdoutWriteFailures": 0,
          "failureLogWriteFailures": 0,
          "redisIpWriteFailures": 0,
          "redisIpVerifyFailures": 0,
          "redisIpVerifyMismatches": 0,
          "spool": {
            "mode": "spool_and_replay",
            "status": "ready",
            "storage": "redis_list",
            "pendingItems": 12,
            "pendingBytes": 3456,
            "oldestPendingAgeSeconds": 34,
            "rejectedEvents": 2,
            "writeFailures": 0,
            "lastFailure": {
              "reason": "spool_full",
              "message": "pending item limit exceeded",
              "occurredAt": "2026-06-23T00:00:00Z"
            }
          },
          "replay": {
            "status": "degraded",
            "pendingItems": 12,
            "inFlightItems": 1,
            "retryableFailures": 3,
            "deadLetteredEvents": 0,
            "replayLagSeconds": 45,
            "maxBytesPerSecond": 2097152,
            "configuredMaxBytesPerSecond": 10485760,
            "adaptive": {
              "enabled": true,
              "minBytesPerSecond": 1048576,
              "maxBytesPerSecond": 10485760,
              "currentMaxBytesPerSecond": 2097152,
              "minConcurrency": 1,
              "maxConcurrency": 8,
              "currentConcurrency": 4,
              "lastDecision": "decrease",
              "lastReason": "replay_failures",
              "lastChangedAt": "2026-06-23T00:00:01Z",
              "memoryGuardStatus": "unavailable"
            },
            "lastFailure": {
              "reason": "upstream_timeout"
            }
          },
          "throughput": {
            "windowSeconds": 10,
            "observedBytesPerSecond": 5120.0,
            "spooledBytesPerSecond": 4096.0,
            "replayedBytesPerSecond": 3072.0,
            "queueGrowthBytesPerSecond": 1024.0
          },
          "recorders": [
            {
              "vrcode": "VR001",
              "activeConnections": 1,
              "spool": {
                "pendingItems": 3
              },
              "replay": {
                "retryableFailures": 1
              }
            }
          ]
        }
        """

        let decoded = try JSONDecoder().decode(
            RuntimeRecorderIngressStatusDocument.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.spool?.mode, "spool_and_replay")
        XCTAssertEqual(decoded.spool?.pendingItems, 12)
        XCTAssertEqual(decoded.spool?.pendingBytes, 3456)
        XCTAssertEqual(decoded.spool?.oldestPendingAgeSeconds, 34)
        XCTAssertEqual(decoded.spool?.lastFailure?.reason, "spool_full")
        XCTAssertEqual(decoded.replay?.status, "degraded")
        XCTAssertEqual(decoded.replay?.inFlightItems, 1)
        XCTAssertEqual(decoded.replay?.retryableFailures, 3)
        XCTAssertEqual(decoded.replay?.lastFailure?.reason, "upstream_timeout")
        XCTAssertEqual(decoded.replay?.configuredMaxBytesPerSecond, 10_485_760)
        XCTAssertEqual(decoded.replay?.adaptive?.currentMaxBytesPerSecond, 2_097_152)
        XCTAssertEqual(decoded.replay?.adaptive?.currentConcurrency, 4)
        XCTAssertEqual(decoded.replay?.adaptive?.lastDecision, "decrease")
        XCTAssertEqual(decoded.replay?.adaptive?.memoryGuardStatus, .unavailable)
        XCTAssertEqual(decoded.throughput?.windowSeconds, 10)
        XCTAssertEqual(decoded.throughput?.observedBytesPerSecond, 5120.0)
        XCTAssertEqual(decoded.throughput?.queueGrowthBytesPerSecond, 1024.0)
        XCTAssertEqual(decoded.recorders.first?.spool?.pendingItems, 3)
        XCTAssertEqual(decoded.recorders.first?.replay?.retryableFailures, 1)

        let legacy = try JSONDecoder().decode(
            RuntimeRecorderIngressStatusDocument.self,
            from: Data(
                """
                {
                  "activeWebSockets": 1,
                  "activeRecorderConnections": 1,
                  "recorders": [],
                  "httpRequests": 0,
                  "socketIoEventsSeen": 0,
                  "socketIoParseFailures": 0,
                  "auditWriteFailures": 0,
                  "auditFileWriteFailures": 0,
                  "auditStdoutWriteFailures": 0,
                  "failureLogWriteFailures": 0,
                  "redisIpWriteFailures": 0,
                  "redisIpVerifyFailures": 0,
                  "redisIpVerifyMismatches": 0
                }
                """.utf8
            )
        )
        XCTAssertNil(legacy.spool)
        XCTAssertNil(legacy.replay)

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RuntimeRecorderIngressStatusDocument.self,
                from: Data(#"{"activeWebSockets":1,"activeRecorderConnections":1}"#.utf8)
            )
        )

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RuntimeRecorderIngressStatusDocument.self,
                from: Data(
                    """
                    {
                      "activeWebSockets": 1,
                      "activeRecorderConnections": 1,
                      "recorders": [],
                      "httpRequests": 0,
                      "socketIoEventsSeen": 0,
                      "socketIoParseFailures": 0,
                      "auditWriteFailures": 0,
                      "auditFileWriteFailures": 0,
                      "auditStdoutWriteFailures": 0,
                      "failureLogWriteFailures": 0,
                      "redisIpWriteFailures": 0,
                      "redisIpVerifyFailures": 0,
                      "redisIpVerifyMismatches": 0,
                      "replay": {
                        "adaptive": {
                          "memoryGuardStatus": "not-ready"
                        }
                      }
                    }
                    """.utf8
                )
            )
        )
    }

    func testDecodesRuntimeStatusV1() throws {
        let document = try decodeFixture(RuntimeStatusDocument.self, named: "runtime-status-v1-healthy")

        XCTAssertNil(document.schemaVersion)
        XCTAssertEqual(document.status, .healthy)
        XCTAssertEqual(document.proxyPort, 80)
    }

    func testDecodesRuntimeStatusV2IgnoringLegacyEmbeddedProgress() throws {
        let document = try decodeFixture(RuntimeStatusDocument.self, named: "runtime-status-updating")

        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.status, .updating)

        let encoded = try JSONEncoder().encode(document)
        let encodedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(encodedObject["progress"])
        XCTAssertNil(encodedObject["operation"])
        XCTAssertNil(encodedObject["message"])
        XCTAssertNil(encodedObject["updatedAt"])
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
        XCTAssertEqual(
            RuntimeOperation(rawValue: "apply-update-bootstrap"),
            .applyUpdateBootstrap
        )
        XCTAssertEqual(
            RuntimeOperation.applyUpdateBootstrap.rawValue,
            "apply-update-bootstrap"
        )
        XCTAssertEqual(RuntimeOperation(rawValue: "runtime-data-backup"), .runtimeDataBackup)
        XCTAssertEqual(RuntimeOperation.runtimeDataBackup.rawValue, "runtime-data-backup")
        XCTAssertEqual(RuntimeOperation(rawValue: "automatic-backup"), .automaticBackup)
        XCTAssertEqual(RuntimeOperation.automaticBackup.rawValue, "automatic-backup")
        XCTAssertEqual(RuntimeOperation(rawValue: "runtime-data-restore"), .runtimeDataRestore)
        XCTAssertEqual(RuntimeOperation.runtimeDataRestore.rawValue, "runtime-data-restore")
    }

    func testRuntimeDataRestoreWorkflowStepRoundTrips() {
        XCTAssertEqual(
            RuntimeWorkflowStep(rawValue: "restore-runtime-data-backup"),
            .restoreRuntimeDataBackup
        )
        XCTAssertEqual(
            RuntimeWorkflowStep.restoreRuntimeDataBackup.rawValue,
            "restore-runtime-data-backup"
        )
        XCTAssertEqual(RuntimeWorkflowStep.restoreRuntimeDataBackup.operation, .runtimeDataRestore)
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

    func testDecodesGuestRuntimeObservation() throws {
        let document = try decodeFixture(GuestRuntimeObservationDocument.self, named: "runtime-observation-ready")

        XCTAssertEqual(document.vmIP, "192.168.64.2")
        XCTAssertEqual(document.bootID, "7b6a6afd-64f8-4dd5-91f1-6dcbf58f8f7d")
        XCTAssertEqual(document.memory?.percent, 25.0)
        XCTAssertEqual(document.systemDisk?.percent, 31.25)
        XCTAssertEqual(document.vitalFilesDisk?.percent, 25.0)
    }

    func testDecodesGuestRuntimeObservationProbeErrors() throws {
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
        let document = try JSONDecoder().decode(GuestRuntimeObservationDocument.self, from: Data(json.utf8))

        XCTAssertNil(document.vmIP)
        XCTAssertEqual(document.probeErrors, [
            GuestRuntimeProbeError(
                source: "vmIP",
                message: "no non-loopback IP address found"
            ),
        ])
    }

    func testDecodesGuestRuntimeObservationDiskHealth() throws {
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
        let document = try JSONDecoder().decode(GuestRuntimeObservationDocument.self, from: Data(json.utf8))

        XCTAssertEqual(document.diskHealth, GuestDiskHealthDocument(
            rootFilesystemReadOnly: true,
            kernelErrors: ["EXT4-fs error (device vda1): checksum invalid"]
        ))
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
          "vmErrors": ["vm-future-error", "vm-service-state-paused"],
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
        XCTAssertEqual(document.vmService, .loaded)
        XCTAssertEqual(document.rootfsBase, .present)

        let encoded = try JSONEncoder().encode(document)
        let encodedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(encodedObject["progress"])
        XCTAssertNil(encodedObject["vmState"])
        XCTAssertNil(encodedObject["vmErrors"])
        XCTAssertNil(encodedObject["failureReasons"])
        XCTAssertNil(encodedObject["domainErrors"])
        XCTAssertNil(encodedObject["operation"])
        XCTAssertNil(encodedObject["message"])
        XCTAssertNil(encodedObject["updatedAt"])
        let roundTripped = try JSONDecoder().decode(RuntimeStatusDocument.self, from: encoded)
        XCTAssertEqual(roundTripped.status.rawValue, "paused")
        XCTAssertEqual(roundTripped.vmService.rawValue, "loaded")
        XCTAssertEqual(roundTripped.rootfsBase.rawValue, "present")
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
            .launchFailed("virtualization"),
            .invalidConfiguration("network"),
            .hostResourceUnavailable("memory"),
            .diskAttachmentInvalid,
            .guestFilesystemError,
            .guestFilesystemReadOnly,
            .guestDiskIO,
            .guestHTTP("failed"),
            .guestHTTPProbeFailed("failed"),
            .guestBootstrapMissingRuntimePackages,
            .guestBootstrapDockerRuntimeFailed,
            .guestBootstrapFailed,
        ]

        XCTAssertEqual(errors.map(\.rawValue), [
            "vm-missing-executable",
            "vm-missing-rootfs-base",
            "vm-missing-disk",
            "vm-service-state-not loaded",
            "vm-missing-ip-address",
            "vm-launch-failed-virtualization",
            "vm-invalid-configuration-network",
            "vm-host-resource-unavailable-memory",
            "vm-disk-attachment-invalid",
            "vm-guest-filesystem-error",
            "vm-guest-filesystem-read-only",
            "vm-guest-disk-io-error",
            "vm-guest-http-failed",
            "vm-guest-http-probe-failed-failed",
            "vm-guest-bootstrap-missing-runtime-packages",
            "vm-guest-bootstrap-docker-runtime-failed",
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

        XCTAssertEqual(RuntimeVMError.unknown("vm-future-error").category, .unknown)
        XCTAssertEqual(RuntimeVMError.unknown("vm-future-error").recoveryAction, .inspectLogs)
        XCTAssertFalse(RuntimeVMError.unknown("vm-future-error").requiresDataPreservationBeforeRecovery)
        XCTAssertEqual(RuntimeVMError.guestHTTPProbeFailed("failed").category, .networking)
        XCTAssertEqual(RuntimeVMError.guestHTTPProbeFailed("failed").recoveryAction, .waitForGuest)
    }

    func testRuntimeFailureReasonsDecodeAsTypedCodes() throws {
        let cases: [(String, RuntimeFailureReason)] = [
            ("missing-vm-bin", .missingVMBin),
            ("vm-service-not loaded", .vmService("not loaded")),
            ("guest-log-sync-service-not-loaded", .guestLogSyncService("not-loaded")),
            ("host-proxy-http-502", .hostProxyHTTP("502")),
            ("guest-http-probe-failed-failed", .guestHTTPProbeFailed("failed")),
            ("recorder-ingress-http-failed", .recorderIngressHTTP("failed")),
            ("container-service-app-state-unhealthy", .containerService(service: "app", state: "unhealthy")),
            ("vitaldb-anomaly-duplicate-ip-subject-10.0.0.10", .vitalDBAnomaly(kind: "duplicate-ip", subject: "10.0.0.10")),
            ("proxy-port-80-in-use-by-nginx-1234", .proxyPortInUse(port: 80, listeners: "nginx-1234")),
            ("host-proxy-listener-scan-unavailable", .hostProxyListenerScanUnavailable),
            (
                "host-proxy-listener-scan-inspection-failed-path=/usr/sbin/lsof reason=permission denied",
                .hostProxyListenerScanInspectionFailed("path=/usr/sbin/lsof reason=permission denied")
            ),
            ("host-proxy-listener-scan-failed-port-80-exit-1", .hostProxyListenerScanFailed(port: 80, exitCode: 1)),
            ("guest-bootstrap-missing-runtime-packages", .guestBootstrapMissingRuntimePackages),
            ("guest-bootstrap-docker-runtime-failed", .guestBootstrapDockerRuntimeFailed),
            ("vm-disk-attachment-invalid", .vmDiskAttachmentInvalid),
            ("vm-launch-failed-virtualization", .vmLaunchFailed("virtualization")),
            ("vm-invalid-configuration-network", .vmConfigurationInvalid("network")),
            ("vm-host-resource-unavailable-memory", .hostResourceUnavailable("memory")),
            ("guest-filesystem-error", .guestFilesystemError),
            ("guest-filesystem-read-only", .guestFilesystemReadOnly),
            ("guest-disk-io-error", .guestDiskIO),
            ("future-reason", .unknown("future-reason")),
        ]
        let rawValues = cases.map { $0.0 }
        let json = try JSONSerialization.data(withJSONObject: rawValues)
        let reasons = try JSONDecoder().decode([RuntimeFailureReason].self, from: json)

        XCTAssertEqual(reasons, cases.map { $0.1 })

        let encoded = try JSONEncoder().encode(reasons)
        let roundTripped = try JSONDecoder().decode([RuntimeFailureReason].self, from: encoded)
        XCTAssertEqual(roundTripped.map(\.rawValue), rawValues)
    }

    func testRuntimeFailureReasonsDefineDomainClassificationAndRecovery() {
        XCTAssertEqual(RuntimeFailureReason.proxyPortInUse(port: 80, listeners: "nginx-1234").domainCategory, .hostProxy)
        XCTAssertEqual(RuntimeFailureReason.proxyPortInUse(port: 80, listeners: "nginx-1234").recoveryAction, .freeProxyPort)
        XCTAssertEqual(RuntimeFailureReason.proxyPortInUse(port: 80, listeners: "nginx-1234").domainSeverity, .critical)

        XCTAssertEqual(RuntimeFailureReason.recorderIngressHTTP("failed").domainCategory, .container)
        XCTAssertEqual(RuntimeFailureReason.recorderIngressHTTP("failed").recoveryAction, .reconcileGuestStack)

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

        XCTAssertEqual(RuntimeFailureReason(rawValue: "vm-disk-attachment-invalid"), .vmDiskAttachmentInvalid)

        XCTAssertEqual(RuntimeFailureReason(vmError: .unknown("future-vm-error")), .unknown("future-vm-error"))
        XCTAssertEqual(RuntimeFailureReason.unknown("future-reason").domainCategory, .unknown)
        XCTAssertEqual(RuntimeFailureReason.unknown("future-reason").recoveryAction, .inspectLogs)

        XCTAssertEqual(RuntimeFailureReason(vmError: .diskAttachmentInvalid), .vmDiskAttachmentInvalid)
        XCTAssertEqual(RuntimeFailureReason.vmDiskAttachmentInvalid.domainCategory, .guestStorage)
        XCTAssertEqual(RuntimeFailureReason.vmDiskAttachmentInvalid.recoveryAction, .backupAndRecreateVM)
        XCTAssertTrue(RuntimeFailureReason.vmDiskAttachmentInvalid.requiresDataPreservationBeforeRecovery)

        XCTAssertEqual(RuntimeFailureReason(vmError: .guestFilesystemError), .guestFilesystemError)
        XCTAssertEqual(RuntimeFailureReason(vmError: .guestFilesystemReadOnly), .guestFilesystemReadOnly)
        XCTAssertEqual(RuntimeFailureReason(vmError: .guestDiskIO), .guestDiskIO)
        XCTAssertEqual(RuntimeFailureReason.guestFilesystemReadOnly.domainCategory, .guestStorage)
        XCTAssertEqual(RuntimeFailureReason.guestFilesystemReadOnly.domainSeverity, .critical)
        XCTAssertEqual(RuntimeFailureReason.guestFilesystemReadOnly.recoveryAction, .backupAndRecreateVM)
        XCTAssertTrue(RuntimeFailureReason.guestFilesystemReadOnly.requiresDataPreservationBeforeRecovery)

        XCTAssertEqual(RuntimeFailureReason(vmError: .launchFailed("virtualization")), .vmLaunchFailed("virtualization"))
        XCTAssertEqual(RuntimeFailureReason.vmLaunchFailed("virtualization").domainCategory, .vmLifecycle)
        XCTAssertEqual(RuntimeFailureReason.vmLaunchFailed("virtualization").recoveryAction, .inspectLogs)

        XCTAssertEqual(RuntimeFailureReason(vmError: .invalidConfiguration("network")), .vmConfigurationInvalid("network"))
        XCTAssertEqual(RuntimeFailureReason.vmConfigurationInvalid("network").domainCategory, .configuration)
        XCTAssertEqual(RuntimeFailureReason.vmConfigurationInvalid("network").recoveryAction, .fixConfiguration)

        XCTAssertEqual(RuntimeFailureReason(vmError: .hostResourceUnavailable("memory")), .hostResourceUnavailable("memory"))
        XCTAssertEqual(RuntimeFailureReason.hostResourceUnavailable("memory").domainCategory, .hostResources)
        XCTAssertEqual(RuntimeFailureReason.hostResourceUnavailable("memory").recoveryAction, .freeHostResources)

        XCTAssertEqual(RuntimeFailureReason.redisUIHTTP("failed").domainSeverity, .warning)
        XCTAssertEqual(RuntimeFailureReason.redisUIHTTP("failed").recoveryAction, .inspectLogs)

        XCTAssertEqual(RuntimeFailureReason.guestHTTPProbeFailed("failed").domainCategory, .guestNetworking)
        XCTAssertEqual(RuntimeFailureReason.guestHTTPProbeFailed("failed").domainSeverity, .warning)
        XCTAssertEqual(RuntimeFailureReason.guestHTTPProbeFailed("failed").recoveryAction, .waitForGuest)

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
        XCTAssertEqual(RuntimeFailureReason.containerRestartLoop(service: "redis").recoveryAction, .reconcileGuestStack)

        XCTAssertEqual(RuntimeFailureReason.guestBootstrapDockerRuntimeFailed.domainCategory, .guestBootstrap)
        XCTAssertEqual(RuntimeFailureReason.guestBootstrapDockerRuntimeFailed.recoveryAction, .repairGuestBootstrap)
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
            .recorderIngressObserved,
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
            "recorder-ingress-observed",
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
            eventType: .recorderIngressObserved,
            since: "2026-05-24T00:00:00Z",
            before: cursor
        )

        XCTAssertEqual(query.limit, 25)
        XCTAssertEqual(query.eventType, .recorderIngressObserved)
        XCTAssertEqual(query.since, "2026-05-24T00:00:00Z")
        XCTAssertEqual(query.before, cursor)
    }

    func testRuntimeOperationEventQueryKeepsGuestLedgerEventTypesSeparate() {
        XCTAssertEqual(RuntimeOperationEventQuery().limit, 100)
        let query = RuntimeOperationEventQuery(
            limit: 25,
            eventType: .interrupted,
            since: "2026-05-24T00:00:00Z",
            cursor: "event:12"
        )

        XCTAssertEqual(query.limit, 25)
        XCTAssertEqual(query.eventType, .interrupted)
        XCTAssertEqual(query.since, "2026-05-24T00:00:00Z")
        XCTAssertEqual(query.cursor, "event:12")
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

    func testRuntimeOperationEventHistoryRequiresAndWritesExplicitNullablePagination() throws {
        let history = RuntimeOperationEventHistory(
            events: [],
            nextCursor: nil,
            matchingCount: nil
        )
        let encoded = try JSONEncoder().encode(history)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertTrue(object["nextCursor"] is NSNull)
        XCTAssertTrue(object["matchingCount"] is NSNull)
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RuntimeOperationEventHistory.self,
                from: Data(#"{"events":[]}"#.utf8)
            )
        )
    }

    private func decodeFixture<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
