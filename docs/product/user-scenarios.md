# VitalServer 제품 사용 시나리오 카탈로그

이 문서는 VitalServer Helper를 사용하는 운영자 관점의 주요 여정을 식별하고,
각 여정의 명시적 상태 소유자와 acceptance evidence를 연결하는 상위 카탈로그입니다.

이 카탈로그는 runtime state의 source of truth가 아닙니다. 실제 상태는 각 소유자가
계약으로 제공하며, 이 문서는 그 계약과 사용자가 관찰할 결과를 연결합니다. 구현,
API 또는 UI가 이 문서를 읽어 상태를 만들거나 누락된 상태를 추론해서는 안 됩니다.

## 1. 사용 방법

- `US-<영역>-<번호>`는 제품 사용 시나리오의 안정적인 식별자입니다.
- 사용자-visible 동작을 변경할 때는 관련 ID의 기대 결과와 evidence를 함께 갱신합니다.
- Gherkin acceptance specification은 `features/`에 두고 같은 ID tag를 사용합니다.
- `.feature`는 현재 acceptance intent입니다. `@bdd-pending` 시나리오는 자동 실행
  증거가 아니며, 표에 연결된 unit/integration/smoke proof와 구분합니다.
- Product Lab의 생체 신호 profile 목록은 이 카탈로그가 아니라
  `apps/vitalserver-lab/vitalserver_lab/model.py`의 `DEFAULT_SCENARIOS`가 소유합니다.

## 2. High-level 동작 경계

```text
Operator
  -> VitalServer Helper UI / Runtime Control PWA
      -> Platform Agent API
          -> Host runtime-state.sqlite and Host services
          -> Runtime gateway
              -> Guest Runtime Controller
                  -> VitalServer / recorder ingress / Product Lab

VRecorder / Browser
  -> Mac host nginx :80
      -> Guest edge nginx
          -> VitalServer / recorder ingress
```

| 상태 | 소유자 | 소비자 원칙 |
|---|---|---|
| Host process, service, filesystem, endpoint, operation state | Platform Agent와 Host SQLite repository | UI와 Guest는 Platform Agent의 명시적 계약만 소비 |
| Guest service와 stack state | Guest Runtime Controller | Host는 Guest Control 응답을 표시·조율하고 Guest 내부를 추정하지 않음 |
| 실제 VRecorder/Bed 관측 | VitalDB observer와 recorder ingress의 각 owner contract | 한 관측 실패를 빈 목록이나 다른 관측의 성공으로 대체하지 않음 |
| Product Lab session/resource state | Product Lab service | UI는 Lab API의 session/recorder/bed 결과만 사용 |
| install/update/recovery/uninstall operation | 해당 Host workflow와 persisted operation state | terminal result 전에는 성공으로 전이하지 않음 |

## 3. 시나리오 카탈로그

| ID | 사용자 목적 | 진입점 | 기대 결과 | 주요 acceptance evidence | Gherkin |
|---|---|---|---|---|---|
| `US-INSTALL-001` | 새 Mac에 Helper를 설치하고 서비스를 사용할 수 있음 | DMG의 PKG installer | 설치 단계가 명시적으로 진행되고 Platform Agent, VM, Guest product service가 검증된 뒤 ready가 보고됨 | `RuntimeInstallWorkflowTests`, `InstallRuntimeUseCaseTests`, golden runtime smoke | [runtime-lifecycle.feature](../../features/runtime-lifecycle.feature) |
| `US-BOOT-001` | 설치된 Mac을 재부팅한 뒤 자동으로 서비스를 다시 사용할 수 있음 | macOS restart/login | launchd service와 VM lifecycle이 owner state를 다시 게시하고, endpoint가 확인된 뒤 proxy가 traffic을 전달함 | `RuntimeInstallStartOnBootPlanApplierTests`, `RuntimeServiceControllerTests`, runtime smoke | [runtime-lifecycle.feature](../../features/runtime-lifecycle.feature) |
| `US-STATUS-001` | 현재 상태와 장애 원인을 구분해서 확인함 | Helper Status/Advanced | loaded, missing, unavailable, failed, stale, empty와 zero가 서로 다른 의미로 표시됨 | `RuntimeControlStatusAssemblerTests`, `RuntimeStatusDisplayPolicyTests` | [runtime-lifecycle.feature](../../features/runtime-lifecycle.feature) |
| `US-SETTINGS-001` | Host/VM 설정을 저장하고 필요한 변경만 적용함 | Helper Settings | Platform Agent owner read가 완전할 때만 desired settings가 저장되고, activation proof 이후 applied state가 갱신됨 | `RuntimeControlContractsTests`, `RuntimePlatformSettingsMappingTests`, configure workflow tests | [runtime-lifecycle.feature](../../features/runtime-lifecycle.feature) |
| `US-STOP-001` | VM runtime을 중지하거나 재시작하면서 control plane은 유지함 | Settings/Advanced runtime action | product runtime service는 중지되지만 Platform Agent는 API와 Host state access를 계속 제공함 | managed-service order tests, TS-131, TS-136 | [runtime-lifecycle.feature](../../features/runtime-lifecycle.feature) |
| `US-RECORDER-001` | 실제 VRecorder 연결과 packet activity를 확인함 | VRecorder -> host port 80; Recorders/Beds | VitalDB observation과 ingress activity가 각각 명시적으로 표시되고 연결/packet history가 요청 window에 맞게 제공됨 | `RuntimeObservabilityAssemblyTests`, recorder ingress and observer tests | [recorder-and-lab.feature](../../features/recorder-and-lab.feature) |
| `US-RECORDER-002` | 숨긴 Recorder/Bed를 삭제해 관련 session 정보까지 정리함 | Recorders/Beds Delete | owner delete command가 성공한 뒤 대상 recorder, bed, assignment/session 관계가 다시 조회되지 않음 | Runtime Control API delete tests, Product Lab cleanup tests, TS-129 | [recorder-and-lab.feature](../../features/recorder-and-lab.feature) |
| `US-RECORDER-003` | VRecorder data를 유지하면서 기본 목록 표시를 관리함 | Helper/PWA Recorders Detail | 명시적으로 선택한 VRecorder만 숨겨지고 다른 VRecorder가 자동 선택되지 않으며 Undo/Show in list로 복구됨; command 실패 시 선택과 owner failure가 보존됨 | `RuntimeViewModelCapabilityTests`, PWA recorder page interaction tests | [recorder-and-lab.feature](../../features/recorder-and-lab.feature) |
| `US-LAB-001` | Product Lab scenario session을 만들고 Recorder를 시작·중지함 | Helper Lab | Lab owner가 session과 resource state를 제공하고, 상태 guard가 허용한 start/stop만 실행됨 | `apps/vitalserver-lab/tests/test_server.py`, Runtime Lab API tests | [recorder-and-lab.feature](../../features/recorder-and-lab.feature) |
| `US-LAB-002` | Lab resource를 삭제하고 생성된 관계를 정리함 | Helper Lab Delete/Reset | active assignment는 명시적으로 거부되거나 session 종료 후 owner가 recorder, bed, 관계를 함께 삭제함 | Lab/TestKit delete tests, Runtime ViewModel capability tests | [recorder-and-lab.feature](../../features/recorder-and-lab.feature) |
| `US-BACKUP-001` | 현재 Host와 Guest data를 하나의 VitalServer backup으로 보존함 | Settings/Advanced Backup | Host runtime state와 Guest Redis data가 검증된 artifact로 생성되고 불완전한 backup은 성공 목록에 포함되지 않음 | runtime backup workflow and compatibility tests | [update-and-recovery.feature](../../features/update-and-recovery.feature) |
| `US-UPDATE-001` | Product Update를 검증하고 적용함 | Helper Update | manifest, compatibility, artifact proof가 통과한 bundle만 적용되며 operation progress와 terminal result가 보존됨 | update workflow tests, `make dist/update/verify/dev` | [update-and-recovery.feature](../../features/update-and-recovery.feature) |
| `US-UPDATE-002` | Update 실패 시 이전 상태로 rollback함 | Update failure/recovery action | failure가 성공으로 숨겨지지 않고 rollback 결과가 별도 terminal state와 evidence로 기록됨 | rollback workflow tests, runtime update acceptance | [update-and-recovery.feature](../../features/update-and-recovery.feature) |
| `US-RECOVERY-001` | Platform Agent, Host DB 또는 Guest dependency 장애를 진단함 | Status/Advanced/Logs | 실패한 owner와 read/write/decode/permission reason이 표시되고 다른 계층이 빈/default state를 만들지 않음 | chaos tests, TS-135, runtime conformance | [update-and-recovery.feature](../../features/update-and-recovery.feature) |
| `US-UNINSTALL-001` | clean uninstall 후 잔여 상태 없이 다시 설치함 | Danger Zone/Uninstaller | VM과 managed service가 순서대로 종료되고 Platform Agent가 마지막에 내려간 뒤 receipt, runtime files, state DB가 제거됨 | `RuntimeLifecycleCleanUninstallTests`, uninstall readiness tests, TS-136 | [runtime-lifecycle.feature](../../features/runtime-lifecycle.feature) |

## 4. 공통 acceptance 원칙

모든 시나리오는 다음 원칙을 공유합니다.

1. 명령 성공은 owner가 제공한 terminal result와 필요한 proof가 있을 때만 성립합니다.
2. missing, invalid, failed, stale, empty, zero를 서로 변환하지 않습니다.
3. UI는 상태를 생성하거나 복구하지 않고 owner state를 표시하고 command를 전달합니다.
4. Host는 Guest 내부 상태를 log, process output 또는 파일명으로 추정하지 않습니다.
5. 설치와 VM build의 kernel panic, boot, rootfs, runtime smoke 실패는 compile 실패입니다.
6. `.feature` 시나리오가 자동화되기 전에는 기존 unit/integration/smoke evidence를
   해당 scenario의 실행 결과라고 부르지 않습니다.

## 5. 카탈로그 변경 규칙

- 새 사용자 여정은 기존 ID 의미를 확장하기보다 새 ID로 추가합니다.
- 사용자-visible invariant가 바뀌면 카탈로그, `.feature`, 관련 계약/테스트를 같은
  focused change에서 갱신합니다.
- 구현 세부 파일명이나 class 이름은 evidence link로만 사용하고, Given/When/Then의
  사용자 조건으로 만들지 않습니다.
- 자동 BDD runner와 step definition이 연결되면 해당 scenario tag를
  `@bdd-pending`에서 `@bdd-automated`로 바꾸고 실행 target을 `features/README.md`에
  기록합니다.
