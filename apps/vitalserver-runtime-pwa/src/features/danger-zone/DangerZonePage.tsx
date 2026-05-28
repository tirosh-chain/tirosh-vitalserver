import { useMemo, useState } from "react";

import {
  useStartRuntimeServices,
  useStopRuntimeServices,
  useUninstallRuntime
} from "../../api/queries";
import { CommandResult } from "../../shared/ui/CommandResult";
import { Panel } from "../../shared/ui/Panel";

export function DangerZonePage() {
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

  return (
    <div className="page-stack">
      <Panel title="Runtime service controls">
        <p className="muted">
          These actions start or stop host-managed runtime services. Use repair
          actions from Advanced when the runtime should be recovered instead.
        </p>
        <div className="action-row">
          <button
            type="button"
            disabled={startServices.isPending}
            onClick={() => startServices.mutate()}
          >
            Start Runtime
          </button>
          <button
            type="button"
            disabled={stopServices.isPending}
            onClick={() => stopServices.mutate()}
          >
            Stop Runtime
          </button>
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
          <button
            type="button"
            disabled={!canUninstall || uninstallRuntime.isPending}
            onClick={() => uninstallRuntime.mutate(cleanUninstall)}
          >
            {cleanUninstall ? "Clean Uninstall" : "Uninstall"}
          </button>
        </div>
      </Panel>

      <Panel title="Operation result">
        <CommandResult result={latestCommand} error={latestError} />
      </Panel>
    </div>
  );
}
