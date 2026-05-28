import { useMemo, useState } from "react";

import {
  useCreateRedisBackup,
  useDeleteHostBackup,
  useHostBackups,
  useRedisBackups,
  useRepairDatastore,
  useRepairProxy,
  useRepairRuntime,
  useRestoreRedisBackup,
  useRollbackBackup
} from "../../application/runtime-control/queries";
import type {
  RuntimeBackup
} from "../../domain/runtime-control/contracts/runtimeControlTypes";
import { formatBytes } from "../../domain/runtime-control/formatting/bytes";
import { CommandResult } from "../../shared/ui/CommandResult";
import { DataTable } from "../../shared/ui/DataTable";
import { ErrorState } from "../../shared/ui/ErrorState";
import { Panel } from "../../shared/ui/Panel";

export function AdvancedPage() {
  const hostBackups = useHostBackups();
  const redisBackups = useRedisBackups();
  const rollbackBackup = useRollbackBackup();
  const deleteHostBackup = useDeleteHostBackup();
  const createRedisBackup = useCreateRedisBackup();
  const restoreRedisBackup = useRestoreRedisBackup();
  const repairRuntime = useRepairRuntime();
  const repairProxy = useRepairProxy();
  const repairDatastore = useRepairDatastore();

  const [selectedHostBackup, setSelectedHostBackup] =
    useState<RuntimeBackup | null>(null);
  const [selectedRedisBackup, setSelectedRedisBackup] =
    useState<RuntimeBackup | null>(null);
  const [proxyPort, setProxyPort] = useState("");

  const latestCommand = useMemo(
    () =>
      repairRuntime.data ??
      repairProxy.data ??
      repairDatastore.data ??
      rollbackBackup.data ??
      deleteHostBackup.data ??
      createRedisBackup.data ??
      restoreRedisBackup.data,
    [
      createRedisBackup.data,
      deleteHostBackup.data,
      repairDatastore.data,
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
    rollbackBackup.error ??
    deleteHostBackup.error ??
    createRedisBackup.error ??
    restoreRedisBackup.error;

  return (
    <div className="page-stack">
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
            <button
              type="button"
              disabled={!selectedHostBackup || rollbackBackup.isPending}
              onClick={() =>
                selectedHostBackup?.path
                  ? rollbackBackup.mutate(selectedHostBackup.path)
                  : undefined
              }
            >
              Rollback
            </button>
            <button
              type="button"
              disabled={!selectedHostBackup || deleteHostBackup.isPending}
              onClick={() =>
                selectedHostBackup?.path
                  ? deleteHostBackup.mutate(selectedHostBackup.path)
                  : undefined
              }
            >
              Delete Backup
            </button>
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
            <button
              type="button"
              disabled={createRedisBackup.isPending}
              onClick={() => createRedisBackup.mutate("")}
            >
              Create Redis Backup
            </button>
            <button
              type="button"
              disabled={!selectedRedisBackup || restoreRedisBackup.isPending}
              onClick={() =>
                selectedRedisBackup?.path
                  ? restoreRedisBackup.mutate(selectedRedisBackup.path)
                  : undefined
              }
            >
              Restore Redis Backup
            </button>
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
          <button
            type="button"
            disabled={repairRuntime.isPending}
            onClick={() => repairRuntime.mutate()}
          >
            Repair Runtime
          </button>
          <button
            type="button"
            disabled={repairDatastore.isPending}
            onClick={() => repairDatastore.mutate()}
          >
            Repair Data Store
          </button>
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
          <button
            type="button"
            disabled={repairProxy.isPending}
            onClick={() => repairProxy.mutate(parseOptionalNumber(proxyPort))}
          >
            Repair Proxy
          </button>
        </div>
      </Panel>

      <Panel title="Operation result">
        <CommandResult result={latestCommand} error={latestError} />
      </Panel>
    </div>
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
  return (
    <DataTable
      rows={rows}
      selectedKey={selected?.path ?? null}
      onSelectRow={onSelect}
      getRowKey={(row) => row.path ?? ""}
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
