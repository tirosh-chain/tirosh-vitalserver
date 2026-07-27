import { describe, expect, it } from "vitest";

import {
  runtimeCommandResponseSchema,
  platformCapabilitiesSchema,
  runtimeCapabilitiesSchema,
  runtimeEventHistorySchema,
  runtimeGuestControlServiceOperationSchema,
  runtimeLogExportResultSchema,
  runtimeLogTextResponseSchema,
  runtimeLabSessionListSchema,
  platformOperationStateSchema,
  platformWorkflowOperationSchema,
  platformWorkflowResourceSchema,
  runtimeProviderCommandResponseSchema,
  recorderVitalFileHistorySchema,
  recorderObservabilityDetailSchema,
  runtimeRedisRelaySettingsReadSchema,
  runtimeRedisRelayStatusReadResultSchema,
  platformStateSchema,
  runtimeSettingsSchema,
  runtimeUpdateBundleSummaryResponseSchema,
  vitalDBObservationSchema,
  vitalDBRecordersSchema,
  vitalDBRelationshipsSchema
} from "./runtimeControlSchemas";

describe("runtime control contract schemas", () => {
  it("preserves explicit Recorder observability read states and rejects raw aggregate fields", () => {
    const detail = fullRecorderObservabilityDetail();
    const withoutObserver = recorderWithoutObserverDetail();

    expect(recorderObservabilityDetailSchema.parse(detail)).toEqual(detail);
    expect(recorderObservabilityDetailSchema.parse(withoutObserver)).toEqual(
      withoutObserver
    );
    expect(
      recorderObservabilityDetailSchema.safeParse({
        ...detail,
        resources: {}
      }).success
    ).toBe(false);
    expect(
      recorderObservabilityDetailSchema.safeParse({
        ...detail,
        state: "unavailable",
        readError: null
      }).success
    ).toBe(false);
    expect(
      recorderObservabilityDetailSchema.safeParse({
        ...detail,
        operationalHealth: {
          ...detail.operationalHealth,
          issueCount: 1
        }
      }).success
    ).toBe(false);
  });

  it("requires complete Product Lab session failure evidence", () => {
    const failedSession = {
      state: "loaded" as const,
      sessions: [
        {
          sessionId: "lab-replay-failed",
          state: "failed" as const,
          scenarioId: "vital-file-replay",
          name: "Vital File Replay",
          recorderCount: 1,
          targetURL: "http://edge/",
          failure: {
            stage: "fileValidation",
            code: "noVitalServerGraphTracks",
            message: "Vital File contains no VitalServer graph-compatible tracks.",
            failedAt: "2026-07-22T08:45:00Z"
          },
          createdAt: "2026-07-22T08:44:59Z",
          updatedAt: "2026-07-22T08:45:00Z"
        }
      ],
      readError: null
    };

    expect(runtimeLabSessionListSchema.parse(failedSession).sessions[0]?.failure)
      .toMatchObject({ code: "noVitalServerGraphTracks" });

    const missingCode = structuredClone(failedSession);
    delete (missingCode.sessions[0]?.failure as { code?: string }).code;
    expect(() => runtimeLabSessionListSchema.parse(missingCode)).toThrow(/code/);
  });

  it("accepts explicit Lab archive export states and required nullable evidence", () => {
    const response = (state: "exported" | "published") => ({
      state: "loaded" as const,
      sessions: [
        {
          sessionId: "lab-session-1",
          state: "finished" as const,
          scenarioId: "baseline-monitoring",
          name: "Baseline Monitoring",
          recorderCount: 1,
          targetURL: null,
          archiveFinalization: {
            state,
            updatedAt: null,
            readError: null
          },
          createdAt: "2026-07-22T00:00:00Z",
          updatedAt: "2026-07-22T00:05:00Z"
        }
      ],
      readError: null
    });

    expect(runtimeLabSessionListSchema.parse(response("exported")))
      .toMatchObject({ sessions: [{ archiveFinalization: { state: "exported" } }] });
    expect(runtimeLabSessionListSchema.parse(response("published")))
      .toMatchObject({ sessions: [{ archiveFinalization: { state: "published" } }] });

    const missingUpdatedAt = response("exported");
    delete (missingUpdatedAt.sessions[0].archiveFinalization as { updatedAt?: null }).updatedAt;
    expect(() => runtimeLabSessionListSchema.parse(missingUpdatedAt)).toThrow(/updatedAt/);

    expect(() =>
      runtimeLabSessionListSchema.parse({
        ...response("exported"),
        sessions: [
          {
            ...response("exported").sessions[0],
            archiveFinalization: {
              state: "uploaded",
              updatedAt: null,
              readError: null
            }
          }
        ]
      })
    ).toThrow(/state/);
  });

  it("requires explicit null fields for missing workflows and unavailable Redis Relay settings", () => {
    expect(
      platformWorkflowResourceSchema.parse({
        state: "missing",
        operation: null,
        readError: null
      })
    ).toMatchObject({ state: "missing", operation: null, readError: null });
    expect(() =>
      platformWorkflowResourceSchema.parse({ state: "missing", readError: null })
    ).toThrow(/operation/);

    expect(
      runtimeRedisRelaySettingsReadSchema.parse({
        state: "unavailable",
        settings: null,
        readError: "Redis Relay configuration is unavailable."
      })
    ).toMatchObject({ state: "unavailable", settings: null });
    expect(() =>
      runtimeRedisRelaySettingsReadSchema.parse({ state: "unavailable", settings: null })
    ).toThrow(/readError/);
  });

  it("requires artifact evidence only for a completed support export", () => {
    const completed = {
      schemaVersion: 1,
      operationId: "workflow-0123456789abcdef0123456789abcdef",
      kind: "support-export",
      state: "completed",
      startedAt: "2026-07-11T00:00:00Z",
      updatedAt: "2026-07-11T00:00:01Z",
      release: null,
      artifact: {
        path: "/var/lib/vitalserver/support/support.tar.gz",
        sha256: "a".repeat(64),
        sizeBytes: 42
      },
      failure: null
    };
    expect(platformWorkflowOperationSchema.parse(completed)).toEqual(completed);
    expect(() => platformWorkflowOperationSchema.parse({ ...completed, artifact: null })).toThrow();
    expect(() => platformWorkflowOperationSchema.parse({ ...completed, kind: "update-apply" })).toThrow();
  });

  it("accepts a command response from Runtime Control API", () => {
    expect(
      runtimeCommandResponseSchema.parse({
        result: {
          exitCode: 0,
          stdout: "ok",
          stderr: "",
          outputIssues: [],
          executionIssue: null
        }
      })
    ).toEqual({
      result: {
        exitCode: 0,
        stdout: "ok",
        stderr: "",
        outputIssues: [],
        executionIssue: null
      }
    });
    expect(() =>
      runtimeCommandResponseSchema.parse({
        result: {
          exitCode: 0,
          stdout: "ok",
          stderr: "",
          executionIssue: null
        }
      })
    ).toThrow();
    expect(() =>
      runtimeCommandResponseSchema.parse({
        result: {
          exitCode: 0,
          stdout: "ok",
          stderr: "",
          outputIssues: []
        }
      })
    ).toThrow();
  });

  it("preserves explicit Runtime Provider command and resource states", () => {
    const completed = {
      operationId: "provider-restart-1",
      action: "restart" as const,
      state: "completed" as const,
      provider: {
        state: "loaded" as const,
        document: {
          schemaVersion: 1,
          state: "running" as const,
          operation: "restart",
          operationID: "provider-restart-1",
          bootID: "boot-1",
          startedAt: "2026-07-01T00:00:00Z",
          updatedAt: "2026-07-01T00:00:01Z",
          deadlineAt: null,
          terminalReason: null,
          message: null
        },
        readError: null
      },
      failure: null
    };

    expect(runtimeProviderCommandResponseSchema.parse(completed)).toEqual(completed);
    expect(
      runtimeProviderCommandResponseSchema.parse({
        ...completed,
        state: "failed",
        provider: { state: "missing", document: null, readError: "not created" },
        failure: { kind: "permission-denied", message: "system service access denied" }
      })
    ).toMatchObject({ state: "failed", failure: { kind: "permission-denied" } });
    expect(() =>
      runtimeProviderCommandResponseSchema.parse({
        ...completed,
        state: "failed",
        failure: null
      })
    ).toThrow();
    expect(() =>
      runtimeProviderCommandResponseSchema.parse({
        ...completed,
        provider: { state: "loaded", document: null, readError: null }
      })
    ).toThrow();

    expect(
      runtimeProviderCommandResponseSchema.parse({
        ...completed,
        provider: {
          state: "loaded",
          document: {
            ...completed.provider.document,
            state: "waiting-for-hypervisor",
            terminalReason: null
          },
          readError: null
        }
      }).provider.document
    ).toMatchObject({ state: "waiting-for-hypervisor" });
    expect(
      runtimeProviderCommandResponseSchema.parse({
        ...completed,
        provider: {
          state: "loaded",
          document: {
            ...completed.provider.document,
            state: "failed",
            terminalReason: "hyperv-provider-exit"
          },
          readError: null
        }
      }).provider.document
    ).toMatchObject({ terminalReason: "hyperv-provider-exit" });
  });

  it("preserves operation state read meanings", () => {
    expect(
      platformOperationStateSchema.parse({
        activeOperation: "apply-bundle",
        install: {
          state: "failed",
          document: null,
          readError: "install state decode failed"
        },
        lease: {
          state: "stale",
          document: {
            schemaVersion: 1,
            operationId: "operation-1",
            operation: "apply-bundle",
            ownerPID: 123,
            startedAt: "2026-07-08T00:00:00Z",
            heartbeatAt: "2026-07-08T00:00:01Z",
            expiresAt: "2026-07-08T00:00:02Z",
            message: null
          },
          readError: null,
          staleReason: "expired"
        }
      })
    ).toMatchObject({
      install: { state: "failed", readError: "install state decode failed" },
      lease: { state: "stale", staleReason: "expired" }
    });
  });

  it("rejects failed or stale operation state without explicit reason", () => {
    expect(() =>
      platformOperationStateSchema.parse({
        activeOperation: null,
        install: {
          state: "failed",
          document: null,
          readError: null
        },
        lease: {
          state: "stale",
          document: null,
          readError: null,
          staleReason: null
        }
      })
    ).toThrow();
  });

  it("rejects operation state payloads that omit explicit null fields", () => {
    expect(() =>
      platformOperationStateSchema.parse({
        install: {
          state: "unavailable"
        },
        lease: {
          state: "unavailable"
        }
      })
    ).toThrow();
  });

  it("accepts unknown platform health values in PlatformState responses", () => {
    expect(platformStateSchema.parse({ services: platformServices(), runtimeInstallationState: "missing", platformHealth: "surprising-from-helper" }).platformHealth)
      .toBe("surprising-from-helper");
  });

  it("accepts Remote Console fields in PlatformState responses", () => {
    expect(
      platformStateSchema.parse({ services: platformServices(), runtimeInstallationState: "missing",
        platformAPIHTTP: "200",
        platformAPIStartedAt: "2026-05-26T04:30:00Z"
      })
    ).toMatchObject({
      platformAPIHTTP: "200",
      platformAPIStartedAt: "2026-05-26T04:30:00Z"
    });
  });

  it("accepts PlatformState responses without container observation", () => {
    expect(
      platformStateSchema.parse({ services: platformServices(), runtimeInstallationState: "missing",
        platformHealth: "healthy",
        installedVersion: "loaded"
      })
    ).toMatchObject({
      platformHealth: "healthy",
      installedVersion: "loaded"
    });
  });

  it("rejects Runtime-owned product state from Host PlatformState", () => {
    for (const field of [
      "redisRelayStatus",
      "guestServicesReadState",
      "guestServices",
      "guestServiceStatuses",
      "guestServiceResources",
      "guestServiceResourceReadIssues",
      "guestStackProbeErrors",
      "guestServicesReadError",
      "cpuUsagePercent",
      "memory",
      "vitalServerMemory",
      "recorderIngressMemory",
      "redisMemory",
      "systemDisk"
    ]) {
      expect(() =>
        platformStateSchema.parse({ services: platformServices(), runtimeInstallationState: "missing",
          platformHealth: "healthy",
          [field]: null
        })
      ).toThrow(new RegExp(field));
    }
  });

  it("requires explicit PlatformState installation state instead of legacy installed bool", () => {
    expect(
      platformStateSchema.parse({
        services: platformServices(),
        runtimeInstallationState: "present"
      })
    ).toMatchObject({
      runtimeInstallationState: "present"
    });
    expect(() =>
      platformStateSchema.parse({
        services: platformServices(),
        runtimeInstalled: true,
        runtimeInstallationState: "present"
      })
    ).toThrow(/runtimeInstalled/);
  });

  it("requires complete Redis Relay status owner resource documents", () => {
    const redisRelayStatus = {
      schemaVersion: 1,
      observedAt: "2026-07-01T00:00:00Z",
      enabled: true,
      state: "running",
      scope: null,
      targetUrl: null,
      targetUsernameConfigured: false,
      targetPasswordConfigured: false,
      settingsFingerprint: null,
      batches: 0,
      totals: {
        scanned: 0,
        copied: 0,
        published: 0,
        unchanged: 0,
        duplicates: 0,
        skipped: 0,
        denied: 0,
        missing: 0,
        errors: 0
      },
      lastBatch: null,
      lastSuccessAt: null,
      lastErrorAt: null,
      lastError: null
    };

    expect(
      runtimeRedisRelayStatusReadResultSchema.parse({
        readState: "loaded",
        document: redisRelayStatus,
        readError: null
      }).document
    ).toMatchObject({
      state: "running",
      scope: null,
      targetUrl: null,
      totals: {
        copied: 0,
        published: 0,
        duplicates: 0
      }
    });

    expect(() =>
      runtimeRedisRelayStatusReadResultSchema.parse({
        readState: "loaded",
        document: {
          ...redisRelayStatus,
          scope: undefined
        },
        readError: null
      })
    ).toThrow(/scope/);

    expect(() =>
      runtimeRedisRelayStatusReadResultSchema.parse({
        readState: "loaded",
        document: {
          ...redisRelayStatus,
          targetUrl: undefined
        },
        readError: null
      })
    ).toThrow(/targetUrl/);

    expect(() =>
      runtimeRedisRelayStatusReadResultSchema.parse({
        readState: "loaded",
        document: {
          ...redisRelayStatus,
          totals: {
            scanned: 0,
            copied: 0,
            unchanged: 0,
            duplicates: 0,
            skipped: 0,
            denied: 0,
            missing: 0,
            errors: 0
          }
        },
        readError: null
      })
    ).toThrow(/published/);

    expect(() =>
      platformStateSchema.parse({ services: platformServices(), runtimeInstallationState: "missing",
        platformHealth: "healthy",
        redisRelayStatus
      })
    ).toThrow(/Runtime owner resource/);
  });

  it("rejects legacy Guest address evidence from PlatformState", () => {
    expect(() =>
      platformStateSchema.parse({ services: platformServices(), runtimeInstallationState: "missing",
        platformHealth: "healthy",
        guestAddressRead: {
          state: "loaded",
          address: "192.168.64.2",
          source: "platform-agent",
          reason: null
        }
      })
    ).toThrow(/guestAddressRead/);
  });

  it("accepts unknown runtime provider states in PlatformState responses", () => {
    expect(platformStateSchema.parse({ services: platformServices(), runtimeInstallationState: "missing", runtimeProviderState: "hibernating" }).runtimeProviderState)
      .toBe("hibernating");
  });

  it("requires canonical Platform service state and explicit read error", () => {
    expect(
      platformStateSchema.parse({
        services: platformServices(),
        runtimeInstallationState: "executable"
      }).services[0]
    ).toEqual({ role: "runtime-provider", state: "running", readError: null });

    expect(() =>
      platformStateSchema.parse({
        services: [
          { role: "runtime-provider", state: "loaded", readError: null },
          ...platformServices().slice(1)
        ],
        runtimeInstallationState: "executable"
      })
    ).toThrow();
    expect(() =>
      platformStateSchema.parse({
        services: [
          { role: "runtime-provider", state: "running" },
          ...platformServices().slice(1)
        ],
        runtimeInstallationState: "executable"
      })
    ).toThrow();
    expect(() =>
      platformStateSchema.parse({
        services: [
          { role: "runtime-provider", state: "read-failed", readError: "" },
          ...platformServices().slice(1)
        ],
        runtimeInstallationState: "executable"
      })
    ).toThrow();
  });

  it("requires each fixed Platform service role exactly once", () => {
    const base = {
      runtimeInstallationState: "missing",
      services: platformServices()
    };

    expect(platformStateSchema.parse(base).services).toHaveLength(5);
    expect(() =>
      platformStateSchema.parse({ ...base, services: [] })
    ).toThrow(/Platform service role is required/);
    expect(() =>
      platformStateSchema.parse({
        ...base,
        services: base.services.filter(
          (service) => service.role !== "log-sync"
        )
      })
    ).toThrow(/Platform service role is required: log-sync/);
    expect(() =>
      platformStateSchema.parse({
        ...base,
        services: [
          ...base.services,
          { role: "watchdog", state: "unavailable", readError: "duplicate" }
        ]
      })
    ).toThrow(/Platform service role must be reported exactly once: watchdog/);
  });

  it("accepts all Runtime Controller settings apply operation commands", () => {
    for (const command of [
      "apply-settings",
      "apply-admin-password",
      "apply-redis-relay-settings",
      "repair-datastore"
    ]) {
      expect(
        runtimeGuestControlServiceOperationSchema.parse({
          operationId: `operation-${command}`,
          service: "runtime-settings",
          command,
          state: "completed",
          createdAt: "2026-07-01T00:00:00Z",
          updatedAt: "2026-07-01T00:00:01Z",
          failure: null
        }).command
      ).toBe(command);
    }
  });

  it("preserves an interrupted control operation and its explicit result", () => {
    const operation = runtimeGuestControlServiceOperationSchema.parse({
      operationId: "operation-restarted",
      service: "app",
      command: "restart",
      state: "interrupted",
      createdAt: "2026-07-01T00:00:00Z",
      updatedAt: "2026-07-01T00:00:01Z",
      failure: {
        kind: "controllerRestarted",
        message: "Runtime Controller restarted before the operation outcome was known."
      },
      result: { attemptedAt: "2026-07-01T00:00:00Z" }
    });

    expect(operation.state).toBe("interrupted");
    expect(operation.failure?.kind).toBe("controllerRestarted");
    expect(operation.result).toEqual({ attemptedAt: "2026-07-01T00:00:00Z" });
  });

  it("requires complete VitalDB recorder activity observations", () => {
    expect(() =>
      vitalDBObservationSchema.parse({
        ...fullVitalDBObservation(),
        recorders: [
          {
            vrcode: "VR_TEST",
            online: true,
            stale: false,
            activity: {
              windowSeconds: 300,
              messageCount: 2,
              byteCount: 1024
            }
          }
        ]
      })
    ).toThrow();

    expect(
      vitalDBObservationSchema.parse({
        ...fullVitalDBObservation(),
        recorders: [
          {
            vrcode: "VR_TEST",
            online: true,
            stale: false,
            activity: fullVitalDBRecorderActivity()
          }
        ]
      }).recorders[0]?.activity
    ).toMatchObject({
      messageCount: 2,
      byteCount: 1024,
      roomCount: 1,
      buckets: [
        {
          messageCount: 2
        }
      ]
    });
  });

  it("requires VitalDB recorder identity and status fields", () => {
    expect(() =>
      vitalDBObservationSchema.parse({
        ...fullVitalDBObservation(),
        recorders: [
          {
            online: true,
            stale: false
          }
        ]
      })
    ).toThrow();

    expect(() =>
      vitalDBObservationSchema.parse({
        ...fullVitalDBObservation(),
        recorders: [
          {
            vrcode: "VR_TEST",
            online: true
          }
        ]
      })
    ).toThrow();

    expect(
      vitalDBObservationSchema.parse({
        ...fullVitalDBObservation(),
        recorders: [
          {
            vrcode: "VR_TEST",
            online: true,
            stale: false
          }
        ]
      }).recorders[0]
    ).toMatchObject({
      vrcode: "VR_TEST",
      online: true,
      stale: false
    });
  });

  it("requires VitalDB bed identity and status fields", () => {
    expect(() =>
      vitalDBObservationSchema.parse({
        ...fullVitalDBObservation(),
        beds: [
          {
            online: true
          }
        ]
      })
    ).toThrow();

    expect(() =>
      vitalDBObservationSchema.parse({
        ...fullVitalDBObservation(),
        beds: [
          {
            bedID: "bed-1"
          }
        ]
      })
    ).toThrow();

    expect(
      vitalDBObservationSchema.parse({
        ...fullVitalDBObservation(),
        beds: [
          {
            bedID: "bed-1",
            online: true
          }
        ]
      }).beds[0]
    ).toMatchObject({
      bedID: "bed-1",
      online: true
    });
  });

  it("requires complete VitalDB anomaly observations", () => {
    expect(() =>
      vitalDBObservationSchema.parse({
        ...fullVitalDBObservation(),
        anomalies: [
          {
            id: "anomaly-1",
            kind: "duplicate-ip",
            severity: "warning",
            observedAt: "2026-05-31T01:00:00Z",
            subject: "10.0.0.10"
          }
        ]
      })
    ).toThrow();

    expect(
      vitalDBObservationSchema.parse({
        ...fullVitalDBObservation(),
        anomalies: [
          {
            id: "anomaly-1",
            kind: "duplicate-ip",
            severity: "warning",
            observedAt: "2026-05-31T01:00:00Z",
            subject: "10.0.0.10",
            message: "duplicate recorder IP"
          }
        ]
      }).anomalies[0]
    ).toMatchObject({
      id: "anomaly-1",
      kind: "duplicate-ip",
      severity: "warning",
      message: "duplicate recorder IP"
    });
  });

  it("requires the Runtime Controller operation event owner contract", () => {
    expect(() =>
      runtimeEventHistorySchema.parse({
        events: [
          {
            id: "event-1",
            eventType: "status-changed",
            timestamp: "2026-05-29T11:00:00Z",
            message: "status changed"
          }
        ],
        nextCursor: null,
        matchingCount: 1
      })
    ).toThrow();

    expect(
      runtimeEventHistorySchema.parse({
        events: [fullRuntimeEvent()],
        nextCursor: null,
        matchingCount: 1
      }).events?.[0]
    ).toMatchObject({
      id: "runtime-operation-event-1",
      source: "runtime-controller",
      eventType: "operation-completed",
      timestamp: "2026-05-29T11:00:00Z"
    });
  });

  it("requires explicit runtime event history and pagination state", () => {
    expect(() =>
      runtimeEventHistorySchema.parse({
        nextCursor: null,
        matchingCount: 0
      })
    ).toThrow();

    expect(() =>
      runtimeEventHistorySchema.parse({
        events: [],
        matchingCount: null
      })
    ).toThrow();

    expect(() =>
      runtimeEventHistorySchema.parse({
        events: [],
        nextCursor: null
      })
    ).toThrow();

    expect(() =>
      runtimeEventHistorySchema.parse({
        events: [],
        nextCursor: null,
        matchingCount: -1
      })
    ).toThrow();

    expect(
      runtimeEventHistorySchema.parse({
        events: [],
        nextCursor: null,
        matchingCount: null
      }).events
    ).toEqual([]);
  });

  it("rejects malformed VRecorder activity samples", () => {
    expect(() =>
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        recorders: [
          {
            ...fullVitalRecorderRecord(),
            activityTimeline: [{ messageCount: "not-a-number" }]
          }
        ]
      }))
    ).toThrow();
  });

  it("accepts VRecorder activity bucket samples", () => {
    expect(
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        recorders: [
          {
            ...fullVitalRecorderRecord(),
            activityTimeline: [
              {
                observedAt: "2026-05-28T00:01:00Z",
                windowSeconds: 60,
                messageCount: 2,
                byteCount: 1024,
                roomCount: 1,
                messagesPerSecond: 0.03,
                bytesPerSecond: 17.06,
                buckets: [
                  {
                    bucketStartedAt: "2026-05-28T00:00:00Z",
                    bucketSeconds: 60,
                    messageCount: 2,
                    byteCount: 1024,
                    roomCount: 1
                  }
                ]
              }
            ]
          }
        ]
      })).recorders?.[0]?.activityTimeline?.[0]?.buckets?.[0]
    ).toMatchObject({
      bucketStartedAt: "2026-05-28T00:00:00Z",
      messageCount: 2
    });
  });

  it("accepts not-observed VitalDB recorder and bed status values", () => {
    const parsedRecorders = vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
      recorders: [
        fullVitalRecorderRecord({
          vrcode: "VR_HISTORY",
          status: "notObserved",
          observationCount: 1,
          duplicateObservationCount: 1,
          presentInLatestObservation: false
        })
      ],
      beds: [
        fullVitalBedRecord({
          bedID: "bed-history",
          status: "notObserved",
          observationCount: 1,
          duplicateObservationCount: 2
        })
      ]
    }));

    expect(parsedRecorders.recorders?.[0]?.status).toBe("notObserved");
    expect(parsedRecorders.recorders?.[0]?.duplicateObservationCount).toBe(1);
    expect(parsedRecorders.beds?.[0]?.status).toBe("notObserved");
    expect(parsedRecorders.beds?.[0]?.duplicateObservationCount).toBe(2);
  });

  it("requires Vital Bed read model identity, status, and count fields", () => {
    expect(() =>
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        beds: [
          {
            bedID: "bed-1",
            status: "online"
          }
        ]
      }))
    ).toThrow();

    expect(
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        beds: [
          fullVitalBedRecord()
        ]
      })).beds?.[0]
    ).toMatchObject({
      bedID: "bed-1",
      status: "online",
      visibility: "visible",
      observationCount: 1,
      duplicateObservationCount: 0,
      currentAnomalyCount: 0
    });
  });

  it("requires Vital Recorder read model identity, status, and count fields", () => {
    expect(() =>
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        recorders: [
          {
            vrcode: "VR_TEST",
            status: "online"
          }
        ]
      }))
    ).toThrow();

    expect(
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        recorders: [
          fullVitalRecorderRecord()
        ]
      })).recorders?.[0]
    ).toMatchObject({
      vrcode: "VR_TEST",
      status: "online",
      visibility: "visible",
      observationCount: 1,
      duplicateObservationCount: 0,
      currentAnomalyCount: 0,
      presentInLatestObservation: true
    });
  });

  it("requires explicit nullable Vital Recorder and bed detail fields", () => {
    expect(() =>
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        recorders: [
          fullVitalRecorderRecord({
            latestAnomalyKind: undefined
          })
        ]
      }))
    ).toThrow();

    expect(() =>
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        recorders: [
          fullVitalRecorderRecord({
            activityTimeline: undefined
          })
        ]
      }))
    ).toThrow();

    expect(() =>
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        recorders: [
          fullVitalRecorderRecord({
            redisIPSync: {
              status: "unavailable"
            }
          })
        ]
      }))
    ).toThrow();

    expect(() =>
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        beds: [
          fullVitalBedRecord({
            linkedRecorderStatus: undefined
          })
        ]
      }))
    ).toThrow();
  });

  it("requires explicit VitalDB read model visibility", () => {
    expect(() =>
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        recorders: [
          fullVitalRecorderRecord({
            visibility: undefined
          })
        ]
      }))
    ).toThrow();

    expect(() =>
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        beds: [
          fullVitalBedRecord({
            visibility: undefined
          })
        ]
      }))
    ).toThrow();

    expect(
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        recorders: [
          fullVitalRecorderRecord({
            visibility: "hidden"
          })
        ],
        beds: [
          fullVitalBedRecord({
            visibility: "hidden"
          })
        ]
      }))
    ).toMatchObject({
      recorders: [{ visibility: "hidden" }],
      beds: [{ visibility: "hidden" }]
    });
  });

  it("requires Vital Recorder history lists and activity provenance", () => {
    expect(() =>
      vitalDBRecordersSchema.parse({
        activityHistory: fullRecorderActivityHistory()
      })
    ).toThrow();

    expect(() =>
      vitalDBRecordersSchema.parse({
        state: "loaded",
        updatedAt: null,
        recorders: [],
        beds: [],
        summary: fullVitalRecorderHistorySummary(),
        activityHistory: {
          source: "readModelProjection"
        },
        recorderIngressStatusRead: null,
        readError: null
      })
    ).toThrow();

    expect(() =>
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        state: undefined
      }))
    ).toThrow();

    expect(() =>
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        readError: undefined
      }))
    ).toThrow();

    expect(() =>
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        recorderIngressStatusRead: undefined
      }))
    ).toThrow();

    expect(() =>
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        recorderIngressStatusRead: {
          readState: "loaded",
          document: null,
          readError: null
        }
      }))
    ).toThrow();

    expect(() =>
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        recorderIngressStatusRead: {
          readState: "loaded",
          httpStatus: "200",
          readError: null
        }
      }))
    ).toThrow();

    expect(() =>
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        recorderIngressStatusRead: {
          readState: "loaded",
          httpStatus: "200",
          document: null,
          readError: null
        }
      }))
    ).toThrow();

    expect(() =>
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        recorderIngressStatusRead: {
          readState: "readFailed",
          httpStatus: "failed",
          document: null,
          readError: ""
        }
      }))
    ).toThrow();

    expect(() =>
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory({
        recorderIngressStatusRead: {
          readState: "loaded",
          httpStatus: "200",
          document: {
            ...fullRecorderIngressStatusDocument(),
            redisIpVerifyFailures: undefined
          },
          readError: null
        }
      }))
    ).toThrow();

    expect(
      vitalDBRecordersSchema.parse(fullVitalRecorderHistory()).activityHistory
    ).toMatchObject({
      source: "notProvided",
      bucketCount: 0
    });
  });

  it("requires Vital Recorder history summary", () => {
    expect(() =>
      vitalDBRecordersSchema.parse({
        updatedAt: "2026-05-31T01:00:00Z",
        state: "loaded",
        recorders: [],
        beds: [],
        activityHistory: fullRecorderActivityHistory(),
        recorderIngressStatusRead: null,
        readError: null
      })
    ).toThrow();

    expect(vitalDBRecordersSchema.parse(fullVitalRecorderHistory()).summary).toEqual(
      fullVitalRecorderHistorySummary()
    );
  });

  it("requires VitalDB relationship history lists", () => {
    expect(() =>
      vitalDBRelationshipsSchema.parse({
        state: "loaded",
        assignments: [],
        readError: null
      })
    ).toThrow();

    expect(() =>
      vitalDBRelationshipsSchema.parse(fullRelationships({
        readError: undefined
      }))
    ).toThrow();
    expect(() =>
      vitalDBRelationshipsSchema.parse(fullRelationships({
        eventTotalCount: 0
      }))
    ).toThrow();
    expect(() =>
      vitalDBRelationshipsSchema.parse(fullRelationships({
        eventLimit: 0
      }))
    ).toThrow();
    expect(() =>
      vitalDBRelationshipsSchema.parse(fullRelationships({
        state: "partiallyLoaded",
        readError: null
      }))
    ).toThrow();
    expect(() =>
      vitalDBRelationshipsSchema.parse(fullRelationships({
        state: "readFailed",
        readError: ""
      }))
    ).toThrow();

    expect(vitalDBRelationshipsSchema.parse(fullRelationships())).toEqual(
      fullRelationships()
    );
  });

  it("requires log text response text", () => {
    expect(() => runtimeLogTextResponseSchema.parse({})).toThrow();
    expect(runtimeLogTextResponseSchema.parse({ text: "" })).toEqual({ text: "" });
  });

  it("requires log export result destination", () => {
    expect(() => runtimeLogExportResultSchema.parse({})).toThrow();
    expect(
      runtimeLogExportResultSchema.parse({ destination: "file:///tmp/logs.zip" })
    ).toEqual({
      destination: "file:///tmp/logs.zip"
    });
  });

  it("requires update bundle summary text", () => {
    expect(() => runtimeUpdateBundleSummaryResponseSchema.parse({})).toThrow();
    expect(runtimeUpdateBundleSummaryResponseSchema.parse({ summary: "ok" })).toEqual({
      summary: "ok"
    });
  });

  it("requires independent complete Platform and Runtime capability contracts", () => {
    expect(() =>
      platformCapabilitiesSchema.parse({ canInstallRuntime: true })
    ).toThrow();
    expect(platformCapabilitiesSchema.parse(platformCapabilities())).toEqual(
      platformCapabilities()
    );

    expect(() => runtimeCapabilitiesSchema.parse({ capabilities: [] })).toThrow();
    expect(
      runtimeCapabilitiesSchema.parse({
        schemaVersion: 1,
        capabilities: ["services:list", "lab:scenarios"]
      })
    ).toEqual({
      schemaVersion: 1,
      capabilities: ["services:list", "lab:scenarios"]
    });
  });

  it("requires explicit Recorder Vital-file attribution and source read states", () => {
    const history = {
      state: "loaded",
      vrcode: "VR_TEST",
      files: [{
        fileID: "upload-1",
        origin: "nativeRecorderUpload",
        vrcode: "VR_TEST",
        bedName: "OR-1",
        filename: "case.vital",
        sizeBytes: 2048,
        status: "indexed",
        receivedAt: "2026-07-23T01:00:00Z",
        recordingStartedAt: null,
        recordingEndedAt: null,
        uploadedAt: "2026-07-23T01:00:01Z",
        attribution: {
          state: "bedAssignmentResolved",
          assignmentID: "assignment-1",
          resolvedAt: "2026-07-23T01:00:00Z",
          readError: null
        },
        failure: null
      }],
      unattributedCount: 0,
      sources: {
        nativeUpload: { state: "loaded", readError: null },
        coldPathRecovery: { state: "loaded", readError: null }
      },
      readError: null
    };

    expect(recorderVitalFileHistorySchema.parse(history)).toEqual(history);
    expect(() => recorderVitalFileHistorySchema.parse({
      ...history,
      sources: {
        nativeUpload: { state: "loaded" },
        coldPathRecovery: { state: "loaded", readError: null }
      }
    })).toThrow();
  });

  it("requires the complete runtime settings contract", () => {
    const missingBridgedInterface: Record<string, unknown> = { ...fullSettings() };
    delete missingBridgedInterface.bridgedInterface;

    expect(() =>
      runtimeSettingsSchema.parse({
        proxyPort: 80
      })
    ).toThrow();
    expect(() =>
      runtimeSettingsSchema.parse(missingBridgedInterface)
    ).toThrow();

    expect(
      runtimeSettingsSchema.parse(fullSettings())
    ).toEqual(fullSettings());
    expect(
      runtimeSettingsSchema.parse({
        ...fullSettings(),
        bridgedInterface: null
      })
    ).toEqual({
      ...fullSettings(),
      bridgedInterface: null
    });
  });
});

function platformServices() {
  return [
    { role: "runtime-provider" as const, state: "running" as const, readError: null },
    { role: "public-proxy" as const, state: "running" as const, readError: null },
    { role: "log-sync" as const, state: "running" as const, readError: null },
    { role: "sleep-prevention" as const, state: "running" as const, readError: null },
    { role: "watchdog" as const, state: "running" as const, readError: null }
  ];
}

function fullCapabilities() {
  return {
    canInstallRuntime: true,
    canUninstallRuntime: true,
    canApplyBundle: true,
    canRollback: true,
    canRollbackRelease: true,
    canEditRuntimeProviderResources: true,
    canEditNetworkExposure: true,
    canResetAdminPassword: true,
    canOpenLocalFiles: true,
    canStreamLogs: true,
    canControlRuntimeServices: true,
    canControlGuestServices: true,
    canExportLogs: true,
    canViewReleaseMetadata: true,
    canUseLab: true
  };
}

function platformCapabilities() {
  const { canControlGuestServices: _, canUseLab: __, ...platform } = fullCapabilities();
  return platform;
}

function fullSettings() {
  return {
    readIssues: [],
    cpuCount: 2,
    memoryGiB: 4,
    diskGiB: 32,
    minimumDiskGiB: 4,
    networkMode: "shared" as const,
    bridgedInterface: "",
    proxyPort: 80,
    runtimeControlPort: 18321,
    vitalFilesDirectory: "/Users/shared/vital",
    vitalServerURL: "http://127.0.0.1:80/",
    remoteConsoleURL: "http://127.0.0.1:18321/",
    publicHost: "",
    publicPort: 80,
    recorderIngressSendDataMode: "spool_and_replay" as const,
    recorderIngressSendDataReplayBatchSize: 10,
    recorderIngressSendDataReplayMaxMiBPerSecond: 20,
    recorderIngress: fullRecorderIngressSettings(),
    containerMemoryLimitsEnabled: true,
    vitalServerContainerMemoryLimitMiB: 4096,
    recorderIngressContainerMemoryLimitMiB: 512,
    redisContainerMemoryLimitMiB: 1024,
    adminPassword: "",
    changeAdminPassword: false,
    startOnBoot: true,
    startOnBootConfigurable: true,
    autoRecoveryEnabled: true,
    preventSystemSleep: true,
    automaticBackupEnabled: true,
    backupScheduleTimes: ["03:15"],
    backupRetentionCount: 30,
    logArchiveRetentionDays: 14,
    logArchiveMaximumGiB: 1,
    redisRelay: {
      enabled: false,
      target: {
        url: "redis://redis.example:6379/0",
        username: "",
        password: "",
        clearPassword: false,
        passwordConfigured: false,
        tls: false
      },
      scope: "vital_reconstruction" as const,
      includeRecorderNetworkContext: false,
      intervalSeconds: 1,
      scanCount: 1000
    },
    restartAfterSave: true
  };
}

function fullRecorderIngressSettings() {
  return {
    sendDataMaxPendingItems: 100000,
    sendDataMaxPendingMiB: 512,
    sendDataMaxPayloadMiB: 10,
    sendDataReplayedMaxItems: 10000,
    sendDataRealtimeMaxPendingItems: 2000,
    sendDataReplayIntervalMs: 1000,
    sendDataReplayMaxAttempts: 3,
    sendDataReplayTargetTimeoutMs: 5000,
    sendDataReplayAdaptiveMinConcurrency: 1,
    sendDataReplayAdaptiveMaxConcurrency: 8,
    rawArchiveEnabled: true,
    rawArchiveMaxFileMiB: 512,
    rawArchiveMaxFiles: 24,
    rawArchiveAutoExportEnabled: true,
    rawArchiveAutoExportQuietSeconds: 300,
    rawArchiveAutoExportScanIntervalSeconds: 60,
    rawArchiveAutoExportCursorStableSeconds: 60,
    rawArchiveAutoExportRetryDelaySeconds: 60,
    rawArchiveAutoExportMaxAttempts: 3,
    rawArchiveAutoExportRequestTimeoutSeconds: 300
  };
}

function fullVitalDBObservation() {
  return {
    schemaVersion: 1,
    source: "vitaldb-observer",
    observedAt: "2026-05-31T01:00:00Z",
    ready: true,
    recorderOnlineThresholdSeconds: 120,
    recorders: [],
    beds: [],
    devices: [],
    filters: [],
    proxyConnections: [],
    anomalies: [],
    readIssues: []
  };
}

function fullVitalDBRecorderActivity() {
  return {
    windowSeconds: 300,
    messageCount: 2,
    byteCount: 1024,
    roomCount: 1,
    firstSeenAt: "2026-05-31T00:59:00Z",
    lastSeenAt: "2026-05-31T01:00:00Z",
    messagesPerSecond: 0.006,
    bytesPerSecond: 3.41,
    buckets: [
      {
        bucketStartedAt: "2026-05-31T00:59:00Z",
        bucketSeconds: 60,
        messageCount: 2,
        byteCount: 1024,
        roomCount: 1
      }
    ]
  };
}

function fullRecorderActivityHistory(overrides: Record<string, unknown> = {}) {
  return {
    source: "notProvided" as const,
    bucketCount: 0,
    earliestBucketStartedAt: null,
    latestBucketStartedAt: null,
    readError: null,
    ...overrides
  };
}

function fullVitalRecorderHistory(overrides: Record<string, unknown> = {}) {
  return {
    state: "loaded",
    updatedAt: "2026-05-31T01:00:00Z",
    recorders: [],
    beds: [],
    summary: fullVitalRecorderHistorySummary(),
    activityHistory: fullRecorderActivityHistory(),
    recorderIngressStatusRead: null,
    readError: null,
    ...overrides
  };
}

function fullVitalRecorderHistorySummary(overrides: Record<string, unknown> = {}) {
  return {
    knownRecorders: 0,
    currentRecorders: 0,
    onlineRecorders: 0,
    staleRecorders: 0,
    recorderAnomalies: 0,
    knownBeds: 0,
    onlineBeds: 0,
    staleBeds: 0,
    bedAssignments: 0,
    bedAnomalies: 0,
    ...overrides
  };
}

function fullRecorderIngressStatusDocument(overrides: Record<string, unknown> = {}) {
  return {
    activeWebSockets: 0,
    activeRecorderConnections: 0,
    recorders: [],
    httpRequests: 0,
    socketIoEventsSeen: 0,
    socketIoParseFailures: 0,
    auditWriteFailures: 0,
    auditFileWriteFailures: 0,
    auditStdoutWriteFailures: 0,
    failureLogWriteFailures: 0,
    redisIpWriteFailures: 0,
    redisIpVerifyFailures: 0,
    redisIpVerifyMismatches: 0,
    ...overrides
  };
}

function fullRelationships(overrides: Record<string, unknown> = {}) {
  return {
    state: "loaded",
    assignments: [
      {
        assignmentID: "assignment-1",
        bedID: "bed-1",
        bedName: "OR-1",
        vrcode: "VR_A",
        startedAt: "2026-05-31T00:00:00Z",
        endedAt: null,
        lastSeenAt: "2026-05-31T01:00:00Z",
        lastObservedAt: "2026-05-31T01:00:00Z",
        status: "online",
        patientConnected: true,
        observationCount: 1
      }
    ],
    events: [
      {
        eventID: "relationship-event-1",
        observedAt: "2026-05-31T01:00:00Z",
        eventType: "unlinkedBed",
        severity: "warning",
        bedID: "bed-1",
        bedName: "OR-1",
        vrcode: "VR_A",
        previousVrcode: null,
        previousBedID: null,
        message: "Bed has no linked VRecorder."
      }
    ],
    eventTotalCount: 1,
    eventLimit: 100,
    readError: null,
    ...overrides
  };
}

function fullRuntimeEvent(overrides: Record<string, unknown> = {}) {
  return {
    schemaVersion: 1,
    id: "runtime-operation-event-1",
    source: "runtime-controller",
    eventType: "operation-completed",
    timestamp: "2026-05-29T11:00:00Z",
    operationId: "runtime-settings-1",
    operationService: "runtime-settings",
    operationCommand: "apply-settings",
    operationState: "completed",
    message: "runtime-settings apply-settings completed",
    failure: null,
    ...overrides
  };
}

function fullRecorderObservabilityDetail() {
  const missing = {
    state: "missing",
    value: null,
    detail: "health observation is absent",
    observedAt: null
  };
  return {
    state: "loaded",
    vrcode: "VR_TEST",
    support: {
      state: "supported",
      source: "accepted_report",
      expectedSince: null,
      recorderVersion: null,
      producerVersion: null,
      protocolVersion: null
    },
    report: {
      state: "current",
      receivedAt: "2026-07-24T00:00:01Z",
      deviceObservedAt: "2026-07-24T00:00:00Z",
      collectionState: "complete",
      readIssueCount: 0
    },
    profile: {
      state: "associated",
      receivedAt: null,
      deviceObservedAt: null,
      deviceId: "observer-1",
      bootId: "boot-1",
      software: {},
      collection: null,
      capabilities: {}
    },
    boot: {
      state: "started",
      orderingState: "ordered",
      bootId: "boot-1",
      startedAt: "2026-07-23T00:00:00Z",
      cleanShutdownAt: null
    },
    evidenceHealth: {
      state: "healthy",
      checkedAt: "2026-07-24T00:00:00Z",
      checkCount: 3,
      detail: null
    },
    incidentState: {
      state: "reported",
      policyVersion: "recorder-incident/v1",
      bootLoopState: "none",
      repeatedUndervoltageState: "none",
      evidenceState: "healthy",
      consecutiveUnexpectedBoots: 0,
      undervoltageBootsConsidered: 0
    },
    operationalHealth: {
      state: "healthy",
      evaluatedAt: "2026-07-24T00:00:00Z",
      issueCount: 0,
      issues: []
    },
    readings: {
      temperatureCelsius: {
        state: "ok",
        value: 51.5,
        detail: null,
        observedAt: "2026-07-24T00:00:00Z"
      },
      memoryAvailableBytes: missing,
      memoryTotalBytes: missing,
      rootUsedPercent: missing,
      dataUsedPercent: missing,
      recorderActiveState: missing,
      publisherActiveState: missing,
      publisherBufferBytes: missing,
      publisherBufferLimitBytes: missing,
      networkInterfaces: []
    },
    readIssues: [],
    readError: null
  };
}

function recorderWithoutObserverDetail() {
  const detail = fullRecorderObservabilityDetail();
  return {
    ...detail,
    state: "notReported",
    support: {
      ...detail.support,
      state: "unknown",
      source: null
    },
    report: {
      ...detail.report,
      state: "notEvaluated",
      receivedAt: null,
      deviceObservedAt: null,
      collectionState: null
    },
    profile: {
      ...detail.profile,
      state: "missing",
      deviceId: null,
      bootId: null
    },
    boot: {
      state: "notReported",
      orderingState: "unknown",
      bootId: null,
      startedAt: null,
      cleanShutdownAt: null
    },
    evidenceHealth: {
      state: "notReported",
      checkedAt: null,
      checkCount: 0,
      detail: null
    },
    incidentState: {
      state: "notReported",
      policyVersion: null,
      bootLoopState: null,
      repeatedUndervoltageState: null,
      evidenceState: null,
      consecutiveUnexpectedBoots: null,
      undervoltageBootsConsidered: null
    },
    operationalHealth: {
      state: "unknown",
      evaluatedAt: null,
      issueCount: 0,
      issues: []
    }
  };
}

function fullVitalRecorderRecord(overrides: Record<string, unknown> = {}) {
  return {
    vrcode: "VR_TEST",
    status: "online",
    visibility: "visible",
    lastIP: null,
    version: null,
    bedID: null,
    bedName: null,
    patientConnected: null,
    firstSeenAt: null,
    lastSeenAt: null,
    observationCount: 1,
    duplicateObservationCount: 0,
    currentAnomalyCount: 0,
    latestAnomalyKind: null,
    latestAnomalySeverity: null,
    latestAnomalyMessage: null,
    latestAnomalyObservedAt: null,
    presentInLatestObservation: true,
    activityTimeline: null,
    redisIPSync: null,
    ...overrides
  };
}

function fullVitalBedRecord(overrides: Record<string, unknown> = {}) {
  return {
    bedID: "bed-1",
    name: null,
    vrcode: null,
    linkedRecorderStatus: null,
    linkedRecorderIP: null,
    linkedRecorderLastSeenAt: null,
    status: "online",
    visibility: "visible",
    patientConnected: null,
    firstSeenAt: null,
    lastSeenAt: null,
    observationCount: 1,
    duplicateObservationCount: 0,
    currentAnomalyCount: 0,
    latestAnomalyKind: null,
    latestAnomalySeverity: null,
    latestAnomalyMessage: null,
    latestAnomalyObservedAt: null,
    ...overrides
  };
}
