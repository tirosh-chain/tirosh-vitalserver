# Linux Clean-Host Release Evidence Boundary

## 목적

DEB archive가 생성된 사실과 Linux Host에서 `dpkg` receipt, systemd unit,
filesystem root가 실제로 관측된 사실은 다르다. 이 문서는 C24를 위해 만든
`LinuxCleanHostReleaseEvidenceRunner`의 역할과 failure 의미를 정의한다.

runner는 다음 release-process stage만 관리한다.

1. `artifact-integrity`: 선택된 DEB의 SHA-256과 `dpkg-deb` Package/Version을
   직접 관측한다.
2. `clean-host-preflight`: `dpkg-query` package receipt, C23의 세 systemd
   unit, C48-owned immutable product root와 mutable data root가 모두 없는지
   관측한다.
3. `clean-install`: 운영자가 명시적으로 실행한 `dpkg --install` 뒤 exact
   package/version receipt를 관측한다.
4. `service-registration`: C23의 `host-agent`, `host-edge-proxy`,
   `host-update-handoff-supervisor` unit이 모두 `LoadState=loaded`인지
   관측한다.
5. `reboot`: checkpoint 후 kernel `/proc/sys/kernel/random/boot_id`가
   변경됐는지, package receipt·unit·두 root가 유지됐는지 다시 관측한다.
6. `update`: explicit succeeded C29/C28/C55 apply와 C48/C49를 검증한 뒤 fresh
   `dpkg-query`, systemd, 두 root가 target release와 일치하는지 관측한다.
7. `rollback`: explicit failed C29/C28 plus succeeded C55 rollback/C48/C49를
   검증한 뒤 fresh package version이 restored C48 release와 일치하는지 관측한다.
8. `uninstall-reinstall`: 명시적으로 선택한 C54
   `preserve-mutable-data` removal을 실행한 뒤 dpkg receipt와 세 unit, immutable
   root가 absent이고 mutable data root가 present인지 관측한다. 그 C54 receipt가
   declared installation/release identity와 일치할 때만 동일 DEB를 재설치하고,
   package/unit/two-root 상태를 다시 관측한다.

`sbom-and-notices`, actual update/rollback effect, 그리고 **purge** disposition의
`uninstall-reinstall`은 다른 owner가 필요하다. 이 runner는 effect를 실행하지 않고
완료된 update/rollback contract와 fresh Linux observation을 결합하며, 한 run에 두
상반된 scenario를 섞지 않는다. C54의 Linux
package-manager completion은 preserve disposition만 terminal receipt로 만들기
때문이다. runner는 checked-in proof를 변경하지 않는다.

## Owner와 경계

| 사실 | Owner | contract/input | runner 행동 |
| --- | --- | --- | --- |
| DEB filename/version, systemd unit name | C23 Product Delivery | selected C23 plan | `LinuxHostDEBReleasePlan`으로 투영 |
| Debian package identifier, product/data roots | C48/DEB composition | explicit run input | observed value와 C23 version을 분리해 보존 |
| package receipt | `dpkg-query` | absolute `dpkg-query` executable | `installed`, explicit `absent`, `residual`, `unavailable`을 구분 |
| service registration | systemd | absolute `systemctl` executable | only `loaded` → registered, only `not-found` → absent |
| reboot session | Linux kernel | declared `cat` executable와 boot-ID path | checkpoint와 changed value 비교 |
| preserving removal completion | Host Installation Manager C54 + dpkg | explicit C54 receipt path, installation ID, release ID | `completed`/`removed-by-os-package-manager`과 exact preservation choice 확인 |
| evidence stage state | Release process | runner SQLite journal | immutable stage/evidence/C24 fragment 기록 |

Host Agent SQLite, Guest Runtime state, libvirt VM lifecycle은 runner input도
output도 아니다. Linux provider가 실행됐다는 것과 systemd unit registration은
독립된 사실이다.

## 실패 의미

`dpkg-query`의 `deinstall ok config-files` 같은 residual 상태는 package
absence가 아니다. 더구나 이 제품은 mutable data를 default로 보존할 수 있으므로
data root가 남아 있으면 clean Host가 아니다. `systemctl`의 다른 exit/status,
`test -e`의 0/1 이외 결과, boot ID empty/read failure는 모두 `unavailable`로
남으며 clean install success로 변환하지 않는다.

`dpkg --install`의 exit code 0도 단독 proof가 아니다. 이어서 exact
package/version receipt가 `install ok installed`이고, service stage에는 세
unit/두 root가 직접 관측돼야 한다.

`execute-uninstall-reinstall-preserving-data`는 removal command가 0이어도
즉시 reinstall하지 않는다. C54 receipt가 다른 installation/release를 가리키거나,
dpkg receipt·service·immutable/data root 중 하나가 preservation state와 다르면
`uninstall-reinstall=failed`를 남기고 종료한다. 즉 failed removal evidence를
새 install로 덮어쓰지 않는다.

## 흐름

```mermaid
sequenceDiagram
    participant O as Root release operator
    participant R as Linux C24 runner + SQLite journal
    participant L as dpkg / systemd / filesystem / kernel

    O->>R: create-run(C23, DEB, C48 package/root input, command contract)
    R->>R: bind DEB SHA-256; create new journal
    O->>R: artifact integrity → clean-host preflight
    R->>L: dpkg-deb; dpkg-query; systemctl x3; test -e x2
    O->>R: execute-clean-install(--authorize-clean-install)
    R->>L: dpkg --install selected.deb
    R->>L: dpkg-query exact package/version
    O->>R: service registration → reboot checkpoint
    R->>L: systemctl x3; cat boot ID
    O->>L: reboot outside runner
    O->>R: reboot observation
    R->>L: changed boot ID + receipt + units + roots
    O->>R: execute-uninstall-reinstall-preserving-data(C54 receipt, identities, --authorize-uninstall-reinstall)
    R->>L: dpkg --remove package → receipt/unit/root observation
    R->>L: dpkg --install selected.deb → receipt/unit/root observation
    R-->>O: immutable evidence JSON and reviewable C24 fragments
```

Creating a run, recording preflight, and checkpointing never install a DEB or
reboot the Host. The only installer effect is `execute-clean-install`, and a
root operator must give the named `--authorize-clean-install` grant. The
preserving removal/reinstall effect likewise requires
`--authorize-uninstall-reinstall`. The runner does not edit canonical
`release-delivery-proofs.v1.json`. A release operator uses C74 to review the
fragment and exact evidence bytes into a new immutable C24 candidate; see
[Release Delivery Proof Attachment
Boundary](release-delivery-proof-attachment-boundary.md).
`write-stage-proof-fragment --stage <C24 stage> --output-proof-fragment <new absolute file>`
publishes one C24 wrapper file from the runner journal without altering package,
systemd, Host, or canonical C24 state.

## Verification boundary

`make -C runtime-platform linux-clean-host-release-evidence-runner-test`
provides deterministic command-contract coverage for clean install/reboot,
preserving uninstall/reinstall, changed DEB, and ambiguous systemd failures. It
does not call `dpkg`, operate systemd, or reboot the workspace host.

Actual C24 evidence must come from a dedicated clean Linux Host. A deterministic
DEB composition or portable provider test remains build/contract evidence, not
clean installation, systemd registration, boot persistence, update, rollback,
or real uninstall/reinstall evidence.
