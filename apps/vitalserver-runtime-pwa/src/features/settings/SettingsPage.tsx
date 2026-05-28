import { useEffect, useState } from "react";

import {
  useApplyRuntimeSettings,
  useRuntimeCapabilities,
  useRuntimeSettings
} from "../../application/runtime-control/queries";
import { canApplyRuntimeSettings } from "../../domain/runtime-control/capabilities/runtimeCapabilities";
import type { RuntimeSettings } from "../../domain/runtime-control/contracts/runtimeControlTypes";
import { validateRuntimeSettings } from "../../domain/runtime-control/settings/runtimeSettingsPolicy";
import { ConfirmButton } from "../../shared/ui/ConfirmButton";
import { ErrorState } from "../../shared/ui/ErrorState";
import { Panel } from "../../shared/ui/Panel";

type SettingsDraft = {
  cpuCount: string;
  memoryGiB: string;
  diskGiB: string;
  proxyPort: string;
  vitalFilesDirectory: string;
  publicHost: string;
  publicPort: string;
  redisBackupRetentionCount: string;
  startOnBoot: boolean;
  autoRecoveryEnabled: boolean;
  preventSystemSleep: boolean;
  restartAfterSave: boolean;
};

const emptyDraft: SettingsDraft = {
  cpuCount: "",
  memoryGiB: "",
  diskGiB: "",
  proxyPort: "",
  vitalFilesDirectory: "",
  publicHost: "",
  publicPort: "",
  redisBackupRetentionCount: "",
  startOnBoot: false,
  autoRecoveryEnabled: false,
  preventSystemSleep: false,
  restartAfterSave: false
};

export function SettingsPage() {
  const settings = useRuntimeSettings();
  const capabilities = useRuntimeCapabilities();
  const applySettings = useApplyRuntimeSettings();
  const [draft, setDraft] = useState<SettingsDraft>(emptyDraft);
  const [customAdvertisedURL, setCustomAdvertisedURL] = useState(false);

  useEffect(() => {
    if (settings.data) {
      setDraft(toDraft(settings.data));
      setCustomAdvertisedURL(usesCustomAdvertisedURL(settings.data));
    }
  }, [settings.data]);

  const updateField = (field: keyof SettingsDraft, value: string | boolean) => {
    setDraft((current) => ({ ...current, [field]: value }));
  };

  const apply = () => {
    const runtimeSettings = toRuntimeSettings(
      draft,
      settings.data,
      customAdvertisedURL
    );
    const validation = validateRuntimeSettings(runtimeSettings);
    if (!validation.valid) {
      return;
    }
    applySettings.mutate({ settings: runtimeSettings });
  };

  const runtimeSettings = toRuntimeSettings(
    draft,
    settings.data,
    customAdvertisedURL
  );
  const validation = validateRuntimeSettings(runtimeSettings);
  const canApply =
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
              min={settings.data?.minimumDiskGiB ?? 1}
              value={draft.diskGiB}
              disabled={!canEditVMResources}
              onChange={(event) => updateField("diskGiB", event.target.value)}
            />
          </label>
        </div>
        {settings.data?.minimumDiskGiB ? (
          <p className="muted">
            VM disk can only be increased. Minimum for this install is{" "}
            {settings.data.minimumDiskGiB} GiB.
          </p>
        ) : null}
      </Panel>

      <Panel title="Network exposure">
        <div className="settings-grid">
          <label>
            Mac listen port
            <input
              type="number"
              min="1"
              max="65535"
              value={draft.proxyPort}
              disabled={!canEditNetworkExposure}
              onChange={(event) => updateField("proxyPort", event.target.value)}
            />
          </label>
        </div>
        <label className="checkbox-label block-checkbox">
          <input
            type="checkbox"
            checked={customAdvertisedURL}
            disabled={!canEditNetworkExposure}
            onChange={(event) => {
              const enabled = event.target.checked;
              setCustomAdvertisedURL(enabled);
              if (!enabled) {
                updateField("publicHost", "");
                updateField("publicPort", draft.proxyPort);
              }
            }}
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
            Default advertised URL: http://(same host):{draft.proxyPort || 80}/
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
              disabled={
                !settings.data?.startOnBootConfigurable || !canControlServices
              }
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
      </Panel>
    </div>
  );
}

function toDraft(settings: RuntimeSettings): SettingsDraft {
  return {
    cpuCount: formatNumber(settings.cpuCount),
    memoryGiB: formatNumber(settings.memoryGiB),
    diskGiB: formatNumber(settings.diskGiB),
    proxyPort: formatNumber(settings.proxyPort),
    vitalFilesDirectory: settings.vitalFilesDirectory ?? "",
    publicHost: settings.publicHost ?? "",
    publicPort: formatNumber(settings.publicPort),
    redisBackupRetentionCount: formatNumber(settings.redisBackupRetentionCount),
    startOnBoot: settings.startOnBoot ?? false,
    autoRecoveryEnabled: settings.autoRecoveryEnabled ?? false,
    preventSystemSleep: settings.preventSystemSleep ?? false,
    restartAfterSave: settings.restartAfterSave ?? false
  };
}

function toRuntimeSettings(
  draft: SettingsDraft,
  current: RuntimeSettings | undefined,
  customAdvertisedURL: boolean
): RuntimeSettings {
  const proxyPort = parseOptionalNumber(draft.proxyPort);
  return {
    cpuCount: parseOptionalNumber(draft.cpuCount),
    memoryGiB: parseOptionalNumber(draft.memoryGiB),
    diskGiB: parseOptionalNumber(draft.diskGiB),
    minimumDiskGiB: current?.minimumDiskGiB,
    proxyPort,
    vitalFilesDirectory: emptyToUndefined(draft.vitalFilesDirectory),
    publicHost: customAdvertisedURL ? emptyToUndefined(draft.publicHost) : undefined,
    publicPort: customAdvertisedURL ? parseOptionalNumber(draft.publicPort) : proxyPort,
    redisBackupRetentionCount: parseOptionalNumber(
      draft.redisBackupRetentionCount
    ),
    startOnBoot: draft.startOnBoot,
    autoRecoveryEnabled: draft.autoRecoveryEnabled,
    preventSystemSleep: draft.preventSystemSleep,
    restartAfterSave: draft.restartAfterSave
  };
}

function formatNumber(value: number | undefined): string {
  return value === undefined ? "" : String(value);
}

function parseOptionalNumber(value: string): number | undefined {
  const trimmed = value.trim();
  if (!trimmed) {
    return undefined;
  }
  const parsed = Number(trimmed);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function emptyToUndefined(value: string): string | undefined {
  const trimmed = value.trim();
  return trimmed ? trimmed : undefined;
}

function usesCustomAdvertisedURL(settings: RuntimeSettings): boolean {
  return Boolean(
    settings.publicHost?.trim() ||
      (settings.publicPort !== undefined && settings.publicPort !== settings.proxyPort)
  );
}
