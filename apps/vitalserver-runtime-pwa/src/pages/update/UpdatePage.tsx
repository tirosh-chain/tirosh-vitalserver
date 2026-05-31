import { useState } from "react";

import {
  useApplyUpdateBundle,
  useSummarizeUpdateBundle,
  useVerifyUpdateBundle
} from "@/application/runtime-control/queries";
import { CommandResult } from "@/components/CommandResult";
import { ErrorState } from "@/components/ErrorState";
import { Panel } from "@/components/Panel";

export function UpdatePage() {
  const [bundlePath, setBundlePath] = useState("");
  const summarize = useSummarizeUpdateBundle();
  const verify = useVerifyUpdateBundle();
  const apply = useApplyUpdateBundle();
  const [reloadScheduled, setReloadScheduled] = useState(false);
  const hasBundlePath = bundlePath.trim().length > 0;
  const applyBundle = () => {
    apply.mutate(bundlePath, {
      onSuccess: (response) => {
        if (response.result?.exitCode !== 0) {
          return;
        }
        setReloadScheduled(true);
        window.setTimeout(() => {
          window.location.replace(`/?updated=${Date.now()}`);
        }, 4_000);
      }
    });
  };

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
          The Remote Console cannot browse host files directly. Enter a local
          path that exists on the Mac running Runtime Control API.
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
          <ErrorState title="Failed to inspect bundle" error={summarize.error} />
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
          onClick={applyBundle}
          disabled={!hasBundlePath || apply.isPending}
        >
          Apply Bundle
        </button>
        {reloadScheduled ? (
          <p className="muted">
            Helper is relaunching. This page will reload shortly to load the
            updated PWA bundle.
          </p>
        ) : null}
        <CommandResult result={apply.data} error={apply.error} />
      </Panel>
    </div>
  );
}
