# TS-058: Reset Installer Leaves VM Launchd State Behind

## Symptom

Reset Installer opens the progress command window and shows:

```text
Uninstall failed. Check the log above.
```

The uninstall log may contain:

```text
uninstall process failed exitCode=missing-marker
```

At the same time, `/var/log/install.log` shows the Reset Installer package postinstall still running or failing with `PKInstallErrorDomain Code=112`, and `launchctl print system/ai.tirosh.vitalserver.helper.vm` can still show the VM service as running.

Another form appears after older reset package builds report success. The next `Install VitalServer Helper.pkg` run fails during preinstall with:

```text
fresh install preflight blocked blockers=launchd-service-loaded:label=ai.tirosh.vitalserver.helper.vm,launchd-service-loaded:label=ai.tirosh.vitalserver.helper.sleep-prevention
```

The install preflight can report runtime files, plists, tools, and package receipt as absent while `launchctl print system/ai.tirosh.vitalserver.helper.vm` and `launchctl print system/ai.tirosh.vitalserver.helper.sleep-prevention` still show loaded or running jobs.

## Cause

There are two separate states that older builds could collapse into one confusing message:

- The progress viewer wrote `missing-marker` when its background worker PID disappeared before a completed/failed marker was observed.
- The real cleanup could still be blocked by a VM process that received `SIGTERM` but did not exit. A guest kernel Oops or stale guest runtime state can leave the host VM process alive while runtime health is critical.
- Force clean recovery could observe `pidFileMissing` from Host-owned VM process state and stop before unloading launchd services. That left explicit launchd state behind even though files and package receipts were removed.

The progress viewer and older reset package shared `/private/tmp/tirosh-vitalserver-uninstall.log`, so a stale progress marker could appear next to later package recovery logs and look like the root cause.

## Fix Direction

Clean uninstall recovery must not wait on the standard 900s graceful VM stop path. When `--force-clean-uninstaller` is used, HostCLI now receives an explicit `forceClean` effect contract and uses the force VM stop path:

- disable runtime services before cleanup,
- send `SIGKILL` to the owned VM process,
- wait only the force-stop timeout,
- unload remaining launchd services after forced VM stop,
- if the VM pid file is missing, unload launchd services from explicit launchd state instead of treating missing pid state as cleanup success,
- preserve service stop blocked state if the VM process is still observable,
- refuse to mark the cleanup completed while launchd services, runtime artifacts, or package receipts still block a fresh install.

The progress viewer now tags terminal markers with a run id and only treats markers for its own run as terminal. Shared or stale log lines no longer masquerade as the current worker result.

## Prevention

Do not infer cleanup success or failure from a shared log marker alone. Keep progress viewer session state separate from Host-owned runtime state. Force cleanup can use more aggressive Host effects, but it must still record blockers and fail the cleanup when a fresh install would remain blocked.

Do not remove plists, tools, runtime files, or receipts before the Host-owned launchd state has been unloaded or explicitly recorded as blocked. `pidFileMissing` is not a general success state; it is only allowed to continue in force clean recovery when launchd state is then read and unloaded through the launchd service contract.
