# Host Installation Lifecycle Boundary

> 상태: **macOS PKG의 C48–C50 install transaction과 C54 removal transaction, Linux의 C49 dpkg/systemd observation·deterministic DEB assembly·실제 `dpkg --install → --remove` lifecycle acceptance를 구현했다. C68 Host Platform staged update는 C48의 platform에 따라 launchd plist/systemd unit/SCM JSON archive layout과 symbolic-link/directory-junction activation effect를 명시적으로 선택한다. Linux default removal은 C54 terminal receipt와 `deinstall ok config-files`까지만 증명하며 C48-declared mutable data를 보존한다. 세 OS C24 runner는 C29/C28/C55/C48/C49 update·rollback contract와 fresh native observation을 결합하는 command를 구현했지만, 실제 clean-Host reboot·update/rollback·uninstall/reinstall delivery evidence는 아직 attach되지 않았다.**

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
| **C48 `HostProductInstallationManifest`** | Release process | immutable release catalog/slot, `current` link, service label·definition hash, mutable store와 packaged Console C53 path/hash의 선언. `installation-manager-journal`은 반드시 Host Installation Manager 소유·`purge-only-by-explicit-command`인 유일한 C50 store | 설치 성공 또는 data compatibility 주장 |
| **C49 `HostInstallationFootprint`** | Host Installation Manager native adapter | macOS는 `pkgutil`/launchd, Linux는 dpkg/systemd, 그리고 release catalog·filesystem·explicit C50 journal/receipt path를 관측 | unreadable state를 absent로 해석하거나 arbitrary receipt residue를 clean state로 해석 |
| **C50 journal/receipt** | Host Installation Manager | preflight → quiescence intent → activation → service finalization/recovery transaction state | runtime/Guest state 소유 |
| **C54 removal journal/receipt** | Host Installation Manager | explicit preserve/purge removal decision, Host-resource deletion boundary, and package-receipt owner hand-off | package-manager database row를 product file처럼 삭제하거나 Guest state를 cleanup으로 추측 |
| **package lifecycle script / MSI custom action** | OS package-manager transport adapter | explicit C48/C50/C54 path와 operator-requested disposition을 Manager에 전달 | receipt/version/data/service 안전성 판단, OS package manager 재귀 호출, package database 삭제 |
| **Host Updater (C25–C30)** | staged update workflow | version-changing layer update | direct PKG overwrite를 successful update로 해석 |
| **C68 Host Platform staged update** | Host Installation Manager | C48 active/candidate proof, target release publish, declared activation, native service quiesce/reconcile, terminal C50 projection | package-manager overwrite를 update로 간주하거나 C24 physical proof를 자체 생성 |

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
  control/
    runtime-console-bootstrap.json        C53, C48 operatorInterface path/hash-bound
  data/                                   Host-owned mutable state
    host-agent/
    virtual-machine/
    installation-manager/
      current-transaction.json            fixed C50 journal name
      latest-installation-receipt.json    fixed C50 receipt name
```

launchd plist는 `/Library/LaunchDaemons`에 있지만 executable/configuration path는
반드시 `current/...`를 가리킨다. 따라서 same-release repair는 이미 검증된 slot만
고치고, future version activation은 stable path를 바꾸는 대신 staged updater의
명시적 workflow를 거친다.

`data/`는 release payload가 아니다. C48은 owner와 retention을 선언하지만 그
내용이 새 release와 호환된다고 추측하지 않는다. 현재 install slice는
same-release repair에서 `data/`를 보존하고 migration하지 않는다.

`installation-manager-journal`은 C48의 다른 mutable store와 교환할 수 없다.
Manager가 C49를 읽거나 C50을 쓰는 경우에는 그 store와 위의 두 fixed filename을
derive한다. package script, UI, 또는 release tool이 넘긴 임의의 path를 같은
transaction으로 해석하지 않는다.

C53은 Runtime Console이 C52의 exact path만 얻도록 하는 installation
configuration이다. release slot 안에 넣으면 `current` link의 변화를 Console이
추론해야 하므로, C48은 stable `control/runtime-console-bootstrap.json`의 exact
absolute path와 SHA-256을 별도 `operatorInterface` 사실로 bind한다. C53은
mutable data도 아니며 C33·endpoint·secret도 아니다. package composer/verifier는
그 bytes와 C53→C52 path relation을 package boundary에서 검증한다. clean-host
delivery proof는 설치 뒤 같은 path의 C53과 Host가 publish한 C52가 실제 Console
user에게 보이는지를 별도로 관측해야 한다.

Release catalog, immutable slot, mutable store, and C50 journal are observed
without following an unexpected symbolic link. Such a path is explicit
unreadable/diverged state and blocks the package; only the C48-declared
`current` activation path is a permitted symlink.

The manager rejects symbolic links in every existing ancestor as well as in
the final C48/C50 path. An `lstat` of only `data/installation-manager` could
otherwise follow a symbolic `data` parent and write the journal outside the
declared Host boundary. C48 paths must therefore use their canonical Host
location; a system alias is not an installation-state fallback.

## 3.1 C54와 OS package receipt ownership

제거는 C50 설치 transaction의 반대편 fallback이 아니다. 운영자는 C54 request에
`preserve-mutable-data` 또는 `purge-all-product-data`를 명시한다. Manager는
declared service definition, `current` activation, immutable release catalog,
그리고 선택된 purge root만 제거하며, C49로 그 결과를 다시 읽는다.

Package receipt의 owner는 OS마다 다르므로 C54 completion도 하나의 boolean이
아니다.

| Host platform | receipt owner | C54 result | 다음 책임 |
| --- | --- | --- | --- |
| macOS | Host Installation Manager가 호출하는 `pkgutil --forget` protocol | `completed`, `packageReceiptRemoval=removed-by-host-installation-manager` | C49가 package receipt까지 `absent`임을 증명 |
| Linux | dpkg database | `awaiting-package-manager`, `packageReceiptRemoval=awaiting-os-package-manager` | `prerm`가 C54 completion transport를 durable manager-owned store에 준비한 뒤 return한다. dpkg가 payload를 삭제하면 `postrm`은 그 persisted Manager/C48 copy로 C49 `installed / packageManagerReceiptState=removed` observation을 읽고 `completed / removed-by-os-package-manager`을 기록한다. dpkg final state는 `deinstall ok config-files`이다. |
| Windows | MSI Windows Installer database | `awaiting-package-manager`, `packageReceiptRemoval=awaiting-os-package-manager` | MSI `pre-RemoveFiles` custom action은 실행 중인 Manager를 포함한 exact immutable release를 남기고 declared SCM services/current junction만 제거한다. MSI가 payload와 ProductCode registration을 commit하면 manager-owned durable completion transport가 terminal C49 observation을 기록한다. |

Windows C48의 `release.productVersion`과 `package.productVersion`은 이미 같은
값이어야 한다. 따라서 Windows에서는 둘 다 MSI가 실제 receipt로 기록할 수 있는
세 숫자 버전(`major.minor.build`, 각각 `0–255`, `0–255`, `0–65535`)이어야 한다.
`0.2.0-dev`처럼 사람이 읽기 위한 release label은 `release.id`나 delivery
artifact metadata에 둘 수 있지만 C49가 비교하는 MSI receipt version으로 쓰지
않는다. Release composer와 Domain이 이 제약을 모두 검증해 package build가
불가능한 C48을 뒤늦게 만들지 않는다.

같은 이유로 Windows C23 delivery plan의 `productVersion`과 MSI artifact filename은
이 숫자 version을 사용한다. `-dev`, build channel, Git revision 같은 prerelease
정체성은 C48 `release.id` 또는 별도의 delivery artifact metadata가 owner이며,
MSI ProductCode/DisplayVersion에 섞지 않는다. macOS와 Linux의 package receipt
규칙을 Windows MSI receipt에 일반화하지 않는다.

따라서 Linux/Windows의 `awaiting-package-manager`는 성공을 꾸미는 fallback이
아니다. immutable release, activation, declared services, 그리고 requested
mutable disposition이 이미 C49로 증명됐지만 package database는 아직 OS의
transaction 안에 있다는 typed hand-off다. `completed` receipt를 쓰거나
package hook에서 `dpkg --purge`/`msiexec /x`를 재귀 호출하는 것은 금지된다.
Linux의 `postrm`은 삭제된 payload나 dpkg control archive의 우연한 helper copy를
사용하지 않는다. C54 admitted journal이 이름과 root를 bound한 completion
transport만 사용한다. 즉 `prerm`은 C54의 preparation effect를 실행하고,
`postrm`은 C54 domain decision이 허용한 `removed` receipt만 terminal completion
evidence로 기록한다. Windows는 같은 순서를 문자 그대로 복사하지 않는다.
Windows Installer의 pre-remove custom action은 release payload 안의 `.exe`를
실행하므로 그 프로세스가 자신의 release directory를 삭제할 수 없다. C54는
durable manager/C48 copy를 먼저 만들고, declared SCM service definitions와
`current` directory junction만 해제한 뒤 MSI에 return한다. `RemoveFiles`와
ProductCode receipt deletion은 MSI가 소유하며, `InstallFinalize` 직전에 schedule한
commit action이 durable manager를 실행해 final C49 absence를 확인한다. 이
Windows-specific hand-off는 Linux와 달리 immutable slot이 hand-off 시점에
**matching/only-expected-release**인 것을 요구한다. 어느 쪽도 package manager를
재귀 호출하거나 package receipt deletion을 성공으로 추측하지 않는다. 이후
dpkg가 남기는 `config-files`는 OS package-manager의 receipt state이며
product-success fallback이 아니다. final receipt absence와 purge disposition은
package manager가 operation을 마친 후 C24 `uninstall-reinstall` evidence가
별도로 증명한다.

### 3.2 Windows MSI source and direct-update guard

`windows_host_msi_composer.py`는 C48이 선언한 ProgramData payload, SCM
definition files, C53 bootstrap file만 WiX v4 authoring으로 쓴다. C50 fresh
install preflight는 `InstallFiles` 뒤 아직 ProductCode receipt가 없다는
`windows-msi-installing` package-manager phase를 명시한다. 같은 ProductCode의
repair는 ordinary C50 preflight를 거쳐 같은 release만 재검증한다. 둘 중 어느
path도 MSI receipt 부재를 installed/clean으로 추측하지 않는다.

서로 다른 ProductCode지만 같은 UpgradeCode인 direct MSI version install은 WiX
`Upgrade` detection + `Launch` condition으로 `InstallFiles` 전에 차단한다.
`UpgradeVersion`은 Windows Installer의 전체 유효 ProductVersion 범위인
`0.0.0`부터 `255.255.65535`까지 양끝을 포함해 명시적으로 탐지하므로,
이전 버전에서의 direct upgrade와 이후 버전에서의 direct downgrade를 모두
차단한다. 현재 ProductCode의 `Installed` repair만 허용한다. MSI
`MajorUpgrade`/`RemoveExistingProducts`는 사용하지 않는다. version-changing
release는 C68 staged Host Updater가 candidate publish/activate/reconcile contract로
수행하며, Windows MSI는 그 절차를 대체하지 않는다. WiX executable과 Util
extension이 명시적으로 제공되지 않으면 composer는 reviewable `.wxs` source만
기록하고 MSI artifact나 clean-host proof를 주장하지 않는다.

### 3.3 Linux dpkg install/removal transport

Linux package hooks are transport, not lifecycle policy. The actual receipt
states are observed by C49 and retain their different meanings:

| dpkg status | C49 stable receipt state / exact `packageManagerReceiptState` | owner and allowed transition |
| --- | --- | --- |
| `install ok unpacked` | `installed` / `unpacked` | dpkg has written payload; `postinst` may start C50. |
| `install ok half-configured` | `installed` / `configuring` | C50 is running in `postinst`; not an installed product. |
| `install ok installed` | `installed` / `installed` | terminal C50 install result; C54 removal may be admitted. |
| `deinstall ok installed` or `deinstall ok half-configured` | `installed` / `removing` | `prerm` has handed C54 to dpkg; not a deletion result. |
| `deinstall ok half-installed` | `installed` / `removed` | payload is gone during `postrm`; only a C54-bound completion transport can use this as terminal evidence. |
| `deinstall ok config-files` | `absent` / `configuration-retained` | dpkg retains package configuration metadata after normal removal. It does not imply mutable product data was deleted. |

The deterministic acceptance runs the same lifecycle in a Debian container:
`dpkg --install`, C50 service activation, `dpkg --remove`, C54 preparation and
completion, payload absence, persisted C54 receipt, then exact final dpkg
`deinstall ok config-files`. It is package-lifecycle evidence, not a
clean-host/reboot/uninstall-reinstall claim.

## 4. install transaction

```text
PKG preinstall
  └─ C50 preflight
       C48 + observed C49
       └─ admitted: journal = preflight-verified (only the declared
          installation-manager journal directory may be created; service
          effect 없음)
       └─ blocked: typed receipt is emitted to Installer stdout only;
          no C50 file or product data directory is created

Installer writes immutable release slot and launchd plist

PKG postinstall
  ├─ prepares only C32/C33-declared data directories and boot-console file
  ├─ C50 quiesce-services
  │    ├─ journal = services-quiescing (before launchctl effect)
  │    └─ exact C48 launchd services stopped → activation-pending
  ├─ C50 activate-release
  │    verifies exact C48 immutable inventory and atomically updates `current`
  │    └─ journal = activated
  └─ C50 finalize-services
       re-registers only C48-declared launchd plist paths
       └─ journal = completed

postinstall failure after `services-quiescing`
  └─ C50 recover
       ├─ re-observe C49 and verify the exact C48 slot
       ├─ activate/reconcile that exact release only
       └─ journal = recovered
```

`quiesce-services` accepts launchctl exit status `0` (stopped), legacy status
`3` (already absent), or the macOS 26 status `113` only when the diagnostic
names the exact declared service as missing. Its durable `services-quiescing`
intent is written *before* the first bootout. Any other exit, command-start
failure, decode failure, or journal mismatch is a typed failed/blocked receipt.
A partial service stop therefore remains a visible recovery-required
transaction instead of a quietly retryable success. A `preflight-verified`
journal is distinct: it has no Host effect and a later preflight may explicitly
supersede it after an Installer payload failure.

C49 service *observation* and C50 quiescence/reconciliation each use the same
narrow adapter-owned missing-service protocol. A legacy no-service result is
status `3`. macOS 26 status `113` is accepted only when stderr contains
`Could not find service "<declared-service>" in domain for system`. A generic
status `113`, a response for another service, a command-start failure, or
unreadable output stays a typed observation/effect failure; it is never a
Domain fallback.

A blocked preflight did not begin an installation transaction. Its structured
receipt is emitted to the Installer log and returned as the CLI result, but is
not persisted below the product data root. Persisting it would manufacture
mutable product state before C50 admitted the operation and turn a harmless
retry into a stale-footprint cleanup problem. The first durable C50 state is
therefore the admitted `preflight-verified` journal. A later payload failure
may leave that journal and use the narrow `clean-install-retry` transition.

Historical packages released before this rule could persist a `blocked` C50
receipt even though preflight had made no Host effect. C49 models that as
`legacy-blocked-preflight` only after it decodes the receipt, verifies the
installation identity, finds no journal, and inventories the highest declared
manager-owned purge-only store to prove that the receipt and its ancestor
directories are the only residue. The explicit
`clean-install-migrate-blocked-preflight-receipt` transition replaces that
known diagnostic document with an admitted journal/receipt. A malformed
receipt, a receipt for another installation, a symlink, an extra file, or any
Host Agent/VM/payload/service state is `receipt-residue` or `unreadable` and
remains blocked. This is migration, not cleanup fallback.

## 5. admission scenarios

| observed C49 footprint | decision | reason |
| --- | --- | --- |
| receipt, release catalog/slot, link, service registration/plist, data, journal all absent | `clean-install` | no owned product state exists |
| no package/release/link/service/runtime state, no journal, and one C49-verified historical `blocked` receipt as the only manager-owned transaction residue | `clean-install-migrate-blocked-preflight-receipt` | old package recorded a diagnostic result before making any product effect; the new preflight atomically replaces only that known document |
| no package receipt/release/service plus `preflight-verified` journal and only its C48-declared manager-owned journal directories | `clean-install-retry` | a prior preflight created diagnostic transaction state but payload delivery did not establish product state |
| same receipt version, only expected catalog slot, matching slot/link/plist, terminal, absent, or preflight-only journal | `same-release-reinstall` | exact immutable release is already active; preflight-only journal made no service effect |
| same receipt version, only expected catalog slot, diverged slot or service plist, expected link, terminal, absent, or preflight-only journal | `same-release-repair` | service is quiesced only after declared bytes are written |
| package receipt version or `current` points at another release | `blocked: direct-version-upgrade-requires-staged-updater` | a direct PKG overwrite is not a version update |
| receipt absent but release catalog/slot, link, service registration/plist, data residue, or arbitrary C50 receipt residue remains | `blocked: stale-installation-footprint-requires-explicit-cleanup` | removing or overwriting unknown state would be data-loss inference |
| unreadable receipt, file, link, journal, service, or data path | `blocked` with typed issue | unknown is not absent |
| journal is `services-quiescing`, `activation-pending`, `activated`, or `failed` | `blocked: unfinished-installation-transaction` | recovery must be explicit |

This deliberately means an old, incomplete installation is not deleted by a
new package. The current slice makes the condition observable and blocks the
write before it can make the situation worse. A future privileged uninstall/
cleanup workflow must have a separately reviewed C50 transition and an
explicit `preserve` or `purge` data disposition; it must not be added as a
package-script fallback.

## 6. Version update boundary

Same-version repair is intentionally narrow. A new release ID or package
version is a **version-changing update**, even if it happens to have the same
file names. The package preflight stops before payload mutation. C25 remains
the stable bootstrap contract and C26 remains next-updater-only language;
Installation Manager never parses C26 and never reclassifies a direct installer
invocation as an update.

The Host Updater validates/stages C25–C30 and delegates the final
`host-platform` layer to a C67 release-owned effect executor. C67 can invoke
only the already-installed Host Installation Manager at the platform's fixed
stable path and names the active `current/installation-manifest.json` path.
The manager reads that active C48 before it inspects the candidate archive;
its C68 operation record and candidate staging directory therefore belong to
the active Installation Manager mutable store, never to a target archive. The
manager then verifies the archive and C48 target, proves the current active
C48 bytes, requires unchanged service and
mutable-store topology, records the durable service-quiescing/publish/activate
boundaries, atomically changes `current`, then re-registers the target's
declared services. A C55 result is successful only when the correlated C68
operation is terminal `succeeded`. Before C68 writes that success, it records
the target C48's `completed` C50 journal/receipt in the target's declared
transaction store. Otherwise a C49 read would see a previous-release C50
record after `current` changed and must report that mismatch rather than
inventing a coherent result. C68 recovery follows the same rule with a
`recovered` C50 transaction for the explicitly re-read `current` C48.

This is intentionally **not** a direct PKG overwrite. Initial installation and
same-release repair remain C50 package transactions; version changes are C68
candidate release transitions. A package receipt version is not used as a Host
update success signal. C68 does not silently replay an incomplete operation.
A `failed` or `unavailable` operation retains the last durable boundary, which
records what the manager had established before an external effect became
uncertain. An operator can invoke only the explicit `reconcile-current-release`
recovery after `services-quiescing`, `release-publishing`, or `activating`. It
proves the actual `current` C48, then re-registers only that release's declared
services. It does not re-apply the archive, infer whether activation completed,
or guess a rollback; the original failed C68 operation remains the update
outcome and recovery has its own receipt. A release that changes service identity/path or
mutable-store topology is blocked rather than reclassified as a normal update;
it requires a separately designed migration contract.

The current same-release PKG path also writes immutable content to the final
C48 slot. C50 protects the critical “payload failure after service quiescence”
case, but it is not a candidate-slot promotion protocol. An online
repair/update design that must prove no in-use file is replaced in place needs
a separate candidate slot, atomic promotion/rollback contract, and C28
evidence. It must not be represented as a broader meaning of
`same-release-repair`.

## 7. Build and package proof

C47 requires a concrete Host Installation Manager binary. The macOS package
composer places it both in the immutable slot and in `Scripts/`, generates C48
after immutable bytes, launchd plists, and VM Supervisor signing are final, and
verifies that the C48 hashes and executable modes match the final package
payload. The expanded-PKG verifier proves the script manager and C48 copies
are byte-identical to their immutable payload counterparts, requires the
preflight/quiesce/activate/finalize/recovery sequence, and rejects package
scripts that directly call launchd.

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
