# Distribution Verification Phase Gaps

## Symptom

Distribution commands can appear successful even though a later phase still has an unverified failure path. Examples:

- `dist/pkg/*/verify` and `dist/dmg/*/verify` do not run the same review gate.
- `dist/troubleshooting/*` stages command files but does not verify executable bits or wrapper contracts.
- update bundle verification checks the archive, but the static smoke and apply smoke interfaces are not visible as separate phases.
- installation can be run without a single target that first verifies the package and then checks the installed runtime.
- rootfs compile과 package/runtime smoke가 Guest deploy material을 각각 다시 조립하면, 서로 다른 apt snapshot, Docker platform, runtime-data metadata 또는 Guest source를 사용해도 성공처럼 보일 수 있습니다.

## Cause

Distribution targets historically grew around artifact type instead of release phase. That made build, artifact verification, install verification, update smoke, and installed runtime smoke easy to confuse. Package 단계가 compile material을 다시 만들면 compile proof와 artifact/runtime proof의 identity도 끊깁니다. 누락된 phase나 identity proof는 runtime state가 아니며 성공한 build target으로 숨기면 안 됩니다.

## Fix Direction

Expose each distribution phase as an explicit target:

```sh
make dist/pkg/dev/verify
make dist/dmg/dev
make dist/dmg/dev/verify
make dist/troubleshooting/dev/verify
make dist/update/dev/smoke
make dist/image-update/dev/smoke
make dist/install/dev/verified
make dist/installed/smoke
```

Release targets must use the same review gate as development targets before compile and runtime smoke. Troubleshooting Tools must verify staged command wrappers and bundled CLIs. Update apply smoke must stay guarded because it can modify an installed runtime.

Rootfs compile은 actual Guest deploy material digest를 receipt에 기록해야 합니다. Package와 runtime smoke는 compile source를 다시 조립하지 않고 그 material을 restage한 뒤, Host가 run마다 소유하는 `host-time.json`, `guestClockUtc`, runId, runtime-smoke 설정만 새로 쓰고 receipt digest와 대조해야 합니다. receipt mismatch는 `pkgbuild` 또는 VM boot 이전의 explicit failure입니다.

## Prevention

Keep these meanings separate in Make targets and devtools usecases:

- review gate: source, contract, and unit-level checks
- compile: build package, DMG, or bundle artifacts
- artifact verify: inspect generated artifact layout and checksums
- static smoke: verify bundle/application contracts without applying them
- apply smoke: explicitly guarded runtime mutation
- installed status: require the Helper app and its main executable, installed
  runtime executables, VM address, Platform Agent, VM, proxy, guest log sync,
  and watchdog launchd jobs; sleep prevention and automatic backup remain
  explicitly optional when `launchctl` reports them absent, while command
  execution/read failures remain failures
- installed health: require installed status plus Guest HTTP and Host proxy HTTP
- installed smoke: require installed health plus the explicit exit/result of the
  installed `/usr/local/bin/vitalserver-vm runtime health` contract
- material receipt: rootfs, package payload, runtime-smoke deploy가 같은 compile material을 사용했는지 확인

Installed status, health, and smoke do not infer package receipt/version or the
recorder ingress → Redis → VitalServer data path. Those proofs belong to a separate
privileged installed acceptance fixture. Do not let a build target imply a later
phase passed. If a phase is not implemented, the target must fail explicitly
instead of returning success.

The installed smoke adapter does not elevate privileges. It runs the installed
CLI with the caller identity and the explicit installed `VITALSERVER_VM_HOME`.
The current health command reads root-owned Host state and publishes a status
artifact, so an unauthorized read/write or CLI exit is an explicit smoke failure,
not an optional or healthy result.
