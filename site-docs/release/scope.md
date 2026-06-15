# Support Scope

이 문서는 Vital Server Helper가 현재 무엇을 지원하고, 무엇을 지원 예정으로 두는지 정리합니다.

## 1. 지원 대상

Vital Server Helper는 VitalServer 운영을 보조하는 별도 계층입니다. VitalServer 공식 배포와 별도로 제공되는 Helper project입니다.

| 대상 | Helper에서의 관계 |
|---|---|
| VitalServer | runtime 상태 확인과 운영 보조 대상 |
| Vital Recorder / VRecorder | 연결 상태와 activity 관측 대상 |
| Bed | recorder와의 관계와 activity 관측 대상 |
| `.vital` 파일 | 향후 sanity check 대상 |
| Helper runtime | 상태 확인, update, repair, log 수집을 제공하는 보조 계층 |

VitalServer, Vital Recorder, VRecorder 관련 이름과 권리는 각 원 소유자에게 있습니다.

## 2. 현재 제공하는 것

현재 현장 검증 범위는 “VitalServer process를 실행한다”에서 끝나지 않습니다. 운영자가 상태를
확인하고, 문제가 생겼을 때 지원 자료를 모을 수 있는지를 함께 봅니다.

| 운영자가 궁금해하는 질문 | 현재 제공하는 것 |
|---|---|
| runtime이 실행 중인가? | Helper app과 runtime CLI의 상태 확인 |
| recorder activity가 보이는가? | recorder observer와 audit proxy 기반 관측 |
| bed 관계를 볼 수 있는가? | Beds 화면과 relationship history |
| 장애 조사 자료를 모을 수 있는가? | status, event, logs, support 자료 |
| update 입력을 검증할 수 있는가? | Product Update bundle verify/apply 흐름 |
| 재설치가 막힌 Mac을 정리할 수 있는가? | Reset for Reinstall command |
| 기존 VitalServer data import archive를 만들 수 있는가? | Troubleshooting Tools의 data import command |

## 3. 포함 구성 요소

| 구성 요소 | repository 위치 |
|---|---|
| macOS Helper app | `apps/vitalserver-macos-runtime` |
| runtime CLI | `apps/vitalserver-macos-runtime`의 `vitalserver-vm` target |
| Runtime Control PWA | `apps/vitalserver-runtime-pwa` |
| Recorder observer | `apps/vitaldb-observer` |
| Audit proxy | `apps/vitalserver-audit-proxy` |
| Testkit | recorder simulation과 검증 도구 package |
| Docs | `site-docs/` MkDocs 문서 |

## 4. 아직 제공하지 않는 것

아래 항목은 현재 현장 검증 release에서 제공하는 기능이 아닙니다.

| 항목 | 상태 |
|---|---|
| `.vital` 파일 sanity check | 지원 예정 |
| External VitalServer mode | 기존 VitalServer 연결 지원 예정 |
| Windows host installer | release 범위 아님 |
| Linux host installer | release 범위 아님 |
| 공개 installer URL | 안정 release 준비 과정에서 확정 |
| checksum 배포 | 안정 release 준비 과정에서 확정 |
| 지원 OS matrix | 안정 release 준비 과정에서 확정 |
| 병원별 rollout 절차 | field validation 이후 확정 |
| 장기 운영 SLA | 별도 계약과 운영 정책에서 다룸 |

## 5. 지원 예정 방향

| 단계 | 내용 |
|---|---|
| 현장 검증 문서 | 현재 설치, 상태 확인, 강제 정리, event 해석 흐름 정리 |
| Release artifact | installer, checksum, 지원 OS, 알려진 제한 사항 고정 |
| External VitalServer mode | 기존 VitalServer deployment에 연결하고 Helper proxy/observer stack으로 관측 |
| Field validation | 병원별 네트워크, 저장 위치, 권한, 운영 절차 확인 |
| Operation docs | 실제 artifact와 일치하는 설치, 운영, rollback 문서 작성 |
