# TS-089: Host macOS Watchdog Timeout Under VM Memory Pressure

> ID: TS-089  
> Category: Runtime health / Host resources / VM lifecycle  
> Owner: macOS runtime  
> Status: active

## Symptom

macOS reboots or shuts down while VitalServer VM workload is running. The panic report is from the host macOS kernel, not from the Linux guest, and includes:

```text
panic(...): watchdog timeout: no checkins from watchdogd in 90 seconds
Kernel Extensions in backtrace:
  com.apple.driver.AppleARMWatchdogTimer
Compressor Info: ... 100% of segments limit (BAD) with ... swapfiles
Panicked task ... kernel_task
```

The 2026-06-20 field report showed `watchdogd` missing checkins for 90 seconds, `AppleARMWatchdogTimer` in the backtrace, `100% of segments limit (BAD)`, and 83 swapfiles. The same symptom had also appeared on a Mac Studio.

## Cause

This report is a host watchdog panic. It is different from guest kernel panic cases that show Linux messages such as:

```text
Kernel panic - not syncing
EXT4-fs error
Remounting filesystem read-only
```

The panic report does not prove that VitalServer guest code directly caused the host kernel panic. The strongest evidence in this case is that the host was under severe memory compression or swap pressure when `watchdogd` stopped checking in. A VM workload can be the trigger or amplifier because Apple Virtualization reserves a large memory allocation for the guest and then runs host-side disk, network, and shared-directory IO around it.

Treat this as a host resource and host virtualization stability incident until correlated evidence proves a narrower cause. Do not convert this panic into guest runtime state, guest disk state, or application health state.

## Checks

Collect host and runtime evidence before restarting stress tests:

```sh
sysctl hw.memsize
vm_stat
memory_pressure
log show --last 2h --predicate 'process == "kernel" OR process == "watchdogd" OR eventMessage CONTAINS[c] "memorystatus" OR eventMessage CONTAINS[c] "pressure"'
log show --last 2h --predicate 'eventMessage CONTAINS[c] "Virtualization" OR eventMessage CONTAINS[c] "VZ"'
```

Collect VitalServer runtime state and VM settings:

```sh
jq '{cpuCount,memoryMiB,network}' "/Library/Application Support/VitalServerHelper/runtime/vm-config.json"
tail -n 200 "/Library/Application Support/VitalServerHelper/logs/runtime/launchd.out.log"
tail -n 120 "/Library/Application Support/VitalServerHelper/logs/runtime/launchd.err.log"
tail -n 120 "/Library/Application Support/VitalServerHelper/status/runtime-events.jsonl"
```

Compare the affected machines:

- macOS build and kernel version.
- hardware model and physical memory.
- configured VM memory and CPU.
- number of concurrent VMs or test runs.
- Chrome, Xcode, Docker Desktop, backup tools, and other high-memory processes running during the incident.
- swapfile count or memory pressure shortly before the panic, when available.

## Actions

For field operation:

1. Export the panic report and VitalServer support logs before retrying the workload.
2. Reduce VM memory by one step, for example from 8 GiB to 4 GiB on 8 GiB or 16 GiB hosts.
3. Avoid concurrent heavy apps or parallel VM build/runtime smoke jobs on the affected machine.
4. If the panic repeats on the same macOS build across multiple Apple Silicon machines, preserve the panic reports as host OS or Apple Virtualization evidence.
5. Do not run VM disk repair solely because of this host panic. Only run disk repair when guest filesystem evidence exists, such as ext4 errors, read-only remount, or disk attachment invalid.

## Fix Direction

Product behavior should make host resource pressure visible before a VM start or restart:

1. Add a host resource preflight for VM start and settings apply.
   - Physical memory, configured VM memory, current memory pressure, swap pressure, and concurrent VM process state should be explicit Host-owned observations.
   - Read failures must remain read failures, not become safe defaults.
2. Report host resource blockers as host runtime state.
   - Use explicit `host-resource-unavailable-memory` or a more specific host pressure reason.
   - UI should display this state; it must not infer guest failure from host pressure.
3. Keep host panic analysis separate from guest panic analysis.
   - Guest `Kernel panic - not syncing` remains a guest boot/runtime failure.
   - macOS `watchdog timeout: no checkins from watchdogd` remains a host failure unless a host contract connects it to a known VM lifecycle effect.
4. Consider lowering default VM memory on smaller hosts or tightening the maximum allowed memory rule.
   - Current defaults reserve 4 GiB for the host and default to 8 GiB when allowed.
   - Repeated watchdog timeout reports suggest the host reserve may be too small for real-world macOS plus browser/helper workloads.

## Prevention

Do not let runtime recovery loop into a host under memory pressure. Watchdog recovery, settings restart, and runtime smoke should consume explicit host resource observations and fail or defer with a visible host-resource reason when the host cannot safely sustain the VM workload.

Do not document this as a guest disk corruption case unless guest logs prove filesystem or kernel failure. Host watchdog panic, guest kernel panic, VM disk read-only, and app readiness failure are separate states with separate owners.
