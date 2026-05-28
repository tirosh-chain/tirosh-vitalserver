import { useEffect, useState } from "react";

import {
  useApplyRuntimeSettings,
  useRuntimeSettings
} from "../../api/queries";
import type { RuntimeSettings } from "../../api/runtimeControlTypes";
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
  preventSystemSleep: false
};

export function SettingsPage() {
  const settings = useRuntimeSettings();
  const applySettings = useApplyRuntimeSettings();
  const [draft, setDraft] = useState<SettingsDraft>(emptyDraft);

  useEffect(() => {
    if (settings.data) {
      setDraft(toDraft(settings.data));
    }
  }, [settings.data]);

  const updateField = (field: keyof SettingsDraft, value: string | boolean) => {
    setDraft((current) => ({ ...current, [field]: value }));
  };

  const apply = () => {
    applySettings.mutate({
      settings: toRuntimeSettings(draft)
    });
  };

  return (
    <div className="page-stack">
      <Panel
        title="Runtime settings"
        actions={
          <button
            type="button"
            onClick={apply}
            disabled={settings.isLoading || applySettings.isPending}
          >
            Apply
          </button>
        }
      >
        {settings.isError ? (
          <p className="error-state">
            Failed to read settings. {String(settings.error)}
          </p>
        ) : null}

        <div className="settings-grid">
          <label>
            CPU cores
            <input
              type="number"
              min="1"
              value={draft.cpuCount}
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
              onChange={(event) => updateField("memoryGiB", event.target.value)}
            />
          </label>
          <label>
            VM disk GiB
            <input
              type="number"
              min="1"
              value={draft.diskGiB}
              onChange={(event) => updateField("diskGiB", event.target.value)}
            />
          </label>
          <label>
            Mac listen port
            <input
              type="number"
              min="1"
              max="65535"
              value={draft.proxyPort}
              onChange={(event) => updateField("proxyPort", event.target.value)}
            />
          </label>
          <label>
            Vital files directory
            <input
              type="text"
              value={draft.vitalFilesDirectory}
              onChange={(event) =>
                updateField("vitalFilesDirectory", event.target.value)
              }
            />
          </label>
          <label>
            Custom advertised host
            <input
              type="text"
              value={draft.publicHost}
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
              onChange={(event) => updateField("publicPort", event.target.value)}
            />
          </label>
          <label>
            Redis backups
            <input
              type="number"
              min="1"
              max="30"
              value={draft.redisBackupRetentionCount}
              onChange={(event) =>
                updateField("redisBackupRetentionCount", event.target.value)
              }
            />
          </label>
        </div>

        <div className="settings-toggles">
          <label className="checkbox-label">
            <input
              type="checkbox"
              checked={draft.startOnBoot}
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
              onChange={(event) =>
                updateField("preventSystemSleep", event.target.checked)
              }
            />
            Prevent system sleep
          </label>
        </div>

        {applySettings.isError ? (
          <p className="error-state">
            Failed to apply settings. {String(applySettings.error)}
          </p>
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
    preventSystemSleep: settings.preventSystemSleep ?? false
  };
}

function toRuntimeSettings(draft: SettingsDraft): RuntimeSettings {
  return {
    cpuCount: parseOptionalNumber(draft.cpuCount),
    memoryGiB: parseOptionalNumber(draft.memoryGiB),
    diskGiB: parseOptionalNumber(draft.diskGiB),
    proxyPort: parseOptionalNumber(draft.proxyPort),
    vitalFilesDirectory: emptyToUndefined(draft.vitalFilesDirectory),
    publicHost: emptyToUndefined(draft.publicHost),
    publicPort: parseOptionalNumber(draft.publicPort),
    redisBackupRetentionCount: parseOptionalNumber(
      draft.redisBackupRetentionCount
    ),
    startOnBoot: draft.startOnBoot,
    autoRecoveryEnabled: draft.autoRecoveryEnabled,
    preventSystemSleep: draft.preventSystemSleep
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
