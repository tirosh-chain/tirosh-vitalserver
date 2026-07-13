import { useInstallInfo, usePlatformState, useReleaseInfo } from "@/console/hooks";
import { DataTable } from "@/components/DataTable";
import { ErrorState } from "@/components/ErrorState";
import { KeyValueRows } from "@/components/KeyValueRows";
import { Panel } from "@/components/Panel";
import { NOT_REPORTED } from "@/domain/runtime-control/formatting/reported";

export function InfoPage() {
  const release = useReleaseInfo();
  const installation = useInstallInfo();
  const platform = usePlatformState();
  const services = release.data?.services ?? [];

  return (
    <div className="page-stack">
      <Panel title="Product information">
        <KeyValueRows
          rows={[
            { label: "Helper version", value: release.data?.helperVersion ?? NOT_REPORTED },
            { label: "Minimum updater version", value: release.data?.minimumUpdaterVersion ?? NOT_REPORTED },
            { label: "VitalServer version", value: release.data?.vitalServerVersion ?? NOT_REPORTED },
            { label: "Installed runtime version", value: platform.data?.installedVersion ?? NOT_REPORTED },
            { label: "Package identifier", value: installation.data?.packageIdentifier ?? NOT_REPORTED }
          ]}
        />
        {release.isError ? <ErrorState title="Release information is unavailable" error={release.error} /> : null}
        {platform.isError ? <ErrorState title="Platform state is unavailable" error={platform.error} /> : null}
        {installation.isError ? <ErrorState title="Installation information is unavailable" error={installation.error} /> : null}
      </Panel>

      <Panel title="Bundled services">
        {release.isPending ? (
          <p className="empty-state">Loading bundled services...</p>
        ) : (
          <DataTable
            rows={services}
            getRowKey={(service) =>
              `${service.name ?? "not-reported"}:${service.image ?? "not-reported"}:${service.version ?? "not-reported"}`
            }
            emptyText="No bundled service metadata was reported."
            columns={[
              { key: "name", header: "Service", render: (service) => service.name ?? NOT_REPORTED },
              { key: "image", header: "Image", render: (service) => service.image ?? NOT_REPORTED },
              { key: "version", header: "Version", render: (service) => service.version ?? NOT_REPORTED }
            ]}
          />
        )}
      </Panel>

      <Panel title="Runtime paths">
        {installation.isPending ? (
          <p className="empty-state">Loading installation paths...</p>
        ) : (
          <KeyValueRows
            rows={[
              { label: "Application bundle", value: installation.data?.appBundlePath ?? NOT_REPORTED },
              { label: "Runtime home", value: installation.data?.runtimeHomePath ?? NOT_REPORTED },
              { label: "Backups", value: installation.data?.backupsPath ?? NOT_REPORTED },
              { label: "Redis backups", value: installation.data?.redisBackupsPath ?? NOT_REPORTED },
              { label: "VitalServer backups", value: installation.data?.runtimeDataBackupsPath ?? NOT_REPORTED }
            ]}
          />
        )}
      </Panel>
    </div>
  );
}
