import { useEffect, useState } from "react";

import {
  useApplyRuntimeSettings,
  useRuntimeCapabilities,
  useRuntimeSettings
} from "@/console/hooks";
import { canApplyRuntimeSettings } from "@/domain/runtime-control/capabilities/runtimeCapabilities";
import {
  draftToRuntimeSettings,
  parseOptionalNumber,
  runtimeSettingsToDraft,
  type RuntimeSettingsDraft,
  usesCustomAdvertisedURL
} from "@/pages/settings/runtimeSettingsForm";
import {
  containerMemoryLimitRanges,
  runtimeSettingsActivationDecision,
  startOnBootControlState,
  validateRuntimeSettings,
  type RuntimeCapabilityReadState
} from "@/domain/runtime-control/settings/runtimeSettingsPolicy";
import { sameHostRuntimeURL } from "@/domain/runtime-control/formatting/http";
import { ConfirmButton } from "@/components/ConfirmButton";
import { ErrorState } from "@/components/ErrorState";
import { Panel } from "@/components/Panel";

export function SettingsPage() {
  const settings = useRuntimeSettings();
  const capabilities = useRuntimeCapabilities();
  const applySettings = useApplyRuntimeSettings();
  const [draft, setDraft] = useState<RuntimeSettingsDraft | null>(null);
  const [customAdvertisedURL, setCustomAdvertisedURL] = useState(false);
  const [changedRuntimeControlPort, setChangedRuntimeControlPort] =
    useState<number | null>(null);

  useEffect(() => {
    if (settings.data) {
      setDraft(
        normalizeContainerMemoryLimitDraft(
          runtimeSettingsToDraft(settings.data),
          settings.data.memoryGiB * 1024
        )
      );
      setCustomAdvertisedURL(usesCustomAdvertisedURL(settings.data));
    } else {
      setDraft(null);
      setCustomAdvertisedURL(false);
    }
  }, [settings.data]);

  const updateField = (
    field: keyof RuntimeSettingsDraft,
    value: string | boolean
  ) => {
    setDraft((current) => {
      if (!current) {
        return current;
      }
      const next = { ...current, [field]: value };
      const normalized = normalizeContainerMemoryLimitDraft(
        next,
        draftMemoryMiB(next, settings.data?.memoryGiB ?? 0)
      );
      if (
        field !== "restartAfterSave" &&
        settings.data &&
        customAdvertisedURL !== undefined
      ) {
        return enableContainerReconcileActivationWhenNeeded(
          normalized,
          settings.data,
          customAdvertisedURL
        );
      }
      return normalized;
    });
  };

  const apply = () => {
    if (!settings.data || !draft) {
      return;
    }
    const runtimeSettings = draftToRuntimeSettings(
      draft,
      settings.data,
      customAdvertisedURL
    );
    const validation = validateRuntimeSettings(runtimeSettings);
    if (!validation.valid) {
      return;
    }
    applySettings.mutate(
      { settings: runtimeSettings },
      {
        onSuccess: () => {
          setChangedRuntimeControlPort(
            changedRuntimeControlPortValue(runtimeSettings.runtimeControlPort)
          );
        }
      }
    );
  };

  const runtimeSettings = settings.data && draft
    ? draftToRuntimeSettings(draft, settings.data, customAdvertisedURL)
    : null;
  const validation = runtimeSettings
    ? validateRuntimeSettings(runtimeSettings)
    : { valid: false, errors: ["Runtime settings are not loaded."] };
  const canApply =
    runtimeSettings !== null &&
    canApplyRuntimeSettings(capabilities.data) &&
    validation.valid &&
    !settings.isLoading &&
    !applySettings.isPending;
  const canEditVMResources = capabilities.data?.canEditVMResources === true;
  const canEditNetworkExposure =
    capabilities.data?.canEditNetworkExposure === true;
  const canEditLocalFiles = capabilities.data?.canOpenLocalFiles === true;
  const canControlServices =
    capabilities.data?.canControlRuntimeServices === true;
  const systemTimeZone =
    Intl.DateTimeFormat().resolvedOptions().timeZone || "system local time";
  const capabilityReadState: RuntimeCapabilityReadState = capabilities.isPending
    ? "loading"
    : capabilities.isError
      ? "failed"
      : capabilities.data
        ? "available"
        : "missing";

  if (!settings.data || !draft) {
    return (
      <div className="page-stack">
        <Panel
          title="VM resources"
          actions={
            <ConfirmButton
              confirmMessage="Apply runtime settings? This may update launchd services, rewrite runtime configuration, and restart the VM runtime only when a changed setting requires it and activation after save is enabled."
              onClick={apply}
              disabled
            >
              Apply
            </ConfirmButton>
          }
        >
          {settings.isPending ? (
            <p className="empty-state">Loading runtime settings...</p>
          ) : null}
          {settings.isError ? (
            <ErrorState title="Failed to read settings" error={settings.error} />
          ) : null}
          {!settings.isPending && !settings.isError && !settings.data ? (
            <ErrorState
              title="Settings response is incomplete"
              error={
                new Error("Runtime Control API did not return settings data.")
              }
            />
          ) : null}
          {settings.data && !draft ? (
            <p className="empty-state">Preparing settings form...</p>
          ) : null}
        </Panel>
      </div>
    );
  }

  const proxyPort = parseOptionalNumber(draft.proxyPort);
  const runtimeControlPort = parseOptionalNumber(draft.runtimeControlPort);
  const browserHostname = currentBrowserHostname();
  const sameHostVitalServerURL = sameHostRuntimeURL({
    hostname: browserHostname,
    port: proxyPort
  });
  const sameHostRemoteConsoleURL = sameHostRuntimeURL({
    hostname: browserHostname,
    port: runtimeControlPort
  });
  const runtimeControlURLPreview =
    runtimeControlPort === undefined
      ? "Remote Console port is not available."
      : sameHostRemoteConsoleURL ?? "Browser host is not available.";
  const defaultAdvertisedURLPreview =
    proxyPort === undefined
      ? "Proxy port is not available."
      : sameHostVitalServerURL ?? "Browser host is not available.";
  const advertisedPort = parseOptionalNumber(draft.publicPort);
  const customAdvertisedURLPreview =
    draft.publicHost.trim() && advertisedPort !== undefined
      ? `http://${draft.publicHost.trim()}:${advertisedPort}/`
      : "Custom advertised URL is not available.";
  const vitalServerURLPreview = customAdvertisedURL
    ? customAdvertisedURLPreview
    : defaultAdvertisedURLPreview;
  const startOnBootControl = startOnBootControlState({
    startOnBootConfigurable: settings.data.startOnBootConfigurable,
    capabilityReadState,
    capabilities: capabilities.data
  });
  const backupAppliedState = runtimeSettings
    ? backupAppliedSettingsSummary(settings.data, runtimeSettings, systemTimeZone)
    : "";
  const logArchiveAppliedState = runtimeSettings
    ? logArchiveAppliedSettingsSummary(settings.data, runtimeSettings)
    : "";
  const containerMemoryLimitVMMaxMiB =
    (runtimeSettings?.memoryGiB ?? settings.data.memoryGiB) * 1024;
  const containerMemoryLimitTotalPercent = runtimeSettings
    ? runtimeContainerLimitTotalPercent(runtimeSettings)
    : 0;
  const updateReplayThroughput = (value: string) => {
    updateField("recorderIngressSendDataReplayMaxMiBPerSecond", value);
  };
  const normalizeReplayThroughput = () => {
    updateField(
      "recorderIngressSendDataReplayMaxMiBPerSecond",
      normalizeReplayThroughputValue(draft.recorderIngressSendDataReplayMaxMiBPerSecond)
    );
  };
  const updateContainerMemoryLimitPercent = (
    field:
      | "vitalServerContainerMemoryLimitMiB"
      | "recorderIngressContainerMemoryLimitMiB"
      | "redisContainerMemoryLimitMiB",
    nextPercent: number,
    range: { minMiB: number; maxMiB: number }
  ) => {
    setDraft((current) => {
      if (!current) {
        return current;
      }
      const vmMiB = draftMemoryMiB(current, settings.data.memoryGiB);
      const otherPercent =
        containerMemoryLimitDraftTotalPercent(current, vmMiB) -
        containerMemoryLimitPercent(current[field], vmMiB);
      const percentRange = containerMemoryLimitPercentRange(
        range,
        vmMiB
      );
      const allowedUpper = Math.max(
        percentRange.min,
        Math.min(
          percentRange.max,
          containerMemoryLimitRanges.maxCombinedPercent - otherPercent
        )
      );
      const percent = Math.min(
        Math.max(Math.round(nextPercent), percentRange.min),
        allowedUpper
      );
      return enableContainerReconcileActivationWhenNeeded(normalizeContainerMemoryLimitDraft({
        ...current,
        [field]: String(containerMemoryLimitMiB(percent, range, vmMiB))
      }, vmMiB), settings.data, customAdvertisedURL);
    });
  };
  const backupSettingsPending = runtimeSettings
    ? backupSettingsChanged(settings.data, runtimeSettings)
    : false;
  const logArchiveSettingsPending = runtimeSettings
    ? logArchiveSettingsChanged(settings.data, runtimeSettings)
    : false;
  const activationDecision = runtimeSettings
    ? runtimeSettingsActivationDecision(runtimeSettings, settings.data)
    : null;

  return (
    <div className="page-stack">
      <Panel
        title="VM resources"
        actions={
          <ConfirmButton
            confirmMessage="Apply runtime settings? This may update launchd services, rewrite runtime configuration, and restart the VM runtime only when a changed setting requires it and activation after save is enabled."
            onClick={apply}
            disabled={!canApply}
          >
            Apply
          </ConfirmButton>
        }
      >
        {settings.isError ? (
          <ErrorState title="Failed to read settings" error={settings.error} />
        ) : null}
        {settings.data?.readIssues?.length ? (
          <div className="warning-list">
            <strong>Settings read issues</strong>
            {settings.data.readIssues.map((issue) => (
              <div key={issue.source}>
                {issue.source}: {issue.message}
              </div>
            ))}
          </div>
        ) : null}

        <div className="settings-grid">
          <label>
            CPU cores
            <input
              type="number"
              min="1"
              value={draft.cpuCount}
              disabled={!canEditVMResources}
              onChange={(event) => updateField("cpuCount", event.target.value)}
            />
          </label>
          <label>
            Memory GiB
            <input
              type="number"
              min="1"
              step="0.5"
              value={draft.memoryGiB}
              disabled={!canEditVMResources}
              onChange={(event) => updateField("memoryGiB", event.target.value)}
            />
          </label>
          <label>
            VM disk GiB
            <input
              type="number"
              min={settings.data.minimumDiskGiB}
              value={draft.diskGiB}
              disabled={!canEditVMResources}
              onChange={(event) => updateField("diskGiB", event.target.value)}
            />
          </label>
        </div>
        <p className="muted">
          VM disk can only be increased. Minimum for this install is{" "}
          {settings.data.minimumDiskGiB} GiB.
        </p>
      </Panel>

      <Panel title="Network exposure">
        <div className="settings-grid">
          <label>
            VitalServer listen port
            <input
              type="number"
              min="1"
              max="65535"
              value={draft.proxyPort}
              disabled={!canEditNetworkExposure}
              onChange={(event) => updateField("proxyPort", event.target.value)}
            />
          </label>
          <label>
            Remote Console port
            <input
              type="number"
              min="1"
              max="65535"
              value={draft.runtimeControlPort}
              disabled={!canEditNetworkExposure}
              onChange={(event) =>
                updateField("runtimeControlPort", event.target.value)
              }
            />
          </label>
        </div>
        <p className="muted">
          VitalServer URL: {vitalServerURLPreview}
        </p>
        <p className="muted">Remote Console: {runtimeControlURLPreview}</p>
        <label className="checkbox-label block-checkbox">
          <input
            type="checkbox"
            checked={customAdvertisedURL}
            disabled={!canEditNetworkExposure}
            onChange={(event) => setCustomAdvertisedURL(event.target.checked)}
          />
          Custom advertised URL
        </label>
        <p className="muted">
          Enable this only when clients must connect through a different host or
          port than the Mac listener, such as an external reverse proxy.
        </p>
        {customAdvertisedURL ? (
          <div className="settings-grid">
            <label>
              Custom advertised host
              <input
                type="text"
                value={draft.publicHost}
                disabled={!canEditNetworkExposure}
                onChange={(event) => updateField("publicHost", event.target.value)}
              />
            </label>
            <label>
              Advertised port
              <input
                type="number"
                min="1"
                max="65535"
                value={draft.publicPort}
                disabled={!canEditNetworkExposure}
                onChange={(event) => updateField("publicPort", event.target.value)}
              />
            </label>
          </div>
        ) : (
          <p className="muted">
            Default advertised URL: {defaultAdvertisedURLPreview}
          </p>
        )}
      </Panel>

      <Panel title="Recorder load control">
        <div className="settings-grid">
          <label className="checkbox-label">
            <input
              type="checkbox"
              checked={draft.recorderIngressLoadControlEnabled}
              disabled={!canControlServices}
              onChange={(event) =>
                updateField(
                  "recorderIngressLoadControlEnabled",
                  event.target.checked
                )
              }
            />
            Recorder load control
          </label>
          <label>
            Max replay throughput
            <input
              type="number"
              min="0"
              max="100"
              step="5"
              value={draft.recorderIngressSendDataReplayMaxMiBPerSecond}
              disabled={
                !canControlServices || !draft.recorderIngressLoadControlEnabled
              }
              onChange={(event) =>
                updateReplayThroughput(event.target.value)
              }
              onBlur={normalizeReplayThroughput}
            />
          </label>
          <label className="checkbox-label">
            <input
              type="checkbox"
              checked={draft.containerMemoryLimitsEnabled}
              disabled={!canControlServices}
              onChange={(event) =>
                updateField("containerMemoryLimitsEnabled", event.target.checked)
              }
            />
            Container memory limits
          </label>
          <p className="muted full-width">
            Container limit total: {containerMemoryLimitTotalPercent}% /{" "}
            {containerMemoryLimitRanges.maxCombinedPercent}% of VM memory
          </p>
          <label>
            VitalServer limit:{" "}
            {containerMemoryLimitPercent(
              draft.vitalServerContainerMemoryLimitMiB,
              containerMemoryLimitVMMaxMiB
            )}
            % ({draft.vitalServerContainerMemoryLimitMiB} MiB)
            <input
              type="range"
              min={
                containerMemoryLimitPercentRange(
                  containerMemoryLimitRanges.vitalServer,
                  containerMemoryLimitVMMaxMiB
                ).min
              }
              max={
                containerMemoryLimitPercentRange(
                  containerMemoryLimitRanges.vitalServer,
                  containerMemoryLimitVMMaxMiB
                ).max
              }
              step={containerMemoryLimitRanges.stepPercent}
              value={containerMemoryLimitPercent(
                draft.vitalServerContainerMemoryLimitMiB,
                containerMemoryLimitVMMaxMiB
              )}
              disabled={!canControlServices || !draft.containerMemoryLimitsEnabled}
              onChange={(event) =>
                updateContainerMemoryLimitPercent(
                  "vitalServerContainerMemoryLimitMiB",
                  Number(event.target.value),
                  containerMemoryLimitRanges.vitalServer
                )
              }
            />
          </label>
          <label>
            Recorder ingress limit:{" "}
            {containerMemoryLimitPercent(
              draft.recorderIngressContainerMemoryLimitMiB,
              containerMemoryLimitVMMaxMiB
            )}
            % ({draft.recorderIngressContainerMemoryLimitMiB} MiB)
            <input
              type="range"
              min={
                containerMemoryLimitPercentRange(
                  containerMemoryLimitRanges.recorderIngress,
                  containerMemoryLimitVMMaxMiB
                ).min
              }
              max={
                containerMemoryLimitPercentRange(
                  containerMemoryLimitRanges.recorderIngress,
                  containerMemoryLimitVMMaxMiB
                ).max
              }
              step={containerMemoryLimitRanges.stepPercent}
              value={containerMemoryLimitPercent(
                draft.recorderIngressContainerMemoryLimitMiB,
                containerMemoryLimitVMMaxMiB
              )}
              disabled={!canControlServices || !draft.containerMemoryLimitsEnabled}
              onChange={(event) =>
                updateContainerMemoryLimitPercent(
                  "recorderIngressContainerMemoryLimitMiB",
                  Number(event.target.value),
                  containerMemoryLimitRanges.recorderIngress
                )
              }
            />
          </label>
          <label>
            Redis limit:{" "}
            {containerMemoryLimitPercent(
              draft.redisContainerMemoryLimitMiB,
              containerMemoryLimitVMMaxMiB
            )}
            % ({draft.redisContainerMemoryLimitMiB} MiB)
            <input
              type="range"
              min={
                containerMemoryLimitPercentRange(
                  containerMemoryLimitRanges.redis,
                  containerMemoryLimitVMMaxMiB
                ).min
              }
              max={
                containerMemoryLimitPercentRange(
                  containerMemoryLimitRanges.redis,
                  containerMemoryLimitVMMaxMiB
                ).max
              }
              step={containerMemoryLimitRanges.stepPercent}
              value={containerMemoryLimitPercent(
                draft.redisContainerMemoryLimitMiB,
                containerMemoryLimitVMMaxMiB
              )}
              disabled={!canControlServices || !draft.containerMemoryLimitsEnabled}
              onChange={(event) =>
                updateContainerMemoryLimitPercent(
                  "redisContainerMemoryLimitMiB",
                  Number(event.target.value),
                  containerMemoryLimitRanges.redis
                )
              }
            />
          </label>
        </div>
        <p className="muted">
          Load control queues recorder send_data and replays payloads to
          VitalServer at a controlled throughput. Throughput is configured in
          MiB/s. Container memory limits are hard Docker limits configured in
          MiB. These changes are applied when container services are reconciled.
        </p>
      </Panel>

      <Panel title="Storage and VitalServer Helper backups">
        <p className={settingsApplyStateClassName(backupSettingsPending)}>
          {backupAppliedState}
        </p>
        <div className="settings-grid">
          <label>
            Vital files directory
            <input
              type="text"
              value={draft.vitalFilesDirectory}
              disabled={!canEditLocalFiles}
              onChange={(event) =>
                updateField("vitalFilesDirectory", event.target.value)
              }
            />
          </label>
          <label className="checkbox-label">
            <input
              type="checkbox"
              checked={draft.automaticBackupEnabled}
              disabled={!canControlServices}
              onChange={(event) =>
                updateField("automaticBackupEnabled", event.target.checked)
              }
            />
            Automatic backups
          </label>
          <p className="muted full-width">
            Schedule timezone: {systemTimeZone} (system local time).
          </p>
          <label>
            Backup times
            <input
              value={draft.backupScheduleTimes}
              disabled={!canControlServices}
              placeholder="03:15, 15:15"
              pattern="^([01][0-9]|2[0-3]):[0-5][0-9](,\s*([01][0-9]|2[0-3]):[0-5][0-9])*$"
              onChange={(event) =>
                updateField("backupScheduleTimes", event.target.value)
              }
            />
          </label>
          <label>
            Backup archives
            <input
              type="number"
              min="1"
              max="30"
              value={draft.backupRetentionCount}
              disabled={!canControlServices}
              onChange={(event) =>
                updateField("backupRetentionCount", event.target.value)
              }
            />
          </label>
        </div>

        <p className="muted">
          Backup times use 24-hour HH:mm format, such as 03:15 or 15:15, and
          each time must be unique.{" "}
          VitalServer Helper backup retention keeps up to 30 recoverable archives,
          including Redis data.
        </p>
      </Panel>

      <Panel title="Logs">
        <p className={settingsApplyStateClassName(logArchiveSettingsPending)}>
          {logArchiveAppliedState}
        </p>
        <div className="settings-grid">
          <label>
            Log archive retention
            <input
              type="number"
              min="1"
              max="30"
              value={draft.logArchiveRetentionDays}
              disabled={!canControlServices}
              onChange={(event) =>
                updateField("logArchiveRetentionDays", event.target.value)
              }
            />
          </label>
          <label>
            Log archive size limit
            <input
              type="number"
              min="1"
              max="20"
              value={draft.logArchiveMaximumGiB}
              disabled={!canControlServices}
              onChange={(event) =>
                updateField("logArchiveMaximumGiB", event.target.value)
              }
            />
          </label>
        </div>

        <p className="muted">
          Managed YYYY-MM-DD log archive folders are pruned by age first, then by
          total size. Non-date folders are not automatically removed.
        </p>
      </Panel>

      <Panel title="Operations">
        <div className="settings-toggles">
          <label className="checkbox-label">
            <input
              type="checkbox"
              checked={draft.startOnBoot}
              disabled={!startOnBootControl.enabled}
              onChange={(event) =>
                updateField("startOnBoot", event.target.checked)
              }
            />
            Start on boot
          </label>
          <label className="checkbox-label">
            <input
              type="checkbox"
              checked={draft.autoRecoveryEnabled}
              disabled={!canControlServices}
              onChange={(event) =>
                updateField("autoRecoveryEnabled", event.target.checked)
              }
            />
            Auto recovery
          </label>
          <label className="checkbox-label">
            <input
              type="checkbox"
              checked={draft.preventSystemSleep}
              disabled={!canControlServices}
              onChange={(event) =>
                updateField("preventSystemSleep", event.target.checked)
              }
            />
            Prevent system sleep
          </label>
          <label className="checkbox-label">
            <input
              type="checkbox"
              checked={draft.restartAfterSave}
              disabled={!canControlServices}
              onChange={(event) =>
                updateField("restartAfterSave", event.target.checked)
              }
            />
            Activate required runtime changes after save
          </label>
        </div>
        {!startOnBootControl.enabled ? (
          <p className="muted">{startOnBootControl.reason}</p>
        ) : null}

        {validation.errors.length ? (
          <div className="error-state">
            <strong>Settings need attention</strong>
            {validation.errors.map((error) => (
              <span key={error}>{error}</span>
            ))}
          </div>
        ) : null}

        {applySettings.isError ? (
          <ErrorState
            title="Failed to apply settings"
            error={applySettings.error}
          />
        ) : null}
        {applySettings.data ? (
          <p className="muted">
            Settings applied. Exit code{" "}
            {applySettings.data.result?.exitCode ?? "unknown"}.
          </p>
        ) : null}
        {changedRuntimeControlPort !== null ? (
          <p className="muted">
            Remote Console port changed to {changedRuntimeControlPort}. Open the
            Remote Console on the configured host after the Runtime Control API
            is available on the new port.
          </p>
        ) : null}
      </Panel>

      <Panel title="Change activation">
        {activationDecision ? (
          <>
            <p
              className={settingsApplyStateClassName(
                activationDecision.requiresActivation
              )}
            >
              {activationDecision.message}
            </p>
            {activationDecision.requiresVMRestart ? (
              <p className="muted">
                Requires VM restart. Required by:{" "}
                {activationDecision.vmRestartChanges.join(", ")}.
              </p>
            ) : null}
            {activationDecision.requiresContainerServicesReconcile ? (
              <p className="muted">
                Requires container reconcile. Required by:{" "}
                {activationDecision.containerServiceChanges.join(", ")}.
              </p>
            ) : null}
          </>
        ) : (
          <p className="muted">Runtime activation state is not available.</p>
        )}
      </Panel>
    </div>
  );
}

function currentBrowserHostname(): string | undefined {
  return globalThis.location?.hostname;
}

function normalizeReplayThroughputValue(value: string): string {
  const parsed = parseOptionalNumber(value);
  if (parsed === undefined || parsed <= 1) {
    return "1";
  }
  return String(Math.min(100, Math.max(5, Math.round(parsed / 5) * 5)));
}

function draftMemoryMiB(draft: RuntimeSettingsDraft, fallbackMemoryGiB: number): number {
  return Math.max((parseOptionalNumber(draft.memoryGiB) ?? fallbackMemoryGiB) * 1024, 1);
}

function normalizeContainerMemoryLimitDraft(
  draft: RuntimeSettingsDraft,
  vmMiB: number
): RuntimeSettingsDraft {
  if (!draft.containerMemoryLimitsEnabled) {
    return draft;
  }
  let next = { ...draft };
  for (const field of [
    "vitalServerContainerMemoryLimitMiB",
    "redisContainerMemoryLimitMiB",
    "recorderIngressContainerMemoryLimitMiB"
  ] as const) {
    const surplus =
      containerMemoryLimitDraftTotalPercent(next, vmMiB) -
      containerMemoryLimitRanges.maxCombinedPercent;
    if (surplus <= 0) {
      return next;
    }
    const range = containerMemoryLimitRangeForField(field);
    const currentPercent = containerMemoryLimitPercent(next[field], vmMiB);
    const minimumPercent = containerMemoryLimitPercentRange(range, vmMiB).min;
    const nextPercent = Math.max(minimumPercent, currentPercent - surplus);
    next = {
      ...next,
      [field]: String(containerMemoryLimitMiB(nextPercent, range, vmMiB))
    };
  }
  return next;
}

function enableContainerReconcileActivationWhenNeeded(
  draft: RuntimeSettingsDraft,
  runtime: Parameters<typeof draftToRuntimeSettings>[1],
  customAdvertisedURL: boolean
): RuntimeSettingsDraft {
  const candidate = draftToRuntimeSettings(draft, runtime, customAdvertisedURL);
  const decision = runtimeSettingsActivationDecision(candidate, runtime);
  if (
    decision.requiresContainerServicesReconcile &&
    !decision.requiresVMRestart
  ) {
    return { ...draft, restartAfterSave: true };
  }
  return draft;
}

function containerMemoryLimitRangeForField(
  field:
    | "vitalServerContainerMemoryLimitMiB"
    | "recorderIngressContainerMemoryLimitMiB"
    | "redisContainerMemoryLimitMiB"
): { minMiB: number; maxMiB: number } {
  if (field === "recorderIngressContainerMemoryLimitMiB") {
    return containerMemoryLimitRanges.recorderIngress;
  }
  if (field === "redisContainerMemoryLimitMiB") {
    return containerMemoryLimitRanges.redis;
  }
  return containerMemoryLimitRanges.vitalServer;
}

function runtimeContainerLimitTotalPercent(settings: {
  memoryGiB: number;
  vitalServerContainerMemoryLimitMiB: number;
  recorderIngressContainerMemoryLimitMiB: number;
  redisContainerMemoryLimitMiB: number;
}): number {
  const vmMiB = Math.max(settings.memoryGiB * 1024, 1);
  return Math.round(
    ((settings.vitalServerContainerMemoryLimitMiB +
      settings.recorderIngressContainerMemoryLimitMiB +
      settings.redisContainerMemoryLimitMiB) /
      vmMiB) *
      100
  );
}

function containerMemoryLimitDraftTotalPercent(
  draft: RuntimeSettingsDraft,
  vmMiB: number
): number {
  return (
    containerMemoryLimitPercent(draft.vitalServerContainerMemoryLimitMiB, vmMiB) +
    containerMemoryLimitPercent(draft.recorderIngressContainerMemoryLimitMiB, vmMiB) +
    containerMemoryLimitPercent(draft.redisContainerMemoryLimitMiB, vmMiB)
  );
}

function containerMemoryLimitPercent(value: string, vmMiB: number): number {
  const valueMiB = parseOptionalNumber(value) ?? 0;
  return Math.round((valueMiB / Math.max(vmMiB, 1)) * 100);
}

function containerMemoryLimitMiB(
  percent: number,
  range: { minMiB: number; maxMiB: number },
  vmMiB: number
): number {
  const valueMiB = Math.round((Math.max(vmMiB, 1) * percent) / 100);
  return Math.min(Math.max(valueMiB, range.minMiB), Math.min(range.maxMiB, vmMiB));
}

function containerMemoryLimitPercentRange(
  range: { minMiB: number; maxMiB: number },
  vmMiB: number
): { min: number; max: number } {
  const safeVMMiB = Math.max(vmMiB, 1);
  const min = Math.max(1, Math.ceil((range.minMiB / safeVMMiB) * 100));
  const max = Math.max(
    min,
    Math.min(100, Math.floor((Math.min(range.maxMiB, safeVMMiB) / safeVMMiB) * 100))
  );
  return { min, max };
}

function changedRuntimeControlPortValue(
  runtimeControlPort: number | undefined
): number | null {
  if (
    runtimeControlPort === undefined ||
    typeof window === "undefined" ||
    window.location.port === String(runtimeControlPort)
  ) {
    return null;
  }

  return runtimeControlPort;
}

function backupAppliedSettingsSummary(
  applied: RuntimeSettingsDraftSource,
  draft: RuntimeSettingsDraftSource,
  systemTimeZone: string
): string {
  const prefix = backupSettingsChanged(applied, draft)
    ? "Not applied yet. Applied"
    : "Applied";
  const automaticBackupText = applied.automaticBackupEnabled
    ? "Automatic backups on"
    : "Automatic backups off";
  const scheduleTimes = applied.backupScheduleTimes.join(", ");

  return `${prefix}: ${automaticBackupText} · ${scheduleTimes} · ${systemTimeZone} · keep ${applied.backupRetentionCount} archives`;
}

function logArchiveAppliedSettingsSummary(
  applied: RuntimeSettingsDraftSource,
  draft: RuntimeSettingsDraftSource
): string {
  const prefix = logArchiveSettingsChanged(applied, draft)
    ? "Not applied yet. Applied"
    : "Applied";

  return `${prefix}: keep ${applied.logArchiveRetentionDays} days · max ${applied.logArchiveMaximumGiB} GiB`;
}

function backupSettingsChanged(
  applied: RuntimeSettingsDraftSource,
  draft: RuntimeSettingsDraftSource
): boolean {
  return (
    applied.automaticBackupEnabled !== draft.automaticBackupEnabled ||
    applied.backupRetentionCount !== draft.backupRetentionCount ||
    applied.backupScheduleTimes.join("\n") !== draft.backupScheduleTimes.join("\n")
  );
}

function logArchiveSettingsChanged(
  applied: RuntimeSettingsDraftSource,
  draft: RuntimeSettingsDraftSource
): boolean {
  return (
    applied.logArchiveRetentionDays !== draft.logArchiveRetentionDays ||
    applied.logArchiveMaximumGiB !== draft.logArchiveMaximumGiB
  );
}

function settingsApplyStateClassName(pending: boolean): string {
  return pending ? "settings-apply-state pending" : "settings-apply-state";
}

type RuntimeSettingsDraftSource = {
  automaticBackupEnabled: boolean;
  backupScheduleTimes: string[];
  backupRetentionCount: number;
  logArchiveRetentionDays: number;
  logArchiveMaximumGiB: number;
};
