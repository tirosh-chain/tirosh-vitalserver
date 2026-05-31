import { useMemo, useState } from "react";

import {
  useCreateRedisBackup,
  useDeleteHostBackup,
  useHostBackups,
  useRedisBackups,
  useRepairDatastore,
  useRepairProxy,
  useRepairRuntime,
  useRepairVMDisk,
  useRuntimeCapabilities,
  useRuntimeOverview,
  useRestoreRedisBackup,
  useRollbackBackup
} from "@/application/runtime-control/queries";
import { canControlRecovery } from "@/domain/runtime-control/capabilities/runtimeCapabilities";
import type {
  RuntimeControlOverview,
  RuntimeBackup
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import { formatBytes } from "@/domain/runtime-control/formatting/bytes";
import { successfulHTTP } from "@/domain/runtime-control/formatting/http";
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

export function AdvancedPage() {
  const overview = useRuntimeOverview();
  const capabilities = useRuntimeCapabilities();
  const hostBackups = useHostBackups();
  const redisBackups = useRedisBackups();
  const rollbackBackup = useRollbackBackup();
  const deleteHostBackup = useDeleteHostBackup();
  const createRedisBackup = useCreateRedisBackup();
  const restoreRedisBackup = useRestoreRedisBackup();
  const repairRuntime = useRepairRuntime();
  const repairProxy = useRepairProxy();
  const repairDatastore = useRepairDatastore();
  const repairVMDisk = useRepairVMDisk();

  const [selectedHostBackup, setSelectedHostBackup] =
    useState<RuntimeBackup | null>(null);
  const [selectedRedisBackup, setSelectedRedisBackup] =
    useState<RuntimeBackup | null>(null);
  const [proxyPort, setProxyPort] = useState("");
  const canRollback = capabilities.data?.canRollback === true;
  const canRepair = canControlRecovery(capabilities.data);

  const latestCommand = useMemo(
    () =>
      repairRuntime.data ??
      repairProxy.data ??
      repairDatastore.data ??
      repairVMDisk.data ??
      rollbackBackup.data ??
      deleteHostBackup.data ??
      createRedisBackup.data ??
      restoreRedisBackup.data,
    [
      createRedisBackup.data,
      deleteHostBackup.data,
      repairDatastore.data,
      repairVMDisk.data,
      repairProxy.data,
      repairRuntime.data,
      restoreRedisBackup.data,
      rollbackBackup.data
    ]
  );

  const latestError =
    repairRuntime.error ??
    repairProxy.error ??
    repairDatastore.error ??
    repairVMDisk.error ??
    rollbackBackup.error ??
    deleteHostBackup.error ??
    createRedisBackup.error ??
    restoreRedisBackup.error;

  return (
    <div className="page-stack">
      <Panel title="Diagnostics">
        <Diagnostics overview={overview.data} />
        {overview.isError ? (
          <ErrorState title="Failed to read runtime diagnostics" error={overview.error} />
        ) : null}
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
            <ConfirmButton
              confirmMessage="Delete the selected managed backup? This cannot be undone."
              disabled={!selectedHostBackup || deleteHostBackup.isPending || !canRollback}
              onClick={() =>
                selectedHostBackup?.path
                  ? deleteHostBackup.mutate(selectedHostBackup.path)
                  : undefined
              }
            >
              Delete Backup
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
          <h3>Redis data recovery</h3>
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
              Create Redis Backup
            </ConfirmButton>
            <ConfirmButton
              confirmMessage="Restore the selected Redis backup? Current Redis data will be replaced."
              disabled={!selectedRedisBackup || restoreRedisBackup.isPending || !canRepair}
              onClick={() =>
                selectedRedisBackup?.path
                  ? restoreRedisBackup.mutate(selectedRedisBackup.path)
                  : undefined
              }
            >
              Restore Redis Backup
            </ConfirmButton>
          </div>
          {redisBackups.isError ? (
            <ErrorState
              title="Failed to read Redis backups"
              error={redisBackups.error}
            />
          ) : null}
        </div>
      </Panel>

      <Panel title="Runtime repair">
        <div className="action-row">
          <ConfirmButton
            confirmMessage="Restart and repair runtime services?"
            disabled={repairRuntime.isPending || !canRepair}
            onClick={() => repairRuntime.mutate()}
          >
            Repair Runtime
          </ConfirmButton>
          <ConfirmButton
            confirmMessage="Repair the Redis data store? Redis may create a backup and truncate a corrupted AOF tail."
            disabled={repairDatastore.isPending || !canRepair}
            onClick={() => repairDatastore.mutate()}
          >
            Repair Data Store
          </ConfirmButton>
          <ConfirmButton
            confirmMessage="Create a Redis backup, then recreate the VM disk from the installed base image? If the current VM cannot create a Redis backup, repair continues because the old VM disk is archived before replacement. Vital files stored on the host are preserved."
            disabled={repairVMDisk.isPending || !canRepair}
            onClick={() => repairVMDisk.mutate()}
          >
            Repair VM Disk
          </ConfirmButton>
        </div>
        <div className="inline-form">
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
          <ConfirmButton
            confirmMessage="Repair the host proxy service on the selected port?"
            disabled={repairProxy.isPending || !canRepair}
            onClick={() => repairProxy.mutate(parseOptionalNumber(proxyPort))}
          >
            Repair Proxy
          </ConfirmButton>
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

function ServiceHealth({ overview }: { overview: RuntimeControlOverview | undefined }) {
  const status = overview?.status;
  const services = [
    {
      label: "VM service",
      value: status?.vmServiceLoaded ? "Running" : "Stopped",
      healthy: status?.vmServiceLoaded
    },
    {
      label: "Proxy service",
      value: status?.proxyServiceLoaded ? "Running" : "Stopped",
      healthy: status?.proxyServiceLoaded
    },
    {
      label: "Watchdog service",
      value: status?.watchdogServiceLoaded ? "Running" : "Stopped",
      healthy: status?.watchdogServiceLoaded
    },
    {
      label: "Guest log sync service",
      value: status?.guestLogSyncServiceLoaded ? "Running" : "Stopped",
      healthy: status?.guestLogSyncServiceLoaded
    },
    {
      label: "VitalServer",
      value: status?.guestHTTP ?? "Unknown",
      healthy: successfulHTTP(status?.guestHTTP)
    },
    {
      label: "Network access",
      value: status?.hostProxyHTTP ?? "Unknown",
      healthy: successfulHTTP(status?.hostProxyHTTP)
    },
    {
      label: "Audit proxy",
      value: status?.containerObservation?.auditProxyHTTP ?? "Unknown",
      healthy: successfulHTTP(status?.containerObservation?.auditProxyHTTP)
    }
  ];

  return (
    <KeyValueRows
      rows={services.map((service) => ({
        label: service.label,
        value: (
          <StatusBadge tone={service.healthy ? "success" : "warning"}>
            {service.value}
          </StatusBadge>
        )
      }))}
    />
  );
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
