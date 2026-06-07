# Capabilities

## Relation To VitalDB

| 항목 | 관계 |
|---|---|
| VitalDB/Vital Server | 원 프로젝트와 공식 배포물을 대체하지 않음 |
| Vital Recorder/VRecorder | 연결 상태와 activity를 관측 대상으로 둠 |
| `.vital` 파일 | 향후 sanity check 대상. 현재 preview release에서 제공하는 기능은 아님 |
| Helper | runtime, 상태 확인, update, log 확인을 위한 별도 보조 계층 |

VitalDB, Vital Server, Vital Recorder, VRecorder 관련 이름과 권리는 각 원 소유자에게
있습니다.

## Current Capabilities

현재 preview 문서가 설명하는 범위는 Vital Server process 실행에 그치지 않습니다.
병원 내부망 가까이에 설치된 runtime이 켜져 있는지, Recorder activity가 보이는지,
장애 조사에 필요한 상태와 로그를 확인할 수 있는지를 중심으로 다룹니다.

| 운영자가 궁금해하는 질문 | 현재 범위 |
|---|---|
| Vital Server runtime이 실행 중인가? | Helper app과 runtime CLI에서 상태 확인 |
| Recorder activity가 보이는가? | VitalDB observer와 audit proxy 기반 관측 |
| 장애 조사에 필요한 자료를 모을 수 있는가? | runtime status, event history, log 확인 |
| preview package를 만들고 기본 검증을 할 수 있는가? | build command, testkit, runtime smoke test |
| update 입력을 검증할 수 있는가? | Product Update bundle verify/apply CLI |

## Included Components

| 항목 | 현재 repository 구성 |
|---|---|
| macOS Helper app | `apps/vitalserver-macos-runtime`의 `VitalServerHelper` target |
| runtime CLI | `apps/vitalserver-macos-runtime`의 `vitalserver-vm` target |
| Runtime Control PWA | `apps/vitalserver-runtime-pwa` |
| VitalDB observer | `apps/vitaldb-observer` |
| Audit proxy | `apps/vitalserver-audit-proxy` |
| Testkit | recorder simulation과 preview 검증 도구 package |
| Docs | `site-docs/` MkDocs 문서 |

## Limitations and Planned Work

| 항목 | 현재 상태 |
|---|---|
| `.vital` 파일 sanity check | 지원 예정. 현재 preview release 범위 아님 |
| Windows host | release 범위 아님 |
| Linux host | release 범위 아님 |
| 공개 installer URL | 미확정 |
| checksum 배포 | 미확정 |
| 지원 OS matrix | 미확정 |
| 병원별 설치 절차 | field validation 이후 확정 |
| 장기 운영 SLA | 현재 문서 범위 아님 |

## Roadmap

| 단계 | 내용 |
|---|---|
| Preview docs | 현재 repository 구성과 미확정 release 항목 정리 |
| Release artifact | installer, checksum, 지원 OS, 알려진 제한 사항 고정 |
| Field validation | 병원별 네트워크, 저장 위치, 권한, 운영 절차 확인 |
| Operation docs | 실제 artifact와 일치하는 설치/운영/rollback 문서 작성 |
