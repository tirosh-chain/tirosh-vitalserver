import { useState } from "react";

import {
  useApplyUpdateBundle,
  useSummarizeUpdateBundle,
  useVerifyUpdateBundle
} from "../../application/runtime-control/queries";
import { CommandResult } from "../../shared/ui/CommandResult";
import { Panel } from "../../shared/ui/Panel";

export function UpdatePage() {
  const [bundlePath, setBundlePath] = useState("");
  const summarize = useSummarizeUpdateBundle();
  const verify = useVerifyUpdateBundle();
  const apply = useApplyUpdateBundle();
  const hasBundlePath = bundlePath.trim().length > 0;

  return (
    <div className="page-stack">
      <Panel title="Update source">
        <div className="inline-form">
          <label>
            Offline bundle
            <input
              type="text"
              placeholder="/path/to/update-bundle.tar.gz"
              value={bundlePath}
              onChange={(event) => setBundlePath(event.target.value)}
            />
          </label>
          <button
            type="button"
            onClick={() => summarize.mutate(bundlePath)}
            disabled={!hasBundlePath || summarize.isPending}
          >
            Inspect
          </button>
        </div>
        <p className="muted">
          PWA cannot browse host files directly. Enter a local path that exists
          on the Mac running Runtime Control API.
        </p>
      </Panel>

      <Panel title="Bundle verification">
        <pre className="command-output">
          {summarize.data?.summary ??
            "Inspect the bundle to show manifest and checksum details."}
        </pre>
        <button
          type="button"
          onClick={() => verify.mutate(bundlePath)}
          disabled={!hasBundlePath || verify.isPending}
        >
          Verify
        </button>
        {summarize.isError ? (
          <p className="error-state">
            Failed to inspect bundle. {String(summarize.error)}
          </p>
        ) : null}
        <CommandResult result={verify.data} error={verify.error} />
      </Panel>

      <Panel title="Apply update">
        <p className="muted">
          Applies the verified bundle and may restart VitalServer services.
          VM/rootfs level changes remain administrator-level operations.
        </p>
        <button
          type="button"
          onClick={() => apply.mutate(bundlePath)}
          disabled={!hasBundlePath || apply.isPending}
        >
          Apply Bundle
        </button>
        <CommandResult result={apply.data} error={apply.error} />
      </Panel>
    </div>
  );
}
