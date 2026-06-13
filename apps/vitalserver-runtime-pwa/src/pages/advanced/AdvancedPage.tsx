import { useEffect, useMemo, useState } from "react";

import {
  useApplyRuntimeSettings,
  useCreateRedisBackup,
  useCreateRuntimeDataBackup,
  useHostBackups,
  useRedisBackups,
  useRepairDatastore,
  useRepairProxy,
  useRepairRuntime,
  useRepairVMDisk,
  useRuntimeDataBackups,
  useRuntimeCapabilities,
  useRuntimeSettings,
  useRuntimeOverview,
  useStartRuntimeServices,
  useStopRuntimeServices,
  useRollbackBackup,
  useRestoreRuntimeDataBackup
} from "@/console/hooks";
import {
  canApplyRuntimeSettings,
  canControlRecovery
} from "@/domain/runtime-control/capabilities/runtimeCapabilities";
import type {
  RuntimeSettings,
  RuntimeControlOverview,
  RuntimeBackup
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import { validateRuntimeSettings } from "@/domain/runtime-control/settings/runtimeSettingsPolicy";
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
  const overview = useRuntimeOverview();
  const capabilities = useRuntimeCapabilities();
  const hostBackups = useHostBackups();
  const redisBackups = useRedisBackups();
  const runtimeDataBackups = useRuntimeDataBackups();
  const runtimeSettings = useRuntimeSettings();
  const applySettings = useApplyRuntimeSettings();
  const rollbackBackup = useRollbackBackup();
  const createRedisBackup = useCreateRedisBackup();
  const createRuntimeDataBackup = useCreateRuntimeDataBackup();
  const restoreRuntimeDataBackup = useRestoreRuntimeDataBackup();
  const startServices = useStartRuntimeServices();
  const stopServices = useStopRuntimeServices();
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
  const [resetAdminPassword, setResetAdminPassword] = useState(false);
  const [newAdminPassword, setNewAdminPassword] = useState("");

  useEffect(() => {
    if (!runtimeSettings.data) {
      setVitalServerURL("");
      setRemoteConsoleURL("");
      setResetAdminPassword(false);
      setNewAdminPassword("");
      return;
    }
    setVitalServerURL(runtimeSettings.data.vitalServerURL);
    setRemoteConsoleURL(runtimeSettings.data.remoteConsoleURL);
    setResetAdminPassword(runtimeSettings.data.changeAdminPassword);
    setNewAdminPassword(runtimeSettings.data.adminPassword);
  }, [runtimeSettings.data]);

  const canRollback = capabilities.data?.canRollback === true;
  const canRepair = canControlRecovery(capabilities.data);
  const canApplySettings = canApplyRuntimeSettings(capabilities.data);
  const canEditNetworkExposure =
    capabilities.data?.canEditNetworkExposure === true;
  const canResetAdminPassword =
    capabilities.data?.canResetAdminPassword === true;
  const canControlServices =
    capabilities.data?.canControlRuntimeServices === true;

  const latestCommand = useMemo(
    () =>
      startServices.data ??
      stopServices.data ??
      repairRuntime.data ??
      repairProxy.data ??
      repairDatastore.data ??
      repairVMDisk.data ??
      applySettings.data ??
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
      applySettings.data,
      rollbackBackup.data,
      startServices.data,
      stopServices.data,
      restoreRuntimeDataBackup.data
    ]
  );

  const latestError =
    startServices.error ??
    stopServices.error ??
    repairRuntime.error ??
    repairProxy.error ??
    repairDatastore.error ??
    repairVMDisk.error ??
    applySettings.error ??
    rollbackBackup.error ??
    createRuntimeDataBackup.error ??
    restoreRuntimeDataBackup.error ??
    createRedisBackup.error;
  const configuredProxyPort =
    parseOptionalNumber(proxyPort) ??
    overview.data?.settings?.proxyPort ??
    overview.data?.status?.proxyPort ??
    appSettings.runtimeControl.defaultProxyPort;

  const networkSettings =
    runtimeSettings.data &&
    updatedRuntimeSettings(runtimeSettings.data, {
      vitalServerURL,
      remoteConsoleURL
    });
  const adminSettings =
    runtimeSettings.data &&
    updatedRuntimeSettings(runtimeSettings.data, {
      changeAdminPassword: resetAdminPassword,
      adminPassword: resetAdminPassword ? newAdminPassword : ""
    });
  const networkValidation = networkSettings
    ? validateAdvancedNetworkSettings(networkSettings)
    : { valid: false, errors: ["Runtime settings are not loaded."] };
  const adminValidation = adminSettings
    ? validateRuntimeSettings(adminSettings)
    : { valid: false, errors: ["Runtime settings are not loaded."] };
  const canApplyNetworkSettings =
    Boolean(networkSettings) &&
    canApplySettings &&
    canEditNetworkExposure &&
    networkValidation.valid &&
    !applySettings.isPending;
  const canApplyAdminSettings =
    Boolean(adminSettings) &&
    canApplySettings &&
    adminValidation.valid &&
    !applySettings.isPending &&
    (!resetAdminPassword || canResetAdminPassword);

  const applyRuntimeSettings = (
    settings: RuntimeSettings | false | undefined
  ) => {
    if (!settings) {
      return;
    }
    applySettings.mutate({ settings });
  };

  return (
    <div className="page-stack">
      <Panel title="Diagnostics">
        <Diagnostics overview={overview.data} />
        {overview.isError ? (
          <ErrorState title="Failed to read runtime diagnostics" error={overview.error} />
        ) : null}
      </Panel>

      <Panel title="VM health">
        <VMHealth overview={overview.data} />
      </Panel>

      <Panel title="Service health">
        <ServiceHealth overview={overview.data} />
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
        {runtimeSettings.isError ? (
          <ErrorState title="Failed to read settings" error={runtimeSettings.error} />
        ) : null}
        <div className="action-row">
          <ConfirmButton
            confirmMessage="Apply runtime settings? This may rewrite runtime configuration and restart runtime services when restart after save is enabled."
            disabled={!canApplyNetworkSettings}
            onClick={() => applyRuntimeSettings(networkSettings)}
          >
            Apply Settings
          </ConfirmButton>
        </div>
      </Panel>

      <Panel title="Admin operations">
        <p className="muted">
          Administrative runtime actions that affect access or runtime service
          availability.
        </p>
        <div className="settings-toggles">
          <label className="checkbox-label">
            <input
              type="checkbox"
              checked={resetAdminPassword}
              disabled={!canResetAdminPassword}
              onChange={(event) => setResetAdminPassword(event.target.checked)}
            />
            Reset admin password
          </label>
        </div>
        {resetAdminPassword ? (
          <label>
            New admin password
            <input
              type="password"
              value={newAdminPassword}
              disabled={!canResetAdminPassword}
              onChange={(event) => setNewAdminPassword(event.target.value)}
            />
          </label>
        ) : null}
        {adminValidation.errors.length ? (
          <ValidationErrors title="Admin settings need attention" errors={adminValidation.errors} />
        ) : null}
        <div className="action-row">
          <ConfirmButton
            confirmMessage="Apply runtime settings? This may rewrite runtime configuration and restart runtime services when restart after save is enabled."
            disabled={!canApplyAdminSettings}
            onClick={() => applyRuntimeSettings(adminSettings)}
          >
            Apply Settings
          </ConfirmButton>
        </div>

        <div className="subsection">
          <h3>Runtime service controls</h3>
          <p className="muted">
            Starts or stops the VM, host proxy, and watchdog together. Use Stop
            for planned maintenance, then Start to bring VitalServer back online.
          </p>
          <div className="action-row">
            <ConfirmButton
              confirmMessage="Starts the VM, host proxy, and watchdog services, then waits for VitalServer to become healthy."
              disabled={startServices.isPending || !canControlServices}
              onClick={() => startServices.mutate()}
            >
              Start Runtime Services
            </ConfirmButton>
            <ConfirmButton
              confirmMessage="Stops the watchdog, host proxy, and VM services. VitalServer will be unavailable until runtime services are started again."
              disabled={stopServices.isPending || !canControlServices}
              onClick={() => stopServices.mutate()}
            >
              Stop Runtime Services
            </ConfirmButton>
          </div>
        </div>
      </Panel>

      <Panel title="Operation result">
        <CommandResult result={latestCommand} error={latestError} />
      </Panel>
    </div>
  );
}

function Diagnostics({ overview }: { overview: RuntimeControlOverview | undefined }) {
  const status = overview?.status;
  return (
    <KeyValueRows
      rows={[
        {
          label: "Runtime state",
          value: (
            <StatusBadge tone={runtimeStateTone(status?.runtimeState)}>
              {formatRuntimeState(status?.runtimeState)}
            </StatusBadge>
          )
        },
        { label: "Operation", value: status?.operation ?? "Unknown" },
        { label: "Runtime version", value: status?.runtimeVersion ?? "Unknown" },
        { label: "VM IP", value: status?.vmIP ?? "Waiting" },
        ...(status?.statusDocumentError
          ? [
              {
                label: "Status document",
                value: `Read failed: ${status.statusDocumentError}`
              }
            ]
          : []),
        ...(status?.guestRuntimeStateError
          ? [
              {
                label: "Guest runtime state",
                value: `Read failed: ${status.guestRuntimeStateError}`
              }
            ]
          : []),
        {
          label: "Failure reasons",
          value: status?.failureReasons?.length
            ? status.failureReasons.join(", ")
            : "-"
        }
      ]}
    />
  );
}

function VMHealth({ overview }: { overview: RuntimeControlOverview | undefined }) {
  const status = overview?.status;
  const runtimeInstalled = status?.runtimeInstalled;
  const vmServiceLoaded = status?.vmServiceLoaded;
  const vmIP = status?.vmIP?.trim();
  const vmErrors = status?.vmErrors?.filter((error) => error.trim().length > 0);

  return (
    <KeyValueRows
      rows={[
        {
          label: "Runtime installation",
          value: (
            <StatusBadge tone={booleanTone(runtimeInstalled)}>
              {runtimeInstalled === undefined
                ? NOT_REPORTED
                : runtimeInstalled
                  ? "Installed"
                  : "Missing"}
            </StatusBadge>
          )
        },
        {
          label: "VM state",
          value: (
            <StatusBadge tone={vmStateTone(status?.vmState)}>
              {formatVMState(status?.vmState)}
            </StatusBadge>
          )
        },
        {
          label: "VM service",
          value: (
            <StatusBadge tone={booleanTone(vmServiceLoaded)}>
              {formatServiceLoaded(vmServiceLoaded)}
            </StatusBadge>
          )
        },
        {
          label: "VM IP address",
          value: (
            <StatusBadge tone={vmIP ? "success" : "warning"}>
              {vmIP || NOT_REPORTED}
            </StatusBadge>
          )
        },
        ...(vmErrors?.length
          ? [
              {
                label: "VM errors",
                value: (
                  <StatusBadge tone="warning">
                    {vmErrors.join(", ")}
                  </StatusBadge>
                )
              }
            ]
          : [])
      ]}
    />
  );
}

function ServiceHealth({ overview }: { overview: RuntimeControlOverview | undefined }) {
  const status = overview?.status;
  const composeServices = status?.containerObservation?.composeServices ?? [];
  const observerService = composeServices.find(
    (service) => service.service === "vitaldb-observer"
  );
  const services = [
    {
      label: "Proxy service",
      value: formatServiceLoaded(status?.proxyServiceLoaded),
      healthy: status?.proxyServiceLoaded
    },
    {
      label: "Guest log sync service",
      value: formatServiceLoaded(status?.guestLogSyncServiceLoaded),
      healthy: status?.guestLogSyncServiceLoaded
    },
    {
      label: "Sleep prevention service",
      value: formatServiceLoaded(status?.sleepPreventionServiceLoaded),
      healthy: status?.sleepPreventionServiceLoaded
    },
    {
      label: "Watchdog service",
      value: formatServiceLoaded(status?.watchdogServiceLoaded),
      healthy: status?.watchdogServiceLoaded
    },
    {
      label: "VitalServer",
      value: formatHTTPStatus(status?.guestHTTP),
      healthy: null
    },
    {
      label: "Network access",
      value: formatHTTPStatus(status?.hostProxyHTTP),
      healthy: null
    },
    {
      label: "VitalDB Observer",
      value: formatComposeService(observerService),
      healthy: composeServiceHealthy(observerService)
    },
    {
      label: "Redis UI",
      value: formatHTTPStatus(status?.redisUIHTTP),
      healthy: null
    },
    {
      label: "Swagger UI",
      value: formatHTTPStatus(status?.swaggerUIHTTP),
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

function formatComposeService(
  service:
    | {
        state?: string | null;
        health?: string | null;
      }
    | undefined
): string {
  const health = service?.health?.trim();
  if (health) {
    return health.charAt(0).toUpperCase() + health.slice(1);
  }
  const state = service?.state?.trim();
  if (state) {
    return state.charAt(0).toUpperCase() + state.slice(1);
  }
  return NOT_REPORTED;
}

function composeServiceHealthy(
  service:
    | {
        state?: string | null;
        health?: string | null;
      }
    | undefined
): boolean | null {
  if (!service) {
    return null;
  }
  if (service.health === "healthy") {
    return true;
  }
  if (service.health) {
    return false;
  }
  if (service.state === "running") {
    return true;
  }
  return false;
}

function updatedRuntimeSettings(
  current: RuntimeSettings,
  updates: Partial<RuntimeSettings>
): RuntimeSettings {
  return {
    ...current,
    ...updates
  };
}

function validateAdvancedNetworkSettings(settings: RuntimeSettings): {
  valid: boolean;
  errors: string[];
} {
  const validation = validateRuntimeSettings(settings);
  const errors = [...validation.errors];
  if (!isAbsoluteHTTPURL(settings.vitalServerURL)) {
    errors.push("VitalServer URL must be an absolute http/https URL.");
  }
  if (!isAbsoluteHTTPURL(settings.remoteConsoleURL)) {
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
