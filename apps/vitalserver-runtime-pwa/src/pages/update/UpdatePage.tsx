import { useEffect, useState } from "react";

import {
  useApplyUpdateBundle,
  useControlCapabilities,
  usePlatformWorkflow,
  useRollbackRelease,
  useSummarizeUpdateBundle,
  useVerifyUpdateBundle
} from "@/console/hooks";
import { ErrorState } from "@/components/ErrorState";
import { Panel } from "@/components/Panel";
import { ConfirmButton } from "@/components/ConfirmButton";
import type { PlatformWorkflowOperation } from "@/domain/runtime-control/contracts/runtimeControlTypes";

export function UpdatePage() {
  const [bundlePath, setBundlePath] = useState("");
  const summarize = useSummarizeUpdateBundle();
  const verify = useVerifyUpdateBundle();
  const apply = useApplyUpdateBundle();
  const capabilities = useControlCapabilities();
  const workflow = usePlatformWorkflow();
  const rollback = useRollbackRelease();
  const [reloadScheduled, setReloadScheduled] = useState(false);
  const [verificationRequestedPath, setVerificationRequestedPath] = useState<string | null>(null);
  const [verifiedBundlePath, setVerifiedBundlePath] = useState<string | null>(null);
  const hasBundlePath = bundlePath.trim().length > 0;
  const applyBundle = () => apply.mutate(bundlePath.trim());
  const currentOperation = workflow.data?.state === "loaded" ? workflow.data.operation : null;
  const observedApplyOperation = currentOperation ?? apply.data ?? null;
  const observedVerifyOperation =
    currentOperation?.kind === "update-verify"
      ? currentOperation
      : verify.data?.kind === "update-verify"
        ? verify.data
        : null;
  const workflowActive = currentOperation?.state === "accepted" || currentOperation?.state === "running";
  const canApplyBundle = capabilities.data?.canApplyBundle === true;
  const selectedBundleVerified =
    verifiedBundlePath !== null && verifiedBundlePath === bundlePath.trim();

  useEffect(() => {
    if (!verificationRequestedPath || !observedVerifyOperation) {
      return;
    }
    if (observedVerifyOperation.state === "completed") {
      setVerifiedBundlePath(verificationRequestedPath);
    } else if (observedVerifyOperation.state === "failed") {
      setVerifiedBundlePath(null);
    }
  }, [observedVerifyOperation, verificationRequestedPath]);

  useEffect(() => {
    if (
      reloadScheduled ||
      observedApplyOperation?.kind !== "update-apply" ||
      observedApplyOperation.state !== "completed"
    ) {
      return;
    }
    setReloadScheduled(true);
    window.setTimeout(() => {
      window.location.replace(`/?updated=${Date.now()}`);
    }, 4_000);
  }, [observedApplyOperation, reloadScheduled]);

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
              onChange={(event) => {
                setBundlePath(event.target.value);
                setVerificationRequestedPath(null);
                setVerifiedBundlePath(null);
              }}
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
          path that exists on the device running the Platform Agent.
        </p>
      </Panel>

      <Panel title="Bundle integrity">
        <pre className="command-output">
          {summarize.data?.summary ??
            "Inspect the bundle to show its stable bootstrap identity and target."}
        </pre>
        <button
          type="button"
          onClick={() => {
            const selectedPath = bundlePath.trim();
            setVerificationRequestedPath(selectedPath);
            setVerifiedBundlePath(null);
            verify.mutate(selectedPath);
          }}
          disabled={!hasBundlePath || verify.isPending || workflowActive}
        >
          Verify Publisher & Payload
        </button>
        {summarize.isError ? (
          <ErrorState title="Failed to inspect bundle" error={summarize.error} />
        ) : null}
        <WorkflowOperation operation={verify.data ?? null} />
        {verify.error ? <ErrorState title="Bundle integrity check failed" error={verify.error} /> : null}
      </Panel>

      <Panel title="Apply update">
        <p className="muted">
          Apply is enabled only after the selected bundle's publisher signature,
          target, next updater, specification, and complete payload closure are verified.
        </p>
        <ConfirmButton
          confirmMessage="Apply the authenticated update bundle?"
          onClick={applyBundle}
          disabled={
            !hasBundlePath ||
            !selectedBundleVerified ||
            apply.isPending ||
            workflowActive ||
            !canApplyBundle
          }
        >
          Apply Product Update
        </ConfirmButton>
        {!selectedBundleVerified && hasBundlePath ? (
          <p className="muted">Verify the selected bundle before applying it.</p>
        ) : null}
        {capabilities.isError ? (
          <ErrorState title="Failed to read update capability" error={capabilities.error} />
        ) : null}
        {!capabilities.isPending && !capabilities.isError && capabilities.data?.canApplyBundle === false ? (
          <p className="muted">
            Stable product update apply is unavailable in this installed build.
          </p>
        ) : null}
        {!capabilities.isPending && !capabilities.isError && capabilities.data?.canApplyBundle === undefined ? (
          <ErrorState
            title="Update capability response is incomplete"
            error={new Error("Platform capabilities did not report canApplyBundle.")}
          />
        ) : null}
        {reloadScheduled ? (
          <p className="muted">
            Helper is relaunching. This page will reload shortly to load the
            updated PWA bundle.
          </p>
        ) : null}
        <WorkflowOperation operation={apply.data ?? null} />
        {apply.error ? <ErrorState title="Update scheduling failed" error={apply.error} /> : null}
      </Panel>

      <Panel title="Current Platform workflow">
        {workflow.isPending ? <p>Loading Platform workflow...</p> : null}
        {workflow.isError ? <ErrorState title="Platform workflow read failed" error={workflow.error} /> : null}
        {workflow.data?.state === "missing" ? <p className="muted">No Platform workflow has run.</p> : null}
        {workflow.data?.readError ? (
          <ErrorState title="Platform workflow is unavailable" error={new Error(workflow.data.readError)} />
        ) : null}
        <WorkflowOperation operation={currentOperation} />
      </Panel>

      <Panel title="Rollback Platform release">
        <p className="muted">
          Rolls back to the previous immutable Platform release recorded by the install owner.
          Runtime and user data are preserved.
        </p>
        <button
          type="button"
          onClick={() => rollback.mutate()}
          disabled={rollback.isPending || workflowActive || capabilities.data?.canRollbackRelease !== true}
        >
          Rollback Release
        </button>
        {!capabilities.isPending && !capabilities.isError && capabilities.data?.canRollbackRelease === false ? (
          <p className="muted">Release rollback is not supported by this Platform Agent.</p>
        ) : null}
        <WorkflowOperation operation={rollback.data ?? null} />
        {rollback.error ? <ErrorState title="Release rollback scheduling failed" error={rollback.error} /> : null}
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
      {operation.release ? (
        <p className="muted">
          Platform {operation.release.platformVersion}, Runtime Bundle {operation.release.runtimeBundleVersion}
        </p>
      ) : null}
      {operation.failure ? (
        <ErrorState
          title={`Platform workflow failed: ${operation.failure.kind}`}
          error={new Error(operation.failure.message)}
        />
      ) : null}
    </div>
  );
}
