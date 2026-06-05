# TS-051: Install Blocked by Orphan Host Proxy nginx

## Symptom

After clean uninstall, installing `VitalServerHelper-*.pkg` fails in Installer with:

```text
PKInstallErrorDomain Code=112
fresh install preflight blocked blockers=host-proxy-port-occupied:port=80 listeners=nginx/<pid>
```

The install preflight document reports the app bundle, product root, runtime tools, launchd plists, and package receipt as absent, but `proxyPortState` is occupied by `nginx`.

## Cause

The host proxy launchd service can be unloaded while the nginx master/worker process it started remains alive. Clean uninstall then removes `/Library/Application Support/VitalServerHelper`, but the orphan nginx process can continue holding port 80 with `PPID=1`.

Fresh install correctly blocks because it must not assume that a port listener is safe to replace. The missing cleanup was in uninstall: it stopped launchd services but did not explicitly verify and terminate owned host proxy nginx listeners before deleting installed files.

## Fix Direction

After stopping runtime services during uninstall, run host proxy port cleanup in an uninstall-specific mode:

- inspect the configured proxy port,
- identify VitalServer-owned nginx listeners by expected PID or installed nginx command path,
- terminate only owned nginx listeners,
- leave external listeners visible and untouched.

Fresh install preflight should continue to block if any external or orphan listener still owns the configured proxy port.

## Prevention

Uninstall must verify process state owned by the Host before removing files that are needed to classify that process. Do not infer that a launchd service unload means all child processes are gone.
