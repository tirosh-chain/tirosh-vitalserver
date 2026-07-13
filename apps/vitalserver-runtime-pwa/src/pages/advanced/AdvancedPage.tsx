import { useEffect, useState } from "react";

import {
  useApplyRuntimeProductSettings,
  useCreateRedisBackup,
  useCreateRuntimeDataBackup,
  useRuntimeStack,
  useRuntimeServiceResources,
  useHostBackups,
  useRedisBackups,
  useRepairDatastore,
  useRestartRuntimeProvider,
  useRuntimeDataBackups,
  useControlCapabilities,
  usePlatformOperationState,
  useRuntimeProductSettings,
  usePlatformState,
  useRestartGuestService,
  useStartGuestService,
  useStopGuestService,
  useRollbackBackup,
  useRestoreRuntimeDataBackup
} from "@/console/hooks";
import {
  canApplyRuntimeProductSettings,
  canRepairRuntimeDatastore,
  canRestartRuntimeProvider
} from "@/domain/runtime-control/capabilities/runtimeCapabilities";
import type {
  PlatformState,
  RuntimeProductSettings,
  PlatformOperationState,
  RuntimeGuestControlStackStatus,
  RuntimeGuestControlServiceOperation,
  RuntimeGuestServiceResource,
  RuntimeBackup,
  RuntimeCommandResponse,
  RuntimeProviderCommandResponse
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import { formatBytes } from "@/domain/runtime-control/formatting/bytes";
import { formatHTTPStatus } from "@/domain/runtime-control/formatting/http";
import { NOT_REPORTED } from "@/domain/runtime-control/formatting/reported";
import {
  formatRuntimeState,
  runtimeStateTone
} from "@/domain/runtime-control/formatting/runtimeState";
import { ConfirmButton } from "@/components/ConfirmButton";
import { CommandResult } from "@/components/CommandResult";
import { DataTable } from "@/components/DataTable";
import { ErrorState } from "@/components/ErrorState";
import { KeyValueRows } from "@/components/KeyValueRows";
import { Panel } from "@/components/Panel";
import { StatusBadge } from "@/components/StatusBadge";

type RuntimeOverviewPresentation = {
  status?: PlatformState;
};

type OperationResultSource =
  | "apply-runtime-settings"
  | "rollback-backup"
  | "create-runtime-data-backup"
  | "restore-runtime-data-backup"
  | "create-redis-backup"
  | "restart-runtime-provider"
  | "repair-datastore"
  | "start-guest-service"
  | "stop-guest-service"
  | "restart-guest-service";

type OperationResult =
  | {
      kind: "command";
      result: RuntimeCommandResponse | undefined;
      error: Error | null;
    }
  | {
      kind: "provider";
      result: RuntimeProviderCommandResponse | undefined;
      error: Error | null;
    }
  | {
      kind: "guest";
      result: RuntimeGuestControlServiceOperation | undefined;
      error: Error | null;
    };

function commandOperationResult(
  result: RuntimeCommandResponse | undefined,
  error: Error | null
): OperationResult {
  return { kind: "command", result, error };
}

function providerOperationResult(
  result: RuntimeProviderCommandResponse | undefined,
  error: Error | null
): OperationResult {
  return { kind: "provider", result, error };
}

function guestOperationResult(
  result: RuntimeGuestControlServiceOperation | undefined,
  error: Error | null
): OperationResult {
  return { kind: "guest", result, error };
}

function platformServiceRunning(
  state: PlatformState | undefined,
  role: PlatformState["services"][number]["role"]
): boolean | undefined {
  const service = state?.services.find((candidate) => candidate.role === role);
  return service ? service.state === "running" : undefined;
}

export function AdvancedPage() {
  const platformState = usePlatformState();
  const operationState = usePlatformOperationState();
  const capabilities = useControlCapabilities();
  const canManageBackups = capabilities.data?.canRollback === true;
  const unavailableBackupMessage = capabilities.isPending
    ? "Loading backup capability..."
    : capabilities.isError
      ? "Backup capability could not be read."
      : "Backup and rollback operations are not supported by this Runtime Control API.";
  const unavailableRuntimeProviderControlMessage = capabilities.isPending
    ? "Loading Runtime Provider control capability..."
    : capabilities.isError
      ? "Runtime Provider control capability could not be read."
      : "Runtime Provider control is not supported by this Platform Agent.";
  const unavailableDatastoreRepairMessage = capabilities.isPending
    ? "Loading data store repair capability..."
    : capabilities.isError
      ? "Data store repair capability could not be read."
      : "Data store repair is not supported by this Runtime Controller.";
  const runtimeStack = useRuntimeStack();
  const runtimeServiceResources = useRuntimeServiceResources(
    runtimeStack.data?.services.map((service) => service.service) ?? []
  );
  const hostBackups = useHostBackups(canManageBackups);
  const redisBackups = useRedisBackups(canManageBackups);
  const runtimeDataBackups = useRuntimeDataBackups(canManageBackups);
  const runtimeSettingsRead = useRuntimeProductSettings();
  const runtimeSettings =
    runtimeSettingsRead.data?.state === "loaded"
      ? runtimeSettingsRead.data.settings ?? undefined
      : undefined;
  const applySettings = useApplyRuntimeProductSettings();
  const rollbackBackup = useRollbackBackup();
  const createRedisBackup = useCreateRedisBackup();
  const createRuntimeDataBackup = useCreateRuntimeDataBackup();
  const restoreRuntimeDataBackup = useRestoreRuntimeDataBackup();
  const startGuestService = useStartGuestService();
  const stopGuestService = useStopGuestService();
  const restartGuestService = useRestartGuestService();
  const restartRuntimeProvider = useRestartRuntimeProvider();
  const repairDatastore = useRepairDatastore();

  const [selectedHostBackup, setSelectedHostBackup] =
    useState<RuntimeBackup | null>(null);
  const [selectedRedisBackup, setSelectedRedisBackup] =
    useState<RuntimeBackup | null>(null);
  const [selectedRuntimeDataBackup, setSelectedRuntimeDataBackup] =
    useState<RuntimeBackup | null>(null);
  const [operationResultSource, setOperationResultSource] =
    useState<OperationResultSource | null>(null);
  const [vitalServerURL, setVitalServerURL] = useState("");
  const [remoteConsoleURL, setRemoteConsoleURL] = useState("");

  useEffect(() => {
    if (!runtimeSettings) {
      setVitalServerURL("");
      setRemoteConsoleURL("");
      return;
    }
    setVitalServerURL(runtimeSettings.vitalServerURL);
    setRemoteConsoleURL(runtimeSettings.remoteConsoleURL);
  }, [runtimeSettings]);

  const canRollback = canManageBackups;
  const canRestartProvider = canRestartRuntimeProvider(capabilities.data);
  const canRepairDatastore = canRepairRuntimeDatastore(capabilities.data);
  const canApplySettings = canApplyRuntimeProductSettings(capabilities.data);
  const canEditNetworkExposure =
    capabilities.data?.canEditNetworkExposure === true;
  const canControlGuestServices =
    capabilities.data?.canControlGuestServices === true;
  const operationResults: Record<OperationResultSource, OperationResult> = {
    "apply-runtime-settings": guestOperationResult(
      applySettings.data,
      applySettings.error
    ),
    "rollback-backup": commandOperationResult(
      rollbackBackup.data,
      rollbackBackup.error
    ),
    "create-runtime-data-backup": commandOperationResult(
      createRuntimeDataBackup.data,
      createRuntimeDataBackup.error
    ),
    "restore-runtime-data-backup": commandOperationResult(
      restoreRuntimeDataBackup.data,
      restoreRuntimeDataBackup.error
    ),
    "create-redis-backup": commandOperationResult(
      createRedisBackup.data,
      createRedisBackup.error
    ),
    "restart-runtime-provider": providerOperationResult(
      restartRuntimeProvider.data,
      restartRuntimeProvider.error
    ),
    "repair-datastore": guestOperationResult(
      repairDatastore.data,
      repairDatastore.error
    ),
    "start-guest-service": guestOperationResult(
      startGuestService.data,
      startGuestService.error
    ),
    "stop-guest-service": guestOperationResult(
      stopGuestService.data,
      stopGuestService.error
    ),
    "restart-guest-service": guestOperationResult(
      restartGuestService.data,
      restartGuestService.error
    )
  };
  const operationResult = operationResultSource
    ? operationResults[operationResultSource]
    : commandOperationResult(undefined, null);
  const platformOverview =
    platformState.data
      ? { status: platformState.data }
      : undefined;

  const networkSettings =
    runtimeSettings &&
    updatedRuntimeSettings(runtimeSettings, {
      vitalServerURL,
      remoteConsoleURL
    });
  const networkValidation = networkSettings
    ? validateAdvancedNetworkSettings(networkSettings)
    : { valid: false, errors: ["Runtime settings are not loaded."] };
  const canApplyNetworkSettings =
    Boolean(networkSettings) &&
    canApplySettings &&
    networkValidation.valid &&
    !applySettings.isPending;

  const applyRuntimeSettings = (
    settings: RuntimeProductSettings | false | undefined
  ) => {
    if (!settings) {
      return;
    }
    setOperationResultSource("apply-runtime-settings");
    applySettings.mutate({ settings });
  };

  return (
    <div className="page-stack">
      <Panel title="Diagnostics">
          <Diagnostics
            overview={platformOverview}
            operationState={operationState.data}
            operationStateError={operationState.error}
          />
        {platformState.isError ? (
          <ErrorState title="Failed to read platform state" error={platformState.error} />
        ) : null}
      </Panel>

      <Panel title="Runtime provider health">
        <VMHealth overview={platformOverview} />
      </Panel>

      <Panel title="Platform services">
        <PlatformServices state={platformState.data} />
      </Panel>

      <Panel title="Runtime product services">
        <GuestServiceControls
          stackStatus={runtimeStack.data}
          resourceReads={runtimeServiceResources}
          stackStatusError={runtimeStack.isError ? runtimeStack.error : null}
          disabled={!canControlGuestServices}
          isPending={
            startGuestService.isPending ||
            stopGuestService.isPending ||
            restartGuestService.isPending
          }
          onStart={(service) => {
            setOperationResultSource("start-guest-service");
            startGuestService.mutate(service);
          }}
          onStop={(service) => {
            setOperationResultSource("stop-guest-service");
            stopGuestService.mutate(service);
          }}
          onRestart={(service) => {
            setOperationResultSource("restart-guest-service");
            restartGuestService.mutate(service);
          }}
        />
      </Panel>

      <Panel title="Access endpoints">
        <KeyValueRows
          rows={[
            {
              label: "Public proxy",
              value: formatHTTPStatus(platformState.data?.publicProxyHTTP)
            }
          ]}
        />
        <APICatalog platformState={platformState.data} />
      </Panel>

      <Panel title="Recovery operations">
        <p className="muted">
          Use these actions when the runtime is installed but unhealthy after
          update, rollback, or unexpected shutdown.
        </p>
        {capabilities.isError ? (
          <ErrorState
            title="Failed to read control capabilities"
            error={capabilities.error}
          />
        ) : null}
        {!capabilities.isPending && !capabilities.isError && !canManageBackups ? (
          <p className="muted">
            Backup and rollback operations are not supported by this Runtime
            Control API.
          </p>
        ) : null}

        <div className="subsection">
          <h3>Update recovery</h3>
          <BackupTable
            rows={canManageBackups ? hostBackups.data ?? [] : []}
            selected={selectedHostBackup}
            onSelect={setSelectedHostBackup}
            emptyText={
              canManageBackups
                ? "No rollback backups are available."
                : unavailableBackupMessage
            }
          />
          <div className="action-row">
            <ConfirmButton
              confirmMessage="Rollback to the selected managed backup? Runtime services may restart."
              disabled={!selectedHostBackup || rollbackBackup.isPending || !canRollback}
              onClick={() => {
                if (!selectedHostBackup?.path) {
                  return;
                }
                setOperationResultSource("rollback-backup");
                rollbackBackup.mutate(selectedHostBackup.path);
              }}
            >
              Rollback
            </ConfirmButton>
          </div>
          {hostBackups.isError ? (
            <ErrorState
              title="Failed to read rollback backups"
              error={hostBackups.error}
            />
          ) : null}
        </div>

        <div className="subsection">
          <h3>VitalServer backup</h3>
          <p className="muted">
            Create or restore one VitalServer backup that includes settings,
            runtime state, observability history, and Redis data.
          </p>
          <BackupTable
            rows={canManageBackups ? runtimeDataBackups.data ?? [] : []}
            selected={selectedRuntimeDataBackup}
            onSelect={setSelectedRuntimeDataBackup}
            emptyText={
              canManageBackups
                ? "No VitalServer backups are available."
                : unavailableBackupMessage
            }
          />
          <div className="action-row">
            <ConfirmButton
              confirmMessage="Create a VitalServer backup now?"
              disabled={
                createRuntimeDataBackup.isPending ||
                !canManageBackups
              }
              onClick={() => {
                setOperationResultSource("create-runtime-data-backup");
                createRuntimeDataBackup.mutate("");
              }}
            >
              Create Backup
            </ConfirmButton>
            <ConfirmButton
              confirmMessage="Restore the selected VitalServer backup? This replaces current runtime data, settings, observability history, and Redis data, and may restart runtime services."
              disabled={
                !selectedRuntimeDataBackup?.path ||
                restoreRuntimeDataBackup.isPending ||
                !canManageBackups
              }
              onClick={() => {
                if (!selectedRuntimeDataBackup?.path) {
                  return;
                }
                setOperationResultSource("restore-runtime-data-backup");
                restoreRuntimeDataBackup.mutate(selectedRuntimeDataBackup.path);
              }}
            >
              Restore Backup
            </ConfirmButton>
          </div>
          {runtimeDataBackups.isError ? (
            <ErrorState
              title="Failed to read VitalServer backups"
              error={runtimeDataBackups.error}
            />
          ) : null}
        </div>

        <div className="subsection">
          <h3>Runtime Provider</h3>
          <p className="muted">
            Restart the Platform-owned Runtime Provider. Guest readiness remains
            reported by the Runtime Controller.
          </p>
          <div className="action-row">
            <ConfirmButton
              confirmMessage="Restart the Runtime Provider?"
              disabled={
                restartRuntimeProvider.isPending || !canRestartProvider
              }
              onClick={() => {
                setOperationResultSource("restart-runtime-provider");
                restartRuntimeProvider.mutate();
              }}
            >
              Restart Runtime Provider
            </ConfirmButton>
          </div>
          {!canRestartProvider ? (
            <p className="muted">{unavailableRuntimeProviderControlMessage}</p>
          ) : null}

          <div className="subsection">
            <h3>Guest data store repair</h3>
            <p className="muted">
              This operation is owned by the Runtime Controller and can create a
              persisted Guest operation result.
            </p>
            <div className="action-row">
              {canRepairDatastore ? (
                <ConfirmButton
                  confirmMessage="Repair the Redis data store? Redis may create a backup and truncate a corrupted AOF tail."
                  disabled={repairDatastore.isPending}
                  onClick={() => {
                    setOperationResultSource("repair-datastore");
                    repairDatastore.mutate();
                  }}
                >
                  Repair Data Store
                </ConfirmButton>
              ) : (
                <p className="muted">
                  {unavailableDatastoreRepairMessage}
                </p>
              )}
            </div>
          </div>

          <div className="subsection">
            <h3>Platform-specific maintenance</h3>
            <p className="muted">
              Host proxy and VM storage repair require platform-specific
              maintenance workflows and are not available in the common console.
            </p>
          </div>

          <div className="subsection">
            <h3>Redis-only recovery</h3>
            <p className="muted">
              Advanced repair action for Redis data only. Use a VitalServer
              backup for normal backup and restore.
            </p>
            <BackupTable
              rows={canManageBackups ? redisBackups.data ?? [] : []}
              selected={selectedRedisBackup}
              onSelect={setSelectedRedisBackup}
              emptyText={
                canManageBackups
                  ? "No Redis backups are available."
                  : unavailableBackupMessage
              }
            />
            <div className="action-row">
              <ConfirmButton
                confirmMessage="Create a recoverable Redis backup now?"
                disabled={
                  createRedisBackup.isPending || !canManageBackups
                }
                onClick={() => {
                  setOperationResultSource("create-redis-backup");
                  createRedisBackup.mutate("");
                }}
              >
                Create Redis-only Backup
              </ConfirmButton>
              <ConfirmButton
                confirmMessage="Restore the selected Redis backup? Current Redis data will be replaced."
                disabled
                onClick={() => undefined}
              >
                Restore Redis-only Backup
              </ConfirmButton>
              <span className="muted">Planned</span>
            </div>
            {redisBackups.isError ? (
              <ErrorState
                title="Failed to read Redis backups"
                error={redisBackups.error}
              />
            ) : null}
          </div>
        </div>
      </Panel>

      <Panel title="Advanced network">
        <p className="muted">
          These settings change how clients discover VitalServer and Remote
          Console beyond this Mac&apos;s direct host proxy URLs.
        </p>
        <div className="settings-grid">
          <label>
            VitalServer URL
            <input
              type="url"
              value={vitalServerURL}
              disabled={!canEditNetworkExposure}
              onChange={(event) => setVitalServerURL(event.target.value)}
            />
          </label>
          <label>
            Remote Console URL
            <input
              type="url"
              value={remoteConsoleURL}
              disabled={!canEditNetworkExposure}
              onChange={(event) => setRemoteConsoleURL(event.target.value)}
            />
          </label>
        </div>
        <p className="muted">
          URL that VitalServer and Remote Console advertise to clients.
        </p>
        <div className="subsection">
          <h3>Planned network features</h3>
          <KeyValueRows
            rows={[
              { label: "mDNS name", value: "Planned" },
              { label: "Bridged networking", value: "Planned" },
              { label: "HTTPS termination", value: "Planned" },
              { label: "Static VM address", value: "Not available" }
            ]}
          />
        </div>
        {networkValidation.errors.length ? (
          <ValidationErrors title="Network settings need attention" errors={networkValidation.errors} />
        ) : null}
        {runtimeSettingsRead.isError ? (
          <ErrorState title="Failed to read settings" error={runtimeSettingsRead.error} />
        ) : null}
        <div className="action-row">
          <ConfirmButton
            confirmMessage="Apply runtime settings? This may update launchd services, rewrite runtime configuration, and restart the VM runtime only when a changed setting requires it and activation after save is enabled."
            disabled={!canApplyNetworkSettings}
            onClick={() => applyRuntimeSettings(networkSettings)}
          >
            Apply Settings
          </ConfirmButton>
        </div>
      </Panel>

      <Panel title="Operation result">
        {operationResult.kind === "provider" ? (
          <RuntimeProviderCommandResult
            command={operationResult.result}
            error={operationResult.error}
          />
        ) : operationResult.kind === "guest" ? (
          <GuestServiceOperationResult
            operation={operationResult.result}
            error={operationResult.error}
          />
        ) : (
          <CommandResult
            result={operationResult.result}
            error={operationResult.error}
          />
        )}
      </Panel>
    </div>
  );
}

function Diagnostics({
  overview,
  operationState,
  operationStateError
}: {
  overview: RuntimeOverviewPresentation | undefined;
  operationState: PlatformOperationState | undefined;
  operationStateError: Error | null;
}) {
  const status = overview?.status;
  return (
    <KeyValueRows
      rows={[
        {
          label: "Runtime state",
          value: (
            <StatusBadge tone={runtimeStateTone(status?.platformHealth)}>
              {formatRuntimeState(status?.platformHealth)}
            </StatusBadge>
          )
        },
        {
          label: "Operation",
          value: operationState?.activeOperation ?? NOT_REPORTED,
          detail: operationStateDetail(operationState, operationStateError)
        },
        { label: "Installed version", value: status?.installedVersion ?? "Unknown" },
        { label: "Runtime endpoint", value: status?.runtimeEndpoint ?? "Waiting" },
        {
          label: "Failure reasons",
          value: status?.healthIssues?.length
            ? status.healthIssues.join(", ")
            : "-"
        }
      ]}
    />
  );
}

function operationStateDetail(
  operationState: PlatformOperationState | undefined,
  operationStateError: Error | null
) {
  if (operationStateError) {
    return `Operation state read failed: ${operationStateError.message}`;
  }
  if (!operationState) {
    return "Operation state not reported";
  }

  const details = [
    `install: ${operationState.install.state}`,
    `lease: ${operationState.lease.state}`
  ];
  if (operationState.install.readError) {
    details.push(`install readError: ${operationState.install.readError}`);
  }
  if (operationState.lease.readError) {
    details.push(`lease readError: ${operationState.lease.readError}`);
  }
  if (operationState.lease.staleReason) {
    details.push(`lease staleReason: ${operationState.lease.staleReason}`);
  }
  return details.join(", ");
}

function VMHealth({ overview }: { overview: RuntimeOverviewPresentation | undefined }) {
  const status = overview?.status;
  const runtimeInstallationState = status?.runtimeInstallationState;
  const vmServiceLoaded = platformServiceRunning(status, "runtime-provider");
  const runtimeEndpoint = status?.runtimeEndpoint?.trim();
  const providerErrors = status?.runtimeProviderErrors?.filter((error) => error.trim().length > 0);

  return (
    <KeyValueRows
      rows={[
        {
          label: "Runtime installation",
          value: (
            <StatusBadge tone={runtimeInstallationTone(runtimeInstallationState)}>
              {formatRuntimeInstallationState(runtimeInstallationState)}
            </StatusBadge>
          )
        },
        {
          label: "Runtime provider state",
          value: (
            <StatusBadge tone={vmStateTone(status?.runtimeProviderState)}>
              {formatVMState(status?.runtimeProviderState)}
            </StatusBadge>
          )
        },
        {
          label: "Runtime provider service",
          value: (
            <StatusBadge tone={booleanTone(vmServiceLoaded)}>
              {formatServiceLoaded(vmServiceLoaded)}
            </StatusBadge>
          )
        },
        {
          label: "Runtime endpoint",
          value: (
            <StatusBadge tone={runtimeEndpoint ? "success" : "warning"}>
              {runtimeEndpoint || NOT_REPORTED}
            </StatusBadge>
          )
        },
        ...(providerErrors?.length
          ? [
              {
                label: "Runtime provider errors",
                value: (
                  <StatusBadge tone="warning">
                    {providerErrors.join(", ")}
                  </StatusBadge>
                )
              }
            ]
          : [])
      ]}
    />
  );
}

function PlatformServices({ state }: { state: PlatformState | undefined }) {
  if (!state) {
    return <p className="muted">Platform service state has not been read.</p>;
  }

  return (
    <DataTable
      rows={state.services}
      getRowKey={(service) => service.role}
      columns={[
        {
          key: "role",
          header: "Role",
          render: (service) => platformServiceLabel(service.role)
        },
        {
          key: "state",
          header: "State",
          render: (service) => (
            <StatusBadge tone={platformServiceTone(service.state)}>
              {service.state}
            </StatusBadge>
          )
        },
        {
          key: "readError",
          header: "Read error",
          render: (service) => service.readError ?? "-"
        }
      ]}
      emptyText="No Platform service state was reported."
    />
  );
}

function platformServiceLabel(
  role: PlatformState["services"][number]["role"]
): string {
  const labels: Record<typeof role, string> = {
    "runtime-provider": "Runtime provider",
    "public-proxy": "Public proxy",
    "log-sync": "Runtime log sync",
    "sleep-prevention": "Sleep prevention",
    watchdog: "Watchdog"
  };
  return labels[role];
}

function platformServiceTone(
  state: PlatformState["services"][number]["state"]
): "success" | "warning" | "danger" | "neutral" {
  if (state === "running") {
    return "success";
  }
  if (state === "stopped" || state === "not-installed" || state === "unavailable") {
    return "neutral";
  }
  if (state === "failed" || state === "permission-denied" || state === "read-failed") {
    return "danger";
  }
  return "warning";
}

function APICatalog({
  platformState
}: {
  platformState: PlatformState | undefined;
}) {
  const proxyPort = platformState?.publicProxyPort;
  if (!proxyPort) {
    return (
      <p className="muted">
        API links are unavailable until the Host proxy port is reported.
      </p>
    );
  }

  const baseURL = `http://127.0.0.1:${proxyPort}`;
  const rows = [
    {
      label: "Swagger UI",
      value: `${baseURL}/swagger/`
    },
    {
      label: "VitalServer API",
      value: `${baseURL}/swagger/docs/openapi.yaml`
    },
    {
      label: "Runtime Control API",
      value: `${baseURL}/swagger/docs/macos-runtime/runtime-control.openapi.json`
    },
    {
      label: "Recorder Ingress API",
      value: `${baseURL}/swagger/docs/openapi/recorder-ingress.openapi.yaml`
    },
    {
      label: "VitalDB Observer API",
      value: `${baseURL}/swagger/docs/openapi/vitaldb-observer.openapi.yaml`
    }
  ];

  return (
    <KeyValueRows
      rows={rows.map((row) => ({
        label: row.label,
        value: (
          <a href={row.value} target="_blank" rel="noreferrer">
            {row.value}
          </a>
        )
      }))}
    />
  );
}

function GuestServiceControls({
  stackStatus,
  resourceReads,
  stackStatusError,
  disabled,
  isPending,
  onStart,
  onStop,
  onRestart
}: {
  stackStatus: RuntimeGuestControlStackStatus | undefined;
  resourceReads: Array<{
    service: string;
    resource: RuntimeGuestServiceResource | undefined;
    error: Error | null;
  }>;
  stackStatusError: Error | null;
  disabled: boolean;
  isPending: boolean;
  onStart: (service: string) => void;
  onStop: (service: string) => void;
  onRestart: (service: string) => void;
}) {
  const statuses = stackStatus?.services ?? [];
  const resourceByService = new Map(
    resourceReads.flatMap((read) =>
      read.resource ? [[read.service, read.resource] as const] : []
    )
  );
  const resourceIssueByService = new Map(
    resourceReads.flatMap((read) =>
      read.error ? [[read.service, read.error.message] as const] : []
    )
  );
  const knownServices = statuses
    .map((serviceStatus) => serviceStatus.service)
    .concat(Array.from(resourceByService.keys()))
    .concat(Array.from(resourceIssueByService.keys()))
    .filter((service, index, services) => services.indexOf(service) === index)
    .sort();
  const stackStatusIssue =
    stackStatus && stackStatus.state !== "loaded"
      ? `Runtime stack status is ${stackStatus.state}.`
      : "";
  const guestServicesReadError = stackStatusError?.message ?? stackStatusIssue;
  const guestServicesReadFailed =
    stackStatusError !== null || stackStatusIssue.length > 0;

  if (knownServices.length === 0 && !guestServicesReadFailed) {
    return null;
  }

  return (
    <div className="subsection">
      <h3>Observed state and control</h3>
      {knownServices.length > 0 ? (
        <DataTable
          rows={knownServices.map((service) => {
            const serviceStatus = statuses.find(
              (candidate) => candidate.service === service
            );
            const resource = resourceByService.get(service);
            return {
              id: service,
              service,
              state: serviceStatus?.state ?? NOT_REPORTED,
              health: serviceStatus?.health ?? NOT_REPORTED,
              spec: resource?.spec.state ?? NOT_REPORTED,
              desired: resource?.spec.desiredState ?? NOT_REPORTED,
              statusRead: resource?.status.readError
                ? `${resource.status.readError.kind}: ${resource.status.readError.message}`
                : resource?.status.state ?? NOT_REPORTED,
              observed: resource?.status.observedState ?? NOT_REPORTED,
              conditions: resource?.conditions.length
                ? resource.conditions
                    .map(
                      (condition) =>
                        `${condition.type}=${condition.status} ${condition.reason}: ${condition.message}`
                    )
                    .join("; ")
                : NOT_REPORTED,
              lastOperation: resource?.lastOperationId ?? NOT_REPORTED,
              resourceIssue: resourceIssueByService.get(service) ?? ""
            };
          })}
          getRowKey={(row) => row.id}
          columns={[
            { key: "service", header: "Service", render: (row) => row.service },
            { key: "state", header: "State", render: (row) => row.state },
            { key: "health", header: "Health", render: (row) => row.health },
            { key: "spec", header: "Spec", render: (row) => row.spec },
            { key: "desired", header: "Desired", render: (row) => row.desired },
            { key: "statusRead", header: "Status read", render: (row) => row.statusRead },
            { key: "observed", header: "Observed", render: (row) => row.observed },
            { key: "conditions", header: "Conditions", render: (row) => row.conditions },
            {
              key: "lastOperation",
              header: "Last operation",
              render: (row) => row.lastOperation
            },
            {
              key: "resourceIssue",
              header: "Resource read",
              render: (row) =>
                row.resourceIssue || (resourceByService.has(row.service) ? "OK" : NOT_REPORTED)
            },
            {
              key: "actions",
              header: "Actions",
              render: (row) => (
                <div className="action-row compact">
                  <ConfirmButton
                    confirmMessage={`Start Runtime service ${row.service}?`}
                    disabled={disabled || isPending}
                    onClick={() => onStart(row.service)}
                  >
                    Start
                  </ConfirmButton>
                  <ConfirmButton
                    confirmMessage={`Stop Runtime service ${row.service}?`}
                    disabled={disabled || isPending}
                    onClick={() => onStop(row.service)}
                  >
                    Stop
                  </ConfirmButton>
                  <ConfirmButton
                    confirmMessage={`Restart Runtime service ${row.service}?`}
                    disabled={disabled || isPending}
                    onClick={() => onRestart(row.service)}
                  >
                    Restart
                  </ConfirmButton>
                </div>
              )
            }
          ]}
          emptyText="No Runtime product services are reported."
        />
      ) : null}
      {guestServicesReadFailed ? (
        <ErrorState
          title="Failed to read Runtime product services"
          error={new Error(guestServicesReadError)}
        />
      ) : null}
    </div>
  );
}

function GuestServiceOperationResult({
  operation,
  error
}: {
  operation: RuntimeGuestControlServiceOperation | undefined;
  error: Error | null;
}) {
  if (error) {
    return <ErrorState error={error} />;
  }

  if (!operation) {
    return <p className="muted">No operation has completed yet.</p>;
  }

  return (
    <pre className="command-output">
      {[
        `operationId: ${operation.operationId}`,
        `service: ${operation.service}`,
        `command: ${operation.command}`,
        `state: ${operation.state}`,
        operation.failure
          ? `failure: ${operation.failure.kind} ${operation.failure.message}`
          : ""
      ]
        .filter(Boolean)
        .join("\n")}
    </pre>
  );
}

function RuntimeProviderCommandResult({
  command,
  error
}: {
  command: RuntimeProviderCommandResponse | undefined;
  error: Error | null;
}) {
  if (error) {
    return <ErrorState error={error} />;
  }

  if (!command) {
    return <p className="muted">No operation has completed yet.</p>;
  }

  return (
    <pre className="command-output">
      {[
        `operationId: ${command.operationId}`,
        `action: ${command.action}`,
        `state: ${command.state}`,
        `provider resource: ${command.provider.state}`,
        command.provider.document
          ? `provider lifecycle: ${command.provider.document.state}`
          : "",
        command.provider.document?.terminalReason
          ? `provider terminal reason: ${command.provider.document.terminalReason}`
          : "",
        command.provider.document?.message
          ? `provider lifecycle message: ${command.provider.document.message}`
          : "",
        command.provider.readError
          ? `provider readError: ${command.provider.readError}`
          : "",
        command.failure
          ? `failure: ${command.failure.kind} ${command.failure.message}`
          : ""
      ]
        .filter(Boolean)
        .join("\n")}
    </pre>
  );
}

function ValidationErrors({
  title,
  errors
}: {
  title: string;
  errors: string[];
}) {
  return (
    <div className="error-state">
      <strong>{title}</strong>
      {errors.map((error) => (
        <span key={error}>{error}</span>
      ))}
    </div>
  );
}

function booleanTone(
  value: boolean | null | undefined
): "success" | "warning" | "neutral" {
  if (value === true) {
    return "success";
  }
  if (value === false || value === null) {
    return "warning";
  }
  return "neutral";
}

function runtimeInstallationTone(
  value: string | null | undefined
): "success" | "warning" | "neutral" {
  if (value === "executable") {
    return "success";
  }
  return "warning";
}

function formatRuntimeInstallationState(value: string | null | undefined): string {
  if (!value) {
    return NOT_REPORTED;
  }
  if (value === "executable") {
    return "Executable";
  }
  if (value === "present") {
    return "Present but not executable";
  }
  if (value === "missing") {
    return "Missing";
  }
  if (value.startsWith("inspect-failed")) {
    return value.includes(":")
      ? `Inspect failed: ${value.split(":").slice(1).join(":").trim()}`
      : "Inspect failed";
  }
  return value;
}

function vmStateTone(
  value: string | null | undefined
): "success" | "warning" | "neutral" {
  if (value === "running") {
    return "success";
  }
  if (!value) {
    return "warning";
  }
  return "neutral";
}

function formatVMState(value: string | null | undefined): string {
  const trimmed = value?.trim();
  if (!trimmed) {
    return NOT_REPORTED;
  }
  return trimmed
    .split("-")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function formatServiceLoaded(value: boolean | null | undefined): string {
  if (value === undefined || value === null) {
    return NOT_REPORTED;
  }
  return value ? "Running" : "Stopped";
}

function updatedRuntimeSettings(
  current: RuntimeProductSettings,
  updates: Partial<RuntimeProductSettings>
): RuntimeProductSettings {
  return {
    ...current,
    ...updates
  };
}

function validateAdvancedNetworkSettings(settings: RuntimeProductSettings): {
  valid: boolean;
  errors: string[];
} {
  const errors: string[] = [];
  if (settings.vitalServerURL && !isAbsoluteHTTPURL(settings.vitalServerURL)) {
    errors.push("VitalServer URL must be an absolute http/https URL.");
  }
  if (settings.remoteConsoleURL && !isAbsoluteHTTPURL(settings.remoteConsoleURL)) {
    errors.push("Remote Console URL must be an absolute http/https URL.");
  }
  return {
    valid: errors.length === 0,
    errors
  };
}

function isAbsoluteHTTPURL(value: string): boolean {
  try {
    const parsed = new URL(value);
    return parsed.protocol === "http:" || parsed.protocol === "https:";
  } catch {
    return false;
  }
}

function BackupTable({
  rows,
  selected,
  onSelect,
  emptyText
}: {
  rows: RuntimeBackup[];
  selected: RuntimeBackup | null;
  onSelect: (backup: RuntimeBackup) => void;
  emptyText: string;
}) {
  const rowsWithPath = rows.filter(hasBackupPath);

  return (
    <DataTable
      rows={rowsWithPath}
      selectedKey={selected?.path ?? null}
      onSelectRow={onSelect}
      getRowKey={(row) => row.path}
      emptyText={emptyText}
      columns={[
        {
          key: "name",
          header: "Backup",
          render: (row) => backupName(row.path)
        },
        {
          key: "path",
          header: "Path",
          render: (row) => <span className="muted">{row.path ?? "-"}</span>
        },
        {
          key: "size",
          header: "Size",
          render: (row) => formatBytes(row.sizeBytes)
        }
      ]}
    />
  );
}

function hasBackupPath(backup: RuntimeBackup): backup is RuntimeBackup & { path: string } {
  return typeof backup.path === "string" && backup.path.length > 0;
}

function backupName(path: string | undefined): string {
  if (!path) {
    return "-";
  }
  const parts = path.split("/");
  return parts[parts.length - 1] || path;
}
