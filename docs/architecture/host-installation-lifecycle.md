# Host Installation Lifecycle Boundary

> 상태: **macOS PKG의 C48–C50 install transaction 구현 및 deterministic package verification 완료.** 실제 clean-Host install, reboot, uninstall/reinstall 증명은 C24 delivery evidence에서 별도로 수행한다.

## 1. 해결하려는 문제

macOS Installer는 같은 target path에 새 payload를 쓸 수 있다. 하지만 기존 파일,
receipt, launchd service, `current` link, 또는 product data가 남았다는 사실만으로
그것이 안전한 reinstall인지, 중단된 install인지, 다른 release인지 알 수는 없다.

그래서 이 제품은 “PKG가 덮어쓸 수 있다”를 installation success의 근거로 쓰지
않는다. Host Installation Manager가 모든 관련 fact를 명시적으로 관측하고, 순수
정책이 허용한 경우에만 package script가 다음 effect로 진행한다.

## 2. 소유자와 계약

| 대상 | authoritative owner | 하는 일 | 하지 않는 일 |
| --- | --- | --- | --- |
| **C48 `HostProductInstallationManifest`** | Release process | immutable release catalog/slot, `current` link, service label·definition hash, mutable store의 선언 | 설치 성공 또는 data compatibility 주장 |
| **C49 `HostInstallationFootprint`** | Host Installation Manager의 macOS adapter | `pkgutil`, release catalog, launchd registration·plist bytes, filesystem, existing C50 journal을 관측 | unreadable state를 absent로 해석 |
| **C50 journal/receipt** | Host Installation Manager | preflight → quiescence → activation transaction state | runtime/Guest state 소유 |
| **PKG pre/postinstall script** | Installer transport adapter | explicit C48/C50 path를 Manager에 전달하고 declared service를 bootstrap | receipt/version/data/service 안전성 판단 |
| **Host Updater (C25–C30)** | staged update workflow | version-changing layer update | direct PKG overwrite를 successful update로 해석 |

`Host Installation Manager`는 Host Agent의 대체물이 아니다. 장기 실행 서비스가
아니며, package effect 전후의 한 번성 transaction boundary다.

## 3. 파일 배치와 변경 가능성

```text
/Library/Application Support/VitalServerRuntimePlatform/
  releases/                              C48-declared release catalog
    <release-id>/                         immutable C48 release slot
    bin/host-agent
    bin/host-edge-proxy
    bin/host-installation-manager
    bin/macos-virtual-machine-supervisor
    config/, release/, vm/
    installation-manifest.json
  current -> releases/<release-id>        atomically activated stable link
  data/                                   Host-owned mutable state
    host-agent/
    virtual-machine/
    installation-manager/
```

launchd plist는 `/Library/LaunchDaemons`에 있지만 executable/configuration path는
반드시 `current/...`를 가리킨다. 따라서 same-release repair는 이미 검증된 slot만
고치고, future version activation은 stable path를 바꾸는 대신 staged updater의
명시적 workflow를 거친다.

`data/`는 release payload가 아니다. C48은 owner와 retention을 선언하지만 그
내용이 새 release와 호환된다고 추측하지 않는다. 현재 install slice는
same-release repair에서 `data/`를 보존하고 migration하지 않는다.

Release catalog, immutable slot, mutable store, and C50 journal are observed
without following an unexpected symbolic link. Such a path is explicit
unreadable/diverged state and blocks the package; only the C48-declared
`current` activation path is a permitted symlink.

## 4. install transaction

```text
PKG preinstall
  ├─ C50 preflight
  │    C48 + observed C49
  │    └─ admitted: journal = preflight-verified
  ├─ C50 quiesce-services
  │    exact C48 launchd services only
  │    └─ succeeded: journal = activation-pending
  │
  └─ Installer writes immutable release slot and launchd plist

PKG postinstall
  ├─ C50 activate-release
  │    verifies every C48 SHA-256 entry in the written slot
  │    └─ atomically replaces current link; journal = activated
  └─ prepares only C32/C33-declared data directories and bootstraps C48 services
```

`quiesce-services` accepts launchctl exit status `0` (stopped) or `3`
(already absent) only. Any other exit, command-start failure, decode failure,
or journal mismatch is a typed failed/blocked receipt. A partial service stop
therefore remains a visible failed installation transaction instead of a
quietly retryable success.

## 5. admission scenarios

| observed C49 footprint | decision | reason |
| --- | --- | --- |
| receipt, release catalog/slot, link, service registration/plist, data, journal all absent | `clean-install` | no owned product state exists |
| same receipt version, only expected catalog slot, matching slot/link/plist, terminal or absent journal | `same-release-reinstall` | exact immutable release is already active |
| same receipt version, only expected catalog slot, diverged slot or service plist, expected link, terminal or absent journal | `same-release-repair` | service is quiesced before declared bytes are repaired |
| package receipt version or `current` points at another release | `blocked: direct-version-upgrade-requires-staged-updater` | a direct PKG overwrite is not a version update |
| receipt absent but release catalog/slot, link, service registration/plist, or data residue remains | `blocked: stale-installation-footprint-requires-explicit-cleanup` | removing or overwriting unknown state would be data-loss inference |
| unreadable receipt, file, link, journal, service, or data path | `blocked` with typed issue | unknown is not absent |
| journal is active | `blocked: unfinished-installation-transaction` | recovery must be explicit |

This deliberately means an old, incomplete installation is not deleted by a
new package. The current slice makes the condition observable and blocks the
write before it can make the situation worse. A future privileged uninstall/
cleanup workflow must have a separately reviewed C50 transition and an
explicit `preserve` or `purge` data disposition; it must not be added as a
package-script fallback.

## 6. Version update boundary

Same-version repair is intentionally narrow. A new release ID or package
version is a **version-changing update**, even if it happens to have the same
file names. The package preflight stops before payload mutation and directs the
operator to the staged Host Updater. C25 remains the stable bootstrap contract
and C26 remains next-updater-only language; Installation Manager never parses
C26 and never reclassifies a direct installer invocation as an update.

## 7. Build and package proof

C47 requires a concrete Host Installation Manager binary. The macOS package
composer places it both in the immutable slot and in `Scripts/`, generates C48
after immutable bytes, launchd plists, and VM Supervisor signing are final, and
verifies that the C48 hashes match the final package payload. The expanded-PKG
verifier additionally requires the preflight/quiesce/activate invocation
sequence and rejects package scripts that directly call `launchctl bootout`.

Useful deterministic checks are:

```sh
make -C runtime-platform host-installation-manager-test
make -C runtime-platform host-installation-manager-build
make -C runtime-platform macos-host-package-composer-test
make -C runtime-platform macos-release-package-assembly-test
make -C runtime-platform contract-check
```

These prove source, contracts, and uninstalled package contents. They do not
claim C24 clean-Host installation, reboot retention, uninstall/reinstall, or
Apple distribution acceptance.
