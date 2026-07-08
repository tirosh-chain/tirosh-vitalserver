import { describe, expect, it } from "vitest";

import {
  runtimeCommandResponseSchema,
  runtimeCapabilitiesSchema,
  runtimeEventHistorySchema,
  runtimeLogExportResultSchema,
  runtimeLogTextResponseSchema,
  runtimeOperationStateSchema,
  runtimeOverviewSchema,
  runtimeStatusSchema,
  runtimeSettingsSchema,
  runtimeUpdateBundleSummaryResponseSchema,
  vitalDBObservationSchema,
  vitalDBRecordersSchema,
  vitalDBRelationshipsSchema
} from "./runtimeControlSchemas";

describe("runtime control contract schemas", () => {
  it("accepts a command response from Runtime Control API", () => {
    expect(
      runtimeCommandResponseSchema.parse({
        result: {
          exitCode: 0,
          stdout: "ok",
          stderr: ""
        }
      })
    ).toEqual({
      result: {
        exitCode: 0,
        stdout: "ok",
        stderr: ""
      }
    });
  });

  it("preserves operation state read meanings", () => {
    expect(
      runtimeOperationStateSchema.parse({
        activeOperation: "apply-bundle",
        runtimeStatusUpdatedAt: "2026-07-08T00:00:00Z",
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
      runtimeOperationStateSchema.parse({
        activeOperation: null,
        runtimeStatusUpdatedAt: null,
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
      runtimeOperationStateSchema.parse({
        install: {
          state: "unavailable"
        },
        lease: {
          state: "unavailable"
        }
      })
    ).toThrow();
  });

  it("accepts unknown runtime state values in overview responses", () => {
    expect(
      runtimeOverviewSchema.parse(
        fullRuntimeOverview({
          status: {
            runtimeState: "surprising-from-helper"
          }
        })
      ).status.runtimeState
    ).toBe("surprising-from-helper");
  });

  it("accepts Remote Console status fields in overview responses", () => {
    expect(
      runtimeOverviewSchema.parse(
        fullRuntimeOverview({
          status: {
            runtimeControlHTTP: "200",
            runtimeControlStartedAt: "2026-05-26T04:30:00Z"
          }
        })
      ).status
    ).toMatchObject({
      runtimeControlHTTP: "200",
      runtimeControlStartedAt: "2026-05-26T04:30:00Z"
    });
  });

  it("accepts overview status responses without container observation", () => {
    expect(
      runtimeOverviewSchema.parse(
        fullRuntimeOverview({
          status: {
            runtimeState: "healthy",
            statusMessage: "loaded"
          }
        })
      ).status
    ).toMatchObject({
      runtimeState: "healthy",
      statusMessage: "loaded"
    });
  });

  it("requires explicit Guest service arrays when RuntimeStatus says Guest services are loaded", () => {
    expect(
      runtimeStatusSchema.parse({
        runtimeState: "healthy",
        guestServicesReadState: "loaded",
        guestServiceStatuses: [],
        guestServiceResources: [],
        guestServiceResourceReadIssues: []
      })
    ).toMatchObject({
      guestServicesReadState: "loaded",
      guestServiceStatuses: [],
      guestServiceResources: [],
      guestServiceResourceReadIssues: []
    });

    expect(() =>
      runtimeStatusSchema.parse({
        runtimeState: "healthy",
        guestServicesReadState: "loaded",
        guestServiceStatuses: []
      })
    ).toThrow(/guestServiceResources/);
  });

  it("requires an explicit read error when RuntimeStatus says Guest service reads failed", () => {
    expect(() =>
      runtimeStatusSchema.parse({
        runtimeState: "degraded",
        guestServicesReadState: "failed",
        guestServicesReadError: ""
      })
    ).toThrow(/guestServicesReadError/);

    expect(
      runtimeStatusSchema.parse({
        runtimeState: "degraded",
        guestServicesReadState: "failed",
        guestServicesReadError: "guest control api timed out"
      })
    ).toMatchObject({
      guestServicesReadState: "failed",
      guestServicesReadError: "guest control api timed out"
    });
  });

  it("accepts unknown VM states in overview responses", () => {
    expect(
      runtimeOverviewSchema.parse(
        fullRuntimeOverview({
          status: {
            vmState: "hibernating"
          }
        })
      ).status.vmState
    ).toBe("hibernating");
  });

  it("preserves VitalDB observation snapshot read-state semantics", () => {
    expect(() =>
      runtimeOverviewSchema.parse(
        fullRuntimeOverview({
          vitalDBObservationSnapshot: {
            state: "unavailable"
          }
        })
      )
    ).toThrow();

    expect(() =>
      runtimeOverviewSchema.parse(
        fullRuntimeOverview({
          vitalDBObservationSnapshot: {
            state: "loaded",
            observation: null,
            readError: null
          }
        })
      )
    ).toThrow();

    expect(() =>
      runtimeOverviewSchema.parse(
        fullRuntimeOverview({
          vitalDBObservationSnapshot: {
            state: "failed",
            observation: null,
            readError: ""
          }
        })
      )
    ).toThrow();

    expect(
      runtimeOverviewSchema.parse(
        fullRuntimeOverview({
          vitalDBObservationSnapshot: {
            state: "loaded",
            observation: fullVitalDBObservation(),
            readError: null
          }
        })
      ).vitalDBObservationSnapshot
    ).toMatchObject({
      state: "loaded",
      observation: {
        source: "vitaldb-observer"
      }
    });
  });

  it("requires explicit RuntimeOverview nullable fields and conditions", () => {
    const { vitalDBObservation: _observation, conditions: _conditions, ...missingOverviewFields } =
      fullRuntimeOverviewShape();

    expect(() => runtimeOverviewSchema.parse(missingOverviewFields)).toThrow();
    expect(() =>
      runtimeOverviewSchema.parse(
        fullRuntimeOverview({
          conditions: [
            {
              type: "VitalDBObservationReady",
              status: "Unknown",
              reason: "Unavailable"
            }
          ]
        })
      )
    ).toThrow();
  });

  it("requires explicit Vital Recorder summary source and observed metrics", () => {
    expect(() =>
      runtimeOverviewSchema.parse(
        fullRuntimeOverview({
          vitalRecorder: {
            knownRecorders: 1
          }
        })
      )
    ).toThrow();

    expect(() =>
      runtimeOverviewSchema.parse(
        fullRuntimeOverview({
          vitalRecorder: {
            source: "vitalDBObservation",
            knownRecorders: 1,
            onlineRecorders: 1,
            staleRecorders: 0,
            knownBeds: 1,
            observedAt: "2026-05-31T01:00:00Z",
            latestRecorder: null
          }
        })
      )
    ).toThrow();

    expect(() =>
      runtimeOverviewSchema.parse(
        fullRuntimeOverview({
          vitalRecorder: {
            source: "vitalDBObservation",
            knownRecorders: 1,
            onlineRecorders: 1,
            staleRecorders: 0,
            knownBeds: 1,
            recorderAnomalies: 0,
            observedAt: "2026-05-31T01:00:00Z",
            latestRecorder: {
              ip: "10.0.0.2",
              lastSeenAt: "2026-05-31T01:00:00Z"
            }
          }
        })
      )
    ).toThrow();

    expect(
      runtimeOverviewSchema.parse(
        fullRuntimeOverview({
          vitalRecorder: {
            source: "vitalDBObservation",
            knownRecorders: 1,
            onlineRecorders: 1,
            staleRecorders: 0,
            knownBeds: 1,
            recorderAnomalies: 0,
            observedAt: "2026-05-31T01:00:00Z",
            latestRecorder: {
              vrcode: "VR_TEST",
              ip: "10.0.0.2",
              lastSeenAt: "2026-05-31T01:00:00Z",
              source: "vitalDBObservation"
            }
          }
        })
      ).vitalRecorder
    ).toMatchObject({
      source: "vitalDBObservation",
      knownRecorders: 1,
      recorderAnomalies: 0,
      latestRecorder: {
        vrcode: "VR_TEST"
      }
    });
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

  it("accepts recovery-suppressed runtime events from the Helper", () => {
    expect(
      runtimeEventHistorySchema.parse({
        events: [
          fullRuntimeEvent({
            eventType: "recovery-suppressed",
            timestamp: "2026-05-29T11:00:00Z",
            status: "critical",
            message: "watchdog recovery suppressed"
          })
        ],
        nextCursor: null,
        matchingCount: 1
      }).events?.[0]?.eventType
    ).toBe("recovery-suppressed");
  });

  it("accepts recovery-deferred runtime events from the Helper", () => {
    expect(
      runtimeEventHistorySchema.parse({
        events: [
          fullRuntimeEvent({
            eventType: "recovery-deferred",
            timestamp: "2026-06-01T01:43:20Z",
            status: "degraded",
            message: "watchdog recovery deferred"
          })
        ],
        nextCursor: null,
        matchingCount: 1
      }).events?.[0]?.eventType
    ).toBe("recovery-deferred");
  });

  it("accepts unknown runtime event types from the Helper", () => {
    expect(
      runtimeEventHistorySchema.parse({
        events: [
          fullRuntimeEvent({
            eventType: "runtime-checkpoint-progressed",
            timestamp: "2026-06-01T01:43:20Z",
            status: "critical",
            message: "future event introduced"
          })
        ],
        nextCursor: null,
        matchingCount: 1
      }).events?.[0]?.eventType
    ).toBe("runtime-checkpoint-progressed");
  });

  it("requires runtime event identity and diagnostic owner fields", () => {
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
      id: "event-1",
      source: "host-runtime",
      eventType: "status-changed",
      timestamp: "2026-05-29T11:00:00Z"
    });
  });

  it("requires runtime event history events", () => {
    expect(() =>
      runtimeEventHistorySchema.parse({
        nextCursor: null,
        matchingCount: 0
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

  it("requires the complete runtime capability contract", () => {
    expect(() =>
      runtimeCapabilitiesSchema.parse({
        canUseLab: true
      })
    ).toThrow();

    expect(
      runtimeCapabilitiesSchema.parse(fullCapabilities())
    ).toEqual(fullCapabilities());
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

function fullCapabilities() {
  return {
    canInstallRuntime: true,
    canUninstallRuntime: true,
    canApplyBundle: true,
    canRollback: true,
    canEditVMResources: true,
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

function fullRuntimeOverview(overrides: Record<string, unknown> = {}) {
  return {
    ...fullRuntimeOverviewShape(),
    ...overrides
  };
}

function fullRuntimeOverviewShape() {
  return {
    status: {
      runtimeState: "healthy" as const
    },
    settings: fullSettings(),
    release: {},
    install: {},
    vitalDBObservation: null,
    vitalDBObservationSnapshot: {
      state: "unavailable" as const,
      observation: null,
      readError: null
    },
    vitalRecorder: {
      source: "unavailable" as const,
      observedAt: null,
      latestRecorder: null
    },
    conditions: [
      {
        type: "VitalDBObservationReady",
        status: "Unknown" as const,
        reason: "Unavailable",
        message: null,
        observedAt: null
      }
    ]
  };
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
    readError: null,
    ...overrides
  };
}

function fullRuntimeEvent(overrides: Record<string, unknown> = {}) {
  return {
    schemaVersion: 1,
    id: "event-1",
    source: "host-runtime",
    eventType: "status-changed",
    timestamp: "2026-05-29T11:00:00Z",
    product: "VitalServer",
    message: "status changed",
    runtimeVersion: "1.2.3",
    failureReasons: [],
    ...overrides
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
