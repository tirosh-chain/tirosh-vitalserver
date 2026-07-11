import { useMemo, useState } from "react";

import {
  useDeleteRuntimeDataBackup,
  useDeleteUpdateBackup,
  useHostBackups,
  useRuntimeDataBackups,
  useControlCapabilities,
  useUninstallRuntime
} from "@/console/hooks";
import type {
  PlatformWorkflowOperation,
  RuntimeBackup
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import { formatBytes } from "@/domain/runtime-control/formatting/bytes";
import { ConfirmButton } from "@/components/ConfirmButton";
import { CommandResult } from "@/components/CommandResult";
import { DataTable } from "@/components/DataTable";
import { ErrorState } from "@/components/ErrorState";
import { Panel } from "@/components/Panel";

export function DangerZonePage() {
  const capabilities = useControlCapabilities();
  const canManageBackups = capabilities.data?.canRollback === true;
  const unavailableBackupMessage = capabilities.isPending
    ? "Loading backup capability..."
    : capabilities.isError
      ? "Backup capability could not be read."
      : "Backup and rollback operations are not supported by this Runtime Control API.";
  const hostBackups = useHostBackups(canManageBackups);
  const runtimeDataBackups = useRuntimeDataBackups(canManageBackups);
  const deleteUpdateBackup = useDeleteUpdateBackup();
  const deleteRuntimeDataBackup = useDeleteRuntimeDataBackup();
  const uninstallRuntime = useUninstallRuntime();
  const [selectedUpdateBackup, setSelectedUpdateBackup] =
    useState<RuntimeBackup | null>(null);
  const [selectedRuntimeDataBackup, setSelectedRuntimeDataBackup] =
    useState<RuntimeBackup | null>(null);
  const [cleanUninstallConfirmation, setCleanUninstallConfirmation] =
    useState("");

  const latestCommand = useMemo(
    () =>
      deleteUpdateBackup.data ??
      deleteRuntimeDataBackup.data,
    [
      deleteRuntimeDataBackup.data,
      deleteUpdateBackup.data
    ]
  );
  const latestError =
    deleteUpdateBackup.error ??
    deleteRuntimeDataBackup.error ??
    uninstallRuntime.error;

  const canCleanUninstall =
    cleanUninstallConfirmation.trim() === "CLEAN UNINSTALL";
  const canUninstallRuntime =
    capabilities.data?.canUninstallRuntime === true;
  const canRollback = canManageBackups;

  return (
    <div className="page-stack">
      {capabilities.isError ? (
        <ErrorState
          title="Failed to read backup capability"
          error={capabilities.error}
        />
      ) : null}
      {!capabilities.isPending && !capabilities.isError && !canManageBackups ? (
        <p className="muted">
          Backup and rollback operations are not supported by this Runtime
          Control API.
        </p>
      ) : null}
      <Panel title="Delete Update Backup">
        <p className="muted">
          Deletes a managed update/rollback backup. This does not delete
          VitalServer backups.
        </p>
        <BackupTable
          rows={canManageBackups ? hostBackups.data ?? [] : []}
          selected={selectedUpdateBackup}
          onSelect={setSelectedUpdateBackup}
          emptyText={
            canManageBackups
              ? "No update backups are available."
              : unavailableBackupMessage
          }
        />
        <div className="action-row">
          <ConfirmButton
            confirmMessage="Delete the selected update backup? This cannot be undone. VitalServer backups are not deleted."
            disabled={
              !selectedUpdateBackup?.path ||
              deleteUpdateBackup.isPending ||
              !canRollback
            }
            onClick={() =>
              selectedUpdateBackup?.path
                ? deleteUpdateBackup.mutate(selectedUpdateBackup.path)
                : undefined
            }
          >
            Delete Update Backup
          </ConfirmButton>
        </div>
        {hostBackups.isError ? (
          <ErrorState title="Failed to read update backups" error={hostBackups.error} />
        ) : null}
      </Panel>

      <Panel title="Delete VitalServer Backup">
        <p className="muted">
          Deletes a selected VitalServer backup. This does not delete update
          rollback backups or the current runtime data.
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
            confirmMessage="Delete the selected VitalServer backup? This cannot be undone. Update rollback backups and current runtime data are not deleted."
            disabled={
              !selectedRuntimeDataBackup?.path ||
              deleteRuntimeDataBackup.isPending ||
              !canManageBackups
            }
            onClick={() =>
              selectedRuntimeDataBackup?.path
                ? deleteRuntimeDataBackup.mutate(selectedRuntimeDataBackup.path)
                : undefined
            }
          >
            Delete VitalServer Backup
          </ConfirmButton>
        </div>
        {runtimeDataBackups.isError ? (
          <ErrorState
            title="Failed to read VitalServer backups"
            error={runtimeDataBackups.error}
          />
        ) : null}
      </Panel>

      <Panel title="Destructive operations">
        <p className="error-state">
          Standard uninstall preserves logs, backups, Redis backups, and Vital
          files. Clean uninstall removes runtime data and configured Vital files.
        </p>
        <div className="inline-form">
          <ConfirmButton
            confirmMessage="Standard uninstall removes the application and Runtime system files while preserving Runtime data. Continue?"
            disabled={uninstallRuntime.isPending || !canUninstallRuntime}
            onClick={() => uninstallRuntime.mutate(false)}
          >
            Standard Uninstall
          </ConfirmButton>
          <label>
            Confirmation
            <input
              type="text"
              value={cleanUninstallConfirmation}
              onChange={(event) =>
                setCleanUninstallConfirmation(event.target.value)
              }
              placeholder="Type CLEAN UNINSTALL"
            />
          </label>
          <ConfirmButton
            confirmMessage="Clean uninstall removes runtime files, logs, backups, Redis backups, and configured Vital files. Continue?"
            disabled={
              !canCleanUninstall ||
              uninstallRuntime.isPending ||
              !canUninstallRuntime
            }
            onClick={() => uninstallRuntime.mutate(true)}
          >
            Clean Uninstall
          </ConfirmButton>
        </div>
      </Panel>

      <Panel title="Operation result">
        <CommandResult result={latestCommand} error={latestError} />
        <WorkflowOperation operation={uninstallRuntime.data ?? null} />
      </Panel>
    </div>
  );
}

function WorkflowOperation({ operation }: { operation: PlatformWorkflowOperation | null }) {
  if (!operation) {
    return null;
  }
  return (
    <div className="operation-state">
      <p>
        Operation {operation.operationId}: {operation.kind} / {operation.state}
      </p>
      {operation.failure ? (
        <ErrorState
          title={`Uninstall workflow failed: ${operation.failure.kind}`}
          error={new Error(operation.failure.message)}
        />
      ) : null}
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
