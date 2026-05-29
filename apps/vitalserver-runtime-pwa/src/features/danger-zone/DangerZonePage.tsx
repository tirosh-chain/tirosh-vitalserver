import { useMemo, useState } from "react";

import {
  useRuntimeCapabilities,
  useStartRuntimeServices,
  useStopRuntimeServices,
  useUninstallRuntime
} from "@/application/runtime-control/queries";
import { ConfirmButton } from "@/shared/ui/ConfirmButton";
import { CommandResult } from "@/shared/ui/CommandResult";
import { Panel } from "@/shared/ui/Panel";

export function DangerZonePage() {
  const capabilities = useRuntimeCapabilities();
  const startServices = useStartRuntimeServices();
  const stopServices = useStopRuntimeServices();
  const uninstallRuntime = useUninstallRuntime();
  const [uninstallConfirmation, setUninstallConfirmation] = useState("");
  const [cleanUninstall, setCleanUninstall] = useState(false);

  const latestCommand = useMemo(
    () => startServices.data ?? stopServices.data ?? uninstallRuntime.data,
    [startServices.data, stopServices.data, uninstallRuntime.data]
  );
  const latestError =
    startServices.error ?? stopServices.error ?? uninstallRuntime.error;

  const requiredConfirmation = cleanUninstall ? "CLEAN UNINSTALL" : "UNINSTALL";
  const canUninstall = uninstallConfirmation.trim() === requiredConfirmation;
  const canControlServices =
    capabilities.data?.canControlRuntimeServices === true;
  const canUninstallRuntime =
    capabilities.data?.canUninstallRuntime === true;

  return (
    <div className="page-stack">
      <Panel title="Runtime service controls">
        <p className="muted">
          These actions start or stop host-managed runtime services. Use repair
          actions from Advanced when the runtime should be recovered instead.
        </p>
        <div className="action-row">
          <ConfirmButton
            confirmMessage="Start VM, host proxy, and watchdog services?"
            disabled={startServices.isPending || !canControlServices}
            onClick={() => startServices.mutate()}
          >
            Start Runtime
          </ConfirmButton>
          <ConfirmButton
            confirmMessage="Stop runtime services? VitalServer will be unavailable until started again."
            disabled={stopServices.isPending || !canControlServices}
            onClick={() => stopServices.mutate()}
          >
            Stop Runtime
          </ConfirmButton>
        </div>
      </Panel>

      <Panel title="Uninstall runtime">
        <p className="error-state">
          Standard uninstall preserves logs, backups, Redis backups, and Vital
          files. Clean uninstall removes runtime data and configured Vital files.
        </p>
        <label className="checkbox-label">
          <input
            type="checkbox"
            checked={cleanUninstall}
            onChange={(event) => {
              setCleanUninstall(event.target.checked);
              setUninstallConfirmation("");
            }}
          />
          Clean uninstall
        </label>
        <div className="inline-form">
          <label>
            Confirmation
            <input
              type="text"
              value={uninstallConfirmation}
              onChange={(event) => setUninstallConfirmation(event.target.value)}
              placeholder={`Type ${requiredConfirmation}`}
            />
          </label>
          <ConfirmButton
            confirmMessage={
              cleanUninstall
                ? "Clean uninstall removes runtime files, logs, backups, Redis backups, and configured Vital files. Continue?"
                : "Uninstall removes runtime services and VM files while preserving logs, backups, Redis backups, and Vital files. Continue?"
            }
            disabled={!canUninstall || uninstallRuntime.isPending || !canUninstallRuntime}
            onClick={() => uninstallRuntime.mutate(cleanUninstall)}
          >
            {cleanUninstall ? "Clean Uninstall" : "Uninstall"}
          </ConfirmButton>
        </div>
      </Panel>

      <Panel title="Operation result">
        <CommandResult result={latestCommand} error={latestError} />
      </Panel>
    </div>
  );
}
