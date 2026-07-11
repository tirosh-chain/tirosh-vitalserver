import { useEffect, useMemo, useState } from "react";

import {
  useApplyRuntimeProductSettings,
  useCreateRedisBackup,
  useCreateRuntimeDataBackup,
  useRuntimeStack,
  useRuntimeServiceResources,
  useHostBackups,
  useRedisBackups,
  useRepairDatastore,
  useRepairProxy,
  useRepairRuntime,
  useRepairVMDisk,
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
  canControlRecovery
} from "@/domain/runtime-control/capabilities/runtimeCapabilities";
import type {
  PlatformState,
  RuntimeProductSettings,
  PlatformOperationState,
  RuntimeGuestControlStackStatus,
  RuntimeGuestControlServiceOperation,
  RuntimeGuestServiceResource,
  RuntimeBackup
} from "@/domain/runtime-control/contracts/runtimeControlTypes";

type RuntimeOverviewPresentation = {
  status?: PlatformState;
};

function platformServiceRunning(
  state: PlatformState | undefined,
  role: PlatformState["services"][number]["role"]
): boolean | undefined {
  const service = state?.services.find((candidate) => candidate.role === role);
  return service ? service.state === "running" : undefined;
}
import { formatBytes } from "@/domain/runtime-control/formatting/bytes";
import { formatHTTPStatus } from "@/domain/runtime-control/formatting/http";
import { NOT_REPORTED } from "@/domain/runtime-control/formatting/reported";
import {
  formatRuntimeState,
  runtimeStateTone
} from "@/domain/runtime-control/formatting/runtimeState";
import { useAppSettings } from "@/config/AppSettingsContext";
import { ConfirmButton } from "@/components/ConfirmButton";
import { CommandResult } from "@/components/CommandResult";
import { DataTable } from "@/components/DataTable";
import { ErrorState } from "@/components/ErrorState";
import { KeyValueRows } from "@/components/KeyValueRows";
import { Panel } from "@/components/Panel";
import { StatusBadge } from "@/components/StatusBadge";

export function AdvancedPage() {
  const appSettings = useAppSettings();
  const platformState = usePlatformState();
  const operationState = usePlatformOperationState();
  const capabilities = useControlCapabilities();
  const runtimeStack = useRuntimeStack();
  const runtimeServiceResources = useRuntimeServiceResources(
    runtimeStack.data?.services.map((service) => service.service) ?? []
  );
  const hostBackups = useHostBackups();
  const redisBackups = useRedisBackups();
  const runtimeDataBackups = useRuntimeDataBackups();
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
  const repairRuntime = useRepairRuntime();
  const repairProxy = useRepairProxy();
  const repairDatastore = useRepairDatastore();
  const repairVMDisk = useRepairVMDisk();

  const [selectedHostBackup, setSelectedHostBackup] =
    useState<RuntimeBackup | null>(null);
  const [selectedRedisBackup, setSelectedRedisBackup] =
    useState<RuntimeBackup | null>(null);
  const [selectedRuntimeDataBackup, setSelectedRuntimeDataBackup] =
    useState<RuntimeBackup | null>(null);
  const [proxyPort, setProxyPort] = useState("");
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

  const canRollback = capabilities.data?.canRollback === true;
  const canRepair = canControlRecovery(capabilities.data);
  const canApplySettings = canApplyRuntimeProductSettings(capabilities.data);
  const canEditNetworkExposure =
    capabilities.data?.canEditNetworkExposure === true;
  const canControlGuestServices =
    capabilities.data?.canControlGuestServices === true;

  const latestCommand = useMemo(
    () =>
      repairRuntime.data ??
      repairProxy.data ??
      repairDatastore.data ??
      repairVMDisk.data ??
      rollbackBackup.data ??
      createRuntimeDataBackup.data ??
      restoreRuntimeDataBackup.data ??
      createRedisBackup.data,
    [
      createRuntimeDataBackup.data,
      createRedisBackup.data,
      repairDatastore.data,
      repairVMDisk.data,
      repairProxy.data,
      repairRuntime.data,
      rollbackBackup.data,
      restoreRuntimeDataBackup.data
    ]
  );

  const latestError =
    startGuestService.error ??
    stopGuestService.error ??
    restartGuestService.error ??
    repairRuntime.error ??
    repairProxy.error ??
    repairDatastore.error ??
    repairVMDisk.error ??
    applySettings.error ??
    rollbackBackup.error ??
    createRuntimeDataBackup.error ??
    restoreRuntimeDataBackup.error ??
    createRedisBackup.error;
  const latestGuestServiceOperation =
    applySettings.data ??
    startGuestService.data ??
    stopGuestService.data ??
    restartGuestService.data;
  const configuredProxyPort =
    parseOptionalNumber(proxyPort) ??
    platformState.data?.publicProxyPort ??
    appSettings.runtimeControl.defaultProxyPort;
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

      <Panel title="Service health">
        <ServiceHealth overview={platformOverview} runtimeStack={runtimeStack.data} />
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
          onStart={(service) => startGuestService.mutate(service)}
          onStop={(service) => stopGuestService.mutate(service)}
          onRestart={(service) => restartGuestService.mutate(service)}
        />
      </Panel>

      <Panel title="API catalog">
        <APICatalog platformState={platformState.data} />
      </Panel>

      <Panel title="Recovery operations">
        <p className="muted">
          Use these actions when the runtime is installed but unhealthy after
          update, rollback, or unexpected shutdown.
        </p>

        <div className="subsection">
          <h3>Update recovery</h3>
          <BackupTable
            rows={hostBackups.data ?? []}
            selected={selectedHostBackup}
            onSelect={setSelectedHostBackup}
            emptyText="No rollback backups are available."
          />
          <div className="action-row">
            <ConfirmButton
              confirmMessage="Rollback to the selected managed backup? Runtime services may restart."
              disabled={!selectedHostBackup || rollbackBackup.isPending || !canRollback}
              onClick={() =>
                selectedHostBackup?.path
                  ? rollbackBackup.mutate(selectedHostBackup.path)
                  : undefined
              }
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
            rows={runtimeDataBackups.data ?? []}
            selected={selectedRuntimeDataBackup}
            onSelect={setSelectedRuntimeDataBackup}
            emptyText="No VitalServer backups are available."
          />
          <div className="action-row">
            <ConfirmButton
              confirmMessage="Create a VitalServer backup now?"
              disabled={createRuntimeDataBackup.isPending || !canRepair}
              onClick={() => createRuntimeDataBackup.mutate("")}
            >
              Create Backup
            </ConfirmButton>
            <ConfirmButton
              confirmMessage="Restore the selected VitalServer backup? This replaces current runtime data, settings, observability history, and Redis data, and may restart runtime services."
              disabled={
                !selectedRuntimeDataBackup?.path ||
                restoreRuntimeDataBackup.isPending ||
                !canRepair
              }
              onClick={() =>
                selectedRuntimeDataBackup?.path
                  ? restoreRuntimeDataBackup.mutate(selectedRuntimeDataBackup.path)
                  : undefined
              }
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
          <h3>Runtime repair</h3>
          <p className="muted">
            Use Repair Runtime first when VitalServer is unhealthy and the exact
            cause is unclear.
          </p>
          <div className="action-row">
            <ConfirmButton
              confirmMessage="Restart and repair runtime services?"
              disabled={repairRuntime.isPending || !canRepair}
              onClick={() => repairRuntime.mutate()}
            >
              Repair Runtime
            </ConfirmButton>
          </div>

          <div className="subsection">
            <h3>Advanced repair tools</h3>
            <p className="muted">
              Use these tools only when diagnostics or support identifies a
              specific failure source.
            </p>
            <div className="action-row">
              <ConfirmButton
                confirmMessage="Repair the host proxy service on the selected port?"
                disabled={repairProxy.isPending || !canRepair}
                onClick={() => repairProxy.mutate(configuredProxyPort)}
              >
                Repair Proxy
              </ConfirmButton>
              <ConfirmButton
                confirmMessage="Create a Redis backup, then recreate the VM disk from the installed base image? If the current VM cannot create a Redis backup, repair continues because the old VM disk is archived before replacement. Vital files stored on the host are preserved."
                disabled={repairVMDisk.isPending || !canRepair}
                onClick={() => repairVMDisk.mutate()}
              >
                Repair VM Disk
              </ConfirmButton>
              <ConfirmButton
                confirmMessage="Repair the Redis data store? Redis may create a backup and truncate a corrupted AOF tail."
                disabled={repairDatastore.isPending || !canRepair}
                onClick={() => repairDatastore.mutate()}
              >
                Repair Data Store
              </ConfirmButton>
            </div>
            <label>
              Proxy port
              <input
                type="number"
                min="1"
                max="65535"
                value={proxyPort}
                onChange={(event) => setProxyPort(event.target.value)}
                placeholder="Use configured port"
              />
            </label>
          </div>

          <div className="subsection">
            <h3>Redis-only recovery</h3>
            <p className="muted">
              Advanced repair action for Redis data only. Use a VitalServer
              backup for normal backup and restore.
            </p>
            <BackupTable
              rows={redisBackups.data ?? []}
              selected={selectedRedisBackup}
              onSelect={setSelectedRedisBackup}
              emptyText="No Redis backups are available."
            />
            <div className="action-row">
              <ConfirmButton
                confirmMessage="Create a recoverable Redis backup now?"
                disabled={createRedisBackup.isPending || !canRepair}
                onClick={() => createRedisBackup.mutate("")}
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
        {latestGuestServiceOperation ? (
          <GuestServiceOperationResult
            operation={latestGuestServiceOperation}
            error={latestError}
          />
        ) : (
          <CommandResult result={latestCommand} error={latestError} />
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

function ServiceHealth({
  overview,
  runtimeStack
}: {
  overview: RuntimeOverviewPresentation | undefined;
  runtimeStack: RuntimeGuestControlStackStatus | undefined;
}) {
  const status = overview?.status;
  const services = [
    {
      label: "Proxy service",
      value: formatServiceLoaded(platformServiceRunning(status, "public-proxy")),
      healthy: platformServiceRunning(status, "public-proxy")
    },
    {
      label: "Guest log sync service",
      value: formatServiceLoaded(platformServiceRunning(status, "log-sync")),
      healthy: platformServiceRunning(status, "log-sync")
    },
    {
      label: "Sleep prevention service",
      value: formatServiceLoaded(platformServiceRunning(status, "sleep-prevention")),
      healthy: platformServiceRunning(status, "sleep-prevention")
    },
    {
      label: "Watchdog service",
      value: formatServiceLoaded(platformServiceRunning(status, "watchdog")),
      healthy: platformServiceRunning(status, "watchdog")
    },
    {
      label: "VitalServer",
      value: runtimeServiceState(runtimeStack, "app"),
      healthy: null
    },
    {
      label: "Network access",
      value: formatHTTPStatus(status?.publicProxyHTTP),
      healthy: null
    },
    {
      label: "Redis UI service",
      value: runtimeServiceState(runtimeStack, "redis-ui"),
      healthy: null
    },
    {
      label: "Swagger UI service",
      value: runtimeServiceState(runtimeStack, "swagger-ui"),
      healthy: null
    }
  ];

  return (
    <KeyValueRows
      rows={services.map((service) => ({
        label: service.label,
        value: (
          <StatusBadge tone={serviceTone(service.healthy, service.value)}>
            {service.value}
          </StatusBadge>
        )
      }))}
    />
  );
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
      ? `Guest stack status is ${stackStatus.state}.`
      : "";
  const guestServicesReadError = stackStatusError?.message ?? stackStatusIssue;
  const guestServicesReadFailed =
    stackStatusError !== null || stackStatusIssue.length > 0;

  if (knownServices.length === 0 && !guestServicesReadFailed) {
    return null;
  }

  return (
    <div className="subsection">
      <h3>Product service controls</h3>
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
                    confirmMessage={`Start Guest service ${row.service}?`}
                    disabled={disabled || isPending}
                    onClick={() => onStart(row.service)}
                  >
                    Start
                  </ConfirmButton>
                  <ConfirmButton
                    confirmMessage={`Stop Guest service ${row.service}?`}
                    disabled={disabled || isPending}
                    onClick={() => onStop(row.service)}
                  >
                    Stop
                  </ConfirmButton>
                  <ConfirmButton
                    confirmMessage={`Restart Guest service ${row.service}?`}
                    disabled={disabled || isPending}
                    onClick={() => onRestart(row.service)}
                  >
                    Restart
                  </ConfirmButton>
                </div>
              )
            }
          ]}
          emptyText="No Guest services are reported."
        />
      ) : null}
      {guestServicesReadFailed ? (
        <ErrorState
          title="Failed to read Guest services"
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
  operation: RuntimeGuestControlServiceOperation;
  error: Error | null;
}) {
  if (error) {
    return <ErrorState error={error} />;
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

function runtimeServiceState(
  stack: RuntimeGuestControlStackStatus | undefined,
  serviceName: string
): string {
  const service = stack?.services.find(
    (candidate) => candidate.service === serviceName
  );
  if (!service) {
    return NOT_REPORTED;
  }
  return service.health ? `${service.state} (${service.health})` : service.state;
}

function serviceTone(
  healthy: boolean | null | undefined,
  value: string
): "success" | "warning" | "neutral" {
  if (healthy === true) {
    return "success";
  }
  if (healthy === false || value === NOT_REPORTED) {
    return "warning";
  }
  return "neutral";
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

function parseOptionalNumber(value: string): number | undefined {
  const trimmed = value.trim();
  if (!trimmed) {
    return undefined;
  }
  const parsed = Number(trimmed);
  return Number.isFinite(parsed) ? parsed : undefined;
}
