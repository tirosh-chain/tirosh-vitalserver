# Windows Clean-Host Release Evidence Boundary

## 목적

Windows MSI가 만들어졌다는 사실과 Windows Host에 설치되어 재부팅 뒤에도
서비스가 남아 있다는 사실은 다르다. 이 문서는 C24 `ReleaseDeliveryProof`를
생성하기 위해 도입한 `WindowsCleanHostReleaseEvidenceRunner`의 책임 경계를
고정한다.

이 runner가 증명할 수 있는 단계는 다음과 같다.

1. `artifact-integrity`: 선택된 MSI의 SHA-256, MSI `ProductVersion`,
   Authenticode 상태를 관측한다.
2. `clean-host-preflight`: MSI ProductCode registry receipt, C23의 세 SCM
   service, 명시된 product installation root가 모두 없음을 관측한다.
3. `clean-install`: 운영자가 명시적으로 실행한 `msiexec /i` 뒤 정확한
   ProductCode와 `DisplayVersion`을 관측한다.
4. `service-registration`: C23이 선언한 `host-agent`, `host-edge-proxy`,
   `host-update-handoff-supervisor`가 각각 SCM에 등록된 것을 관측한다.
5. `reboot`: checkpoint의 Windows boot-session 식별자와 다른 식별자를
   관측한 뒤 MSI receipt, 세 SCM service, product root를 다시 관측한다.
6. `update`: explicit C29/C28/C55 apply와 C48/C49 contract를 검증한 뒤 fresh
   registry ProductCode, SCM service, product root가 그 결과와 일치하는지 관측한다.
7. `rollback`: failed C29/C28와 succeeded C55 rollback, restored C48/C49를
   검증한 뒤 fresh DisplayVersion/SCM/root가 restored release와 일치하는지 관측한다.
8. `uninstall-reinstall`: C54 `preserve-mutable-data` 제거 뒤 MSI ProductCode,
   세 SCM service, C48 immutable release root가 없고 C48 mutable data root가
   남았음을 관측한다. 정확한 completed C54 receipt가 있을 때만 같은
   hash-bound MSI를 재설치하고 package/service/두 root를 다시 관측한다.

`sbom-and-notices`와 actual staged-update effect는 다른 owner의 명시적
workflow다. 이 runner는 effect를 실행하지 않고, 완료된 update/rollback contracts와
fresh Windows observation을 결합한다. update와 rollback은 같은 run에 함께 기록할 수
없다. `uninstall-reinstall`도 dedicated
clean Windows Host에서 실제로 수집한 경우만 release proof가 될 수 있으며,
checked-in proof를 `verified`로 바꾸지 않는다.

## Owner와 입력 계약

| 사실 | Owner | runner가 받는 입력 | runner가 하는 일 |
| --- | --- | --- | --- |
| intended MSI 이름/version, SCM service 이름 | C23 Product Delivery | release-plan path와 plan ID | `WindowsHostMSIReleasePlan`으로 한 번 투영 |
| MSI ProductCode, installation root, immutable release root, mutable data root | MSI/C48 release composition | explicit CLI input | clean preflight/install 및 C54 보존 제거 뒤 실제 Windows observation과 비교 |
| C54 preservation completion | Host Installation Manager | exact receipt path + expected installation/release ID | receipt identity, disposition, OS package-manager completion을 확인한 뒤에만 재설치 |
| Windows command output | Windows | C24 command contract (`PowerShell`, `msiexec`, `reg.exe`, `sc.exe`) | raw stdout/stderr와 결과를 evidence에 보존 |
| C24 stage transition | Release process | runner SQLite journal | predecessor guard와 immutable stage record 적용 |
| Host lifecycle/Guest state | Host Agent/Guest Runtime | 없음 | 읽거나 변경하지 않음 |

C23은 MSI `ProductCode`나 release directory를 소유하지 않는다. 반대로
runner는 C23에 없는 service name, product version, installer filename을 CLI
argument로 다시 받지 않는다. 이 분리로 C23 desired identity와 MSI/C48
composition identity가 섞이지 않는다.

## 외부 명령과 failure 의미

명령은 ambient `PATH`에서 찾지 않는다. run 생성 시 absolute executable path를
`WindowsCleanHostReleaseEvidenceCommandContract`로 기록한다.

- `reg.exe query`의 알려진 *key/value 없음* 응답만 MSI `absent`다. access,
  registry service, parsing error는 `unavailable` 또는 `invalid`다.
- `sc.exe query`의 알려진 *does not exist as an installed service* 응답만
  service `absent`다. 다른 SCM error는 clean Host가 아니다.
- PowerShell MSI COM metadata와 Authenticode 결과는 둘 다 읽혀야 하며,
  signature `Valid`와 C23 `ProductVersion` 일치가 필요하다.
- `Test-Path`가 `present`/`absent` 이외의 결과이면 요청한 C48 root 상태는
  `unavailable`이다. product root가 존재한다는 이유로 data root를 추정하지
  않는다.
- `msiexec /x` 성공, registry receipt 부재, service 부재 중 어느 하나도 C54
  completion receipt나 data preservation을 대신하지 않는다. receipt가 없거나
  다른 installation/release를 가리키면 reinstall effect는 실행되지 않는다.

따라서 MSI file name, `msiexec` exit code, C48 manifest, 이전 journal row는
Windows install/service/reboot 성공을 대신할 수 없다.

## 실행 흐름

```mermaid
sequenceDiagram
    participant O as Elevated release operator
    participant R as Windows C24 runner + SQLite journal
    participant W as Windows Installer / Registry / SCM / CIM

    O->>R: create-run(C23, MSI, ProductCode, C48 roots, command contract)
    R->>R: bind MSI SHA-256; create new journal
    O->>R: record-artifact-integrity
    R->>W: MSI metadata + Authenticode observation
    O->>R: record-clean-host-preflight
    R->>W: registry + SCM x3 + root observation
    O->>R: execute-clean-install(--authorize-clean-install)
    R->>W: msiexec /i … /qn /norestart
    R->>W: ProductCode receipt observation
    O->>R: record-service-registration
    R->>W: registry + SCM x3 + root observation
    O->>R: record-reboot-checkpoint; reboot Windows outside runner; record-reboot
    R->>W: CIM boot session + registry + SCM x3 + root observation
    O->>R: execute-uninstall-reinstall-preserving-data(C54 receipt, IDs, --authorize-uninstall-reinstall)
    R->>W: msiexec /x + registry/SCM/immutable/data observations
    R->>W: msiexec /i only after completed C54 preservation receipt
    R-->>O: immutable evidence JSON + C24 proof fragments
```

`execute-clean-install`은 install effect를 수행하는 유일한 command이며 반드시
`--authorize-clean-install` grant를 함께 받아야 한다. create, integrity,
preflight, service, reboot command는 install/reboot를 발생시키지 않는다. runner도
canonical `release-delivery-proofs.v1.json`을 수정하지
않는다. release operator는 emitted fragment와 evidence bytes를 C74 review
attachment에 명시적으로 제시하여 새 immutable C24 candidate를 발행한다. 자세한 guard와
candidate 검증 절차는 [Release Delivery Proof Attachment
Boundary](release-delivery-proof-attachment-boundary.md)를 따른다.
`write-stage-proof-fragment --stage <C24 stage> --output-proof-fragment <new absolute file>`는
SCM/registry evidence journal을 바꾸지 않고 one-time C24 fragment file만 발행한다.

`execute-uninstall-reinstall-preserving-data`는 reboot evidence 뒤의 별도
수명주기 effect이며 반드시 `--authorize-uninstall-reinstall` grant를 함께 받아야
한다. MSI ProductCode의 `/x`는 run에 고정된 C48 input이고,
reinstall은 C54 receipt와 package/service/immutable-root/data-root 관측이 모두
성공했을 때만 수행한다. 현재 C54 OS package-manager completion은 preservation
경로만 terminal하게 표현한다. purge는 preservation으로 둔갑하거나 verified
C24 proof가 되어서는 안 되며, 별도 external completion 설계가 필요하다.

## 검증과 운영 한계

`make -C runtime-platform windows-clean-host-release-evidence-runner-test`는
Windows command contract fixture로 C24 transition/guard/failure semantics을
검증한다. 여기서 실제 MSI 설치나 Hyper-V 실행은 하지 않는다.

실제 release evidence는 dedicated clean Windows Host에서 runner CLI를 실행해
수집해야 한다. CI가 actual Host binaries로 WiX MSI를 compile하는 것은
artifact-build proof일 뿐이며, clean install, SCM registration, reboot, update,
rollback, uninstall/reinstall C24 proof가 아니다.
