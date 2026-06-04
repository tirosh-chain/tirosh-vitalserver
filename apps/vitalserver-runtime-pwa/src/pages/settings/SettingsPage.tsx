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
  startOnBootControlState,
  validateRuntimeSettings,
  type RuntimeCapabilityReadState
} from "@/domain/runtime-control/settings/runtimeSettingsPolicy";
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
      setDraft(runtimeSettingsToDraft(settings.data));
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
    setDraft((current) => current && { ...current, [field]: value });
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
              confirmMessage="Apply runtime settings? This may rewrite runtime configuration and restart runtime services when restart after save is enabled."
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
  const runtimeControlURLPreview =
    runtimeControlPort === undefined
      ? "Remote Console port is not available."
      : `Port ${runtimeControlPort}`;
  const defaultAdvertisedURLPreview =
    proxyPort === undefined
      ? "Proxy port is not available."
      : `http://(same host):${proxyPort}/`;
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

  return (
    <div className="page-stack">
      <Panel
        title="VM resources"
        actions={
          <ConfirmButton
            confirmMessage="Apply runtime settings? This may rewrite runtime configuration and restart runtime services when restart after save is enabled."
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

      <Panel title="Storage and Redis data">
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
          <label>
            Redis backups
            <input
              type="number"
              min="1"
              max="30"
              value={draft.redisBackupRetentionCount}
              disabled={!canControlServices}
              onChange={(event) =>
                updateField("redisBackupRetentionCount", event.target.value)
              }
            />
          </label>
        </div>

        <p className="muted">
          Redis backup retention keeps up to 30 recoverable archives.
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
            Restart services after save
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
    </div>
  );
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
