import { useEffect, useState } from "react";

import {
  useApplyRuntimeAdminPassword,
  useApplyRuntimePlatformSettings,
  useApplyRuntimeRedisRelaySettings,
  useApplyRuntimeProductSettings,
  useControlCapabilities,
  useRuntimeProductSettings,
  useRuntimePlatformSettings,
  useRuntimeRedisRelaySettings
} from "@/console/hooks";
import {
  canApplyRuntimeProductSettings,
  canApplyRuntimeAdminPassword,
  canApplyRuntimeRedisRelaySettings
} from "@/domain/runtime-control/capabilities/runtimeCapabilities";
import type {
  RuntimeProductSettings,
  RuntimePlatformSettings,
  RuntimeRedisRelaySettingsApplyRequest
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import { ConfirmButton } from "@/components/ConfirmButton";
import { CommandResult } from "@/components/CommandResult";
import { ErrorState } from "@/components/ErrorState";
import { Panel } from "@/components/Panel";

type Draft = {
  settings: RuntimeProductSettings;
  recorderIngressJSON: string;
  backupScheduleText: string;
};

type RedisRelayDraft = RuntimeRedisRelaySettingsApplyRequest;

export function SettingsPage() {
  const read = useRuntimeProductSettings();
  const apply = useApplyRuntimeProductSettings();
  const applyAdminPassword = useApplyRuntimeAdminPassword();
  const relayRead = useRuntimeRedisRelaySettings();
  const applyRelay = useApplyRuntimeRedisRelaySettings();
  const capabilities = useControlCapabilities();
  const [draft, setDraft] = useState<Draft | null>(null);
  const [adminPassword, setAdminPassword] = useState("");
  const [relayDraft, setRelayDraft] = useState<RedisRelayDraft | null>(null);

  useEffect(() => {
    const settings = read.data?.state === "loaded" ? read.data.settings : null;
    setDraft(settings ? toDraft(settings) : null);
  }, [read.data]);

  useEffect(() => {
    const settings = relayRead.data?.state === "loaded" ? relayRead.data.settings : null;
    setRelayDraft(
      settings
        ? {
            ...settings,
            target: {
              url: settings.target.url,
              username: settings.target.username,
              password: "",
              clearPassword: false,
              tls: settings.target.tls
            }
          }
        : null
    );
  }, [relayRead.data]);

  if (read.isPending) {
    return (
      <div className="page-stack">
        <PlatformSettingsPanel />
        <Panel title="Runtime product settings">Loading runtime settings...</Panel>
      </div>
    );
  }
  if (read.isError) {
    return (
      <div className="page-stack">
        <PlatformSettingsPanel />
        <Panel title="Runtime product settings">
          <ErrorState title="Failed to read runtime settings" error={read.error} />
        </Panel>
      </div>
    );
  }
  if (read.data?.state !== "loaded" || !read.data.settings || !draft) {
    return (
      <div className="page-stack">
        <PlatformSettingsPanel />
        <Panel title="Runtime product settings">
          <ErrorState
            title="Runtime settings are unavailable"
            error={new Error(read.data?.readError ?? "Runtime settings were not reported.")}
          />
        </Panel>
      </div>
    );
  }

  const parsed = parsedSettings(draft);
  const validationError = parsed instanceof Error ? parsed.message : null;
  const canApplyProductSettings = canApplyRuntimeProductSettings(
    capabilities.data
  );
  const update = <K extends keyof RuntimeProductSettings>(
    field: K,
    value: RuntimeProductSettings[K]
  ) => {
    setDraft((current) =>
      current
        ? { ...current, settings: { ...current.settings, [field]: value } }
        : current
    );
  };

  return (
    <div className="page-stack">
      <PlatformSettingsPanel />
      <Panel
        title="Runtime product settings"
        actions={
          <ConfirmButton
            confirmMessage="Apply product runtime settings and reconcile the Compose stack?"
            disabled={
              !canApplyProductSettings ||
              parsed instanceof Error ||
              apply.isPending
            }
            onClick={() => {
              if (canApplyProductSettings && !(parsed instanceof Error)) {
                apply.mutate({ settings: parsed });
              }
            }}
          >
            Apply
          </ConfirmButton>
        }
      >
        <p className="muted">
          These settings belong to the Runtime Controller and are identical on
          macOS, Windows, and Linux. VM, OS service, proxy-listener, and local
          filesystem settings belong to the Platform Agent.
        </p>
        {read.data.readError ? (
          <ErrorState title="Runtime settings read issue" error={new Error(read.data.readError)} />
        ) : null}
        {apply.error ? (
          <ErrorState title="Runtime settings apply failed" error={apply.error} />
        ) : null}
        {validationError ? <p className="form-error">{validationError}</p> : null}
      </Panel>

      <Panel title="Advertised product endpoints">
        <div className="settings-grid">
          <TextField
            label="VitalServer URL"
            value={draft.settings.vitalServerURL}
            onChange={(value) => update("vitalServerURL", value)}
          />
          <TextField
            label="Remote Console URL"
            value={draft.settings.remoteConsoleURL}
            onChange={(value) => update("remoteConsoleURL", value)}
          />
          <TextField
            label="Advertised host"
            value={draft.settings.publicHost}
            onChange={(value) => update("publicHost", value)}
          />
          <NumberField
            label="Advertised port"
            value={draft.settings.publicPort}
            onChange={(value) => update("publicPort", value)}
            max={65535}
          />
        </div>
      </Panel>

      <Panel title="Recorder load control">
        <div className="settings-grid">
          <label>
            Send-data mode
            <select
              value={draft.settings.recorderIngressSendDataMode}
              onChange={(event) =>
                update(
                  "recorderIngressSendDataMode",
                  event.target.value as RuntimeProductSettings["recorderIngressSendDataMode"]
                )
              }
            >
              <option value="passthrough">passthrough</option>
              <option value="mirror_spool">mirror_spool</option>
              <option value="spool_only">spool_only</option>
              <option value="spool_and_replay">spool_and_replay</option>
            </select>
          </label>
          <NumberField
            label="Replay batch size"
            value={draft.settings.recorderIngressSendDataReplayBatchSize}
            onChange={(value) => update("recorderIngressSendDataReplayBatchSize", value)}
          />
          <NumberField
            label="Replay limit MiB/s"
            value={draft.settings.recorderIngressSendDataReplayMaxMiBPerSecond}
            onChange={(value) =>
              update("recorderIngressSendDataReplayMaxMiBPerSecond", value)
            }
          />
        </div>
        <label>
          Recorder ingress advanced settings
          <textarea
            rows={18}
            value={draft.recorderIngressJSON}
            onChange={(event) =>
              setDraft((current) =>
                current ? { ...current, recorderIngressJSON: event.target.value } : current
              )
            }
          />
        </label>
      </Panel>

      <Panel title="Container memory limits">
        <label className="checkbox-label block-checkbox">
          <input
            type="checkbox"
            checked={draft.settings.containerMemoryLimitsEnabled}
            onChange={(event) =>
              update("containerMemoryLimitsEnabled", event.target.checked)
            }
          />
          Apply explicit Compose container memory limits
        </label>
        <div className="settings-grid">
          <NumberField
            label="VitalServer MiB"
            value={draft.settings.vitalServerContainerMemoryLimitMiB}
            onChange={(value) => update("vitalServerContainerMemoryLimitMiB", value)}
          />
          <NumberField
            label="Recorder ingress MiB"
            value={draft.settings.recorderIngressContainerMemoryLimitMiB}
            onChange={(value) =>
              update("recorderIngressContainerMemoryLimitMiB", value)
            }
          />
          <NumberField
            label="Redis MiB"
            value={draft.settings.redisContainerMemoryLimitMiB}
            onChange={(value) => update("redisContainerMemoryLimitMiB", value)}
          />
        </div>
      </Panel>

      <Panel title="Runtime backups">
        <label className="checkbox-label block-checkbox">
          <input
            type="checkbox"
            checked={draft.settings.automaticBackupEnabled}
            onChange={(event) => update("automaticBackupEnabled", event.target.checked)}
          />
          Automatic Runtime backup
        </label>
        <div className="settings-grid">
          <TextField
            label="Schedule times"
            value={draft.backupScheduleText}
            onChange={(value) =>
              setDraft((current) =>
                current ? { ...current, backupScheduleText: value } : current
              )
            }
          />
          <NumberField
            label="Retention count"
            value={draft.settings.backupRetentionCount}
            onChange={(value) => update("backupRetentionCount", value)}
          />
        </div>
        <p className="muted">Enter schedule times separated by commas, for example 03:15, 15:15.</p>
      </Panel>

      <Panel
        title="Redis Relay"
        actions={
          <ConfirmButton
            confirmMessage="Apply Redis Relay settings and reconcile the Runtime stack?"
            disabled={
              !relayDraft ||
              !canApplyRuntimeRedisRelaySettings(capabilities.data) ||
              applyRelay.isPending
            }
            onClick={() => {
              if (relayDraft) {
                applyRelay.mutate(relayDraft);
              }
            }}
          >
            Apply relay
          </ConfirmButton>
        }
      >
        <p className="muted">
          Redis Relay configuration and its secret belong to the Runtime Controller.
          The configured password is reported only as present or absent.
        </p>
        {relayRead.isPending ? <p>Loading Redis Relay settings...</p> : null}
        {relayRead.isError ? (
          <ErrorState title="Redis Relay settings read failed" error={relayRead.error} />
        ) : null}
        {relayRead.data?.state !== "loaded" && relayRead.data?.readError ? (
          <ErrorState
            title="Redis Relay settings are unavailable"
            error={new Error(relayRead.data.readError)}
          />
        ) : null}
        {relayDraft ? (
          <>
            <label className="checkbox-label block-checkbox">
              <input
                type="checkbox"
                checked={relayDraft.enabled}
                onChange={(event) =>
                  setRelayDraft({ ...relayDraft, enabled: event.target.checked })
                }
              />
              Enable Redis Relay
            </label>
            <div className="settings-grid">
              <TextField
                label="Target URL"
                value={relayDraft.target.url}
                onChange={(url) =>
                  setRelayDraft({
                    ...relayDraft,
                    target: { ...relayDraft.target, url }
                  })
                }
              />
              <TextField
                label="Target username"
                value={relayDraft.target.username}
                onChange={(username) =>
                  setRelayDraft({
                    ...relayDraft,
                    target: { ...relayDraft.target, username }
                  })
                }
              />
              <label>
                New target password
                <input
                  type="password"
                  autoComplete="new-password"
                  value={relayDraft.target.password ?? ""}
                  onChange={(event) =>
                    setRelayDraft({
                      ...relayDraft,
                      target: {
                        ...relayDraft.target,
                        password: event.target.value,
                        clearPassword: false
                      }
                    })
                  }
                />
              </label>
              <label>
                Scope
                <select
                  value={relayDraft.scope}
                  onChange={(event) =>
                    setRelayDraft({
                      ...relayDraft,
                      scope: event.target.value as RedisRelayDraft["scope"]
                    })
                  }
                >
                  <option value="vital_reconstruction">vital reconstruction</option>
                  <option value="waveform_trend_only">waveform/trend only</option>
                </select>
              </label>
              <NumberField
                label="Interval seconds"
                value={relayDraft.intervalSeconds}
                onChange={(intervalSeconds) =>
                  setRelayDraft({ ...relayDraft, intervalSeconds })
                }
                min={0.1}
              />
              <NumberField
                label="Scan count"
                value={relayDraft.scanCount}
                onChange={(scanCount) => setRelayDraft({ ...relayDraft, scanCount })}
              />
            </div>
            <label className="checkbox-label block-checkbox">
              <input
                type="checkbox"
                checked={relayDraft.target.tls}
                onChange={(event) =>
                  setRelayDraft({
                    ...relayDraft,
                    target: { ...relayDraft.target, tls: event.target.checked }
                  })
                }
              />
              Use TLS
            </label>
            <label className="checkbox-label block-checkbox">
              <input
                type="checkbox"
                checked={relayDraft.includeRecorderNetworkContext}
                onChange={(event) =>
                  setRelayDraft({
                    ...relayDraft,
                    includeRecorderNetworkContext: event.target.checked
                  })
                }
              />
              Include recorder network context
            </label>
            <label className="checkbox-label block-checkbox">
              <input
                type="checkbox"
                checked={relayDraft.target.clearPassword}
                onChange={(event) =>
                  setRelayDraft({
                    ...relayDraft,
                    target: {
                      ...relayDraft.target,
                      password: "",
                      clearPassword: event.target.checked
                    }
                  })
                }
              />
              Clear configured target password
            </label>
            <p className="muted">
              Password currently configured: {relayRead.data?.settings?.target.passwordConfigured ? "yes" : "no"}
            </p>
          </>
        ) : null}
        {applyRelay.error ? (
          <ErrorState title="Redis Relay settings apply failed" error={applyRelay.error} />
        ) : null}
      </Panel>

      <Panel title="Runtime administrator password">
        <p className="muted">
          The password is sent only to the Runtime Controller, is never returned
          by a read API, and is not stored in this page after a successful change.
        </p>
        <div className="inline-form">
          <label>
            New administrator password
            <input
              type="password"
              autoComplete="new-password"
              value={adminPassword}
              onChange={(event) => setAdminPassword(event.target.value)}
            />
          </label>
          <ConfirmButton
            confirmMessage="Replace the VitalServer administrator password and reconcile the Runtime stack?"
            disabled={
              !canApplyRuntimeAdminPassword(capabilities.data) ||
              adminPassword.length === 0 ||
              adminPassword.includes("\n") ||
              adminPassword.includes("\r") ||
              applyAdminPassword.isPending
            }
            onClick={() =>
              applyAdminPassword.mutate(
                { password: adminPassword },
                { onSuccess: () => setAdminPassword("") }
              )
            }
          >
            Replace password
          </ConfirmButton>
        </div>
        {applyAdminPassword.data ? (
          <p className="muted">
            Operation {applyAdminPassword.data.operationId}: {applyAdminPassword.data.state}
          </p>
        ) : null}
        {applyAdminPassword.error ? (
          <ErrorState
            title="Administrator password change failed"
            error={applyAdminPassword.error}
          />
        ) : null}
      </Panel>
    </div>
  );
}

function PlatformSettingsPanel() {
  const read = useRuntimePlatformSettings();
  const apply = useApplyRuntimePlatformSettings();
  const capabilities = useControlCapabilities();
  const [draft, setDraft] = useState<RuntimePlatformSettings | null>(null);

  useEffect(() => {
    setDraft(read.data?.state === "loaded" ? read.data.settings : null);
  }, [read.data]);

  if (read.isPending) {
    return <Panel title="Platform settings">Loading Platform Agent settings...</Panel>;
  }
  if (read.isError) {
    return (
      <Panel title="Platform settings">
        <ErrorState title="Platform settings are unavailable" error={read.error} />
      </Panel>
    );
  }
  if (read.data?.state !== "loaded" || !draft) {
    return (
      <Panel title="Platform settings">
        <ErrorState
          title="Platform settings are unavailable"
          error={new Error(read.data?.readError ?? "Platform settings were not reported.")}
        />
      </Panel>
    );
  }

  const canApply =
    capabilities.data?.canEditRuntimeProviderResources === true &&
    capabilities.data.canEditNetworkExposure === true;
  const validationError =
    draft.diskGiB < draft.minimumDiskGiB
      ? `Disk must be at least ${draft.minimumDiskGiB} GiB.`
      : draft.networkMode === "bridged" && !draft.bridgedInterface?.trim()
        ? "A bridged interface is required in bridged network mode."
        : null;
  const update = <K extends keyof RuntimePlatformSettings>(
    field: K,
    value: RuntimePlatformSettings[K]
  ) => setDraft((current) => (current ? { ...current, [field]: value } : current));

  return (
    <Panel
      title="Platform settings"
      actions={
        <ConfirmButton
          confirmMessage="Apply Host settings? Runtime Provider resources or listeners may restart."
          disabled={!canApply || validationError !== null || apply.isPending}
          onClick={() => apply.mutate({ settings: platformApplyDocument(draft) })}
        >
          Apply Host settings
        </ConfirmButton>
      }
    >
      <p className="muted">
        These settings are owned by the Platform Agent. macOS currently supports editing;
        Windows and Linux report this contract as unavailable until their Host adapters own it.
      </p>
      {!canApply ? (
        <p className="muted">This Platform Agent reports Host settings as read-only.</p>
      ) : null}
      {validationError ? <p className="form-error">{validationError}</p> : null}
      {read.data.readIssues.map((issue) => (
        <ErrorState key={`${issue.source}:${issue.message}`} title={issue.source} error={new Error(issue.message)} />
      ))}
      <div className="settings-grid">
        <NumberField label="CPU count" value={draft.cpuCount} onChange={(value) => update("cpuCount", value)} />
        <NumberField label="Memory GiB" value={draft.memoryGiB} onChange={(value) => update("memoryGiB", value)} />
        <NumberField label={`Disk GiB (minimum ${draft.minimumDiskGiB})`} value={draft.diskGiB} min={draft.minimumDiskGiB} onChange={(value) => update("diskGiB", value)} />
        <label>
          Network mode
          <select value={draft.networkMode} onChange={(event) => update("networkMode", event.target.value as RuntimePlatformSettings["networkMode"])}>
            <option value="shared">shared</option>
            <option value="bridged">bridged</option>
          </select>
        </label>
        <TextField label="Bridged interface" value={draft.bridgedInterface ?? ""} onChange={(value) => update("bridgedInterface", value.trim() ? value : null)} />
        <NumberField label="Public proxy port" value={draft.proxyPort} max={65535} onChange={(value) => update("proxyPort", value)} />
        <NumberField label="Runtime Control port" value={draft.runtimeControlPort} max={65535} onChange={(value) => update("runtimeControlPort", value)} />
        <TextField label="Vital files directory" value={draft.vitalFilesDirectory} onChange={(value) => update("vitalFilesDirectory", value)} />
        <TextField label="Backup schedule times" value={draft.backupScheduleTimes.join(", ")} onChange={(value) => update("backupScheduleTimes", value.split(",").map((item) => item.trim()).filter(Boolean))} />
        <NumberField label="Backup retention count" value={draft.backupRetentionCount} onChange={(value) => update("backupRetentionCount", value)} />
        <NumberField label="Log retention days" value={draft.logArchiveRetentionDays} onChange={(value) => update("logArchiveRetentionDays", value)} />
        <NumberField label="Maximum log archive GiB" value={draft.logArchiveMaximumGiB} onChange={(value) => update("logArchiveMaximumGiB", value)} />
      </div>
      <div className="settings-grid">
        <SettingsToggle label="Start on boot" checked={draft.startOnBoot} disabled={!draft.startOnBootConfigurable} onChange={(value) => update("startOnBoot", value)} />
        <SettingsToggle label="Automatic recovery" checked={draft.autoRecoveryEnabled} onChange={(value) => update("autoRecoveryEnabled", value)} />
        <SettingsToggle label="Prevent system sleep" checked={draft.preventSystemSleep} onChange={(value) => update("preventSystemSleep", value)} />
        <SettingsToggle label="Automatic backup" checked={draft.automaticBackupEnabled} onChange={(value) => update("automaticBackupEnabled", value)} />
        <SettingsToggle label="Restart after save" checked={draft.restartAfterSave} onChange={(value) => update("restartAfterSave", value)} />
      </div>
      <CommandResult result={apply.data} error={apply.error} emptyText="No Host settings apply has run." />
    </Panel>
  );
}

function platformApplyDocument(settings: RuntimePlatformSettings) {
  return {
    cpuCount: settings.cpuCount,
    memoryGiB: settings.memoryGiB,
    diskGiB: settings.diskGiB,
    networkMode: settings.networkMode,
    bridgedInterface: settings.bridgedInterface,
    proxyPort: settings.proxyPort,
    runtimeControlPort: settings.runtimeControlPort,
    vitalFilesDirectory: settings.vitalFilesDirectory,
    startOnBoot: settings.startOnBoot,
    autoRecoveryEnabled: settings.autoRecoveryEnabled,
    preventSystemSleep: settings.preventSystemSleep,
    automaticBackupEnabled: settings.automaticBackupEnabled,
    backupScheduleTimes: settings.backupScheduleTimes,
    backupRetentionCount: settings.backupRetentionCount,
    logArchiveRetentionDays: settings.logArchiveRetentionDays,
    logArchiveMaximumGiB: settings.logArchiveMaximumGiB,
    restartAfterSave: settings.restartAfterSave
  };
}

function SettingsToggle({
  label,
  checked,
  disabled = false,
  onChange
}: {
  label: string;
  checked: boolean;
  disabled?: boolean;
  onChange: (value: boolean) => void;
}) {
  return (
    <label className="checkbox-label block-checkbox">
      <input type="checkbox" checked={checked} disabled={disabled} onChange={(event) => onChange(event.target.checked)} />
      {label}
    </label>
  );
}

function toDraft(settings: RuntimeProductSettings): Draft {
  return {
    settings,
    recorderIngressJSON: JSON.stringify(settings.recorderIngress, null, 2),
    backupScheduleText: settings.backupScheduleTimes.join(", ")
  };
}

function parsedSettings(draft: Draft): RuntimeProductSettings | Error {
  let recorderIngress: unknown;
  try {
    recorderIngress = JSON.parse(draft.recorderIngressJSON);
  } catch (error) {
    return new Error(`Recorder ingress settings JSON is invalid: ${String(error)}`);
  }
  if (!recorderIngress || typeof recorderIngress !== "object" || Array.isArray(recorderIngress)) {
    return new Error("Recorder ingress settings must be a JSON object.");
  }
  const backupScheduleTimes = draft.backupScheduleText
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  if (backupScheduleTimes.length === 0) {
    return new Error("At least one backup schedule time is required.");
  }
  return {
    ...draft.settings,
    recorderIngress: recorderIngress as RuntimeProductSettings["recorderIngress"],
    backupScheduleTimes
  };
}

function TextField({
  label,
  value,
  onChange
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <label>
      {label}
      <input type="text" value={value} onChange={(event) => onChange(event.target.value)} />
    </label>
  );
}

function NumberField({
  label,
  value,
  onChange,
  max,
  min = 1
}: {
  label: string;
  value: number;
  onChange: (value: number) => void;
  max?: number;
  min?: number;
}) {
  return (
    <label>
      {label}
      <input
        type="number"
        min={min}
        max={max}
        value={value}
        onChange={(event) => onChange(Number(event.target.value))}
      />
    </label>
  );
}
