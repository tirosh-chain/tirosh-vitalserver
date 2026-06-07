# Release Scope

## Relation To VitalDB

| 항목 | 관계 |
|---|---|
| VitalDB/Vital Server | 원 프로젝트와 공식 배포물을 대체하지 않음 |
| Vital Recorder/VRecorder | 연결 상태와 activity를 관측 대상으로 둠 |
| `.vital` 파일 | 저장 상태와 읽기 가능성을 확인해야 하는 운영 대상 |
| Helper | runtime, 상태 확인, update, log 확인을 위한 별도 보조 계층 |

VitalDB, Vital Server, Vital Recorder, VRecorder 관련 이름과 권리는 각 원 소유자에게
있습니다.

## Provided In This Repository

| 항목 | 현재 repository 구성 |
|---|---|
| macOS Helper app | `apps/vitalserver-macos-runtime`의 `VitalServerHelper` target |
| runtime CLI | `apps/vitalserver-macos-runtime`의 `vitalserver-vm` target |
| Runtime Control PWA | `apps/vitalserver-runtime-pwa` |
| VitalDB observer | `apps/vitaldb-observer` |
| Audit proxy | `apps/vitalserver-audit-proxy` |
| Testkit | recorder simulation과 검증 도구 package |
| Docs | `site-docs/` MkDocs 문서 |

## Not Release Scope Yet

| 항목 | 현재 상태 |
|---|---|
| Windows host | release 범위 아님 |
| Linux host | release 범위 아님 |
| 공개 installer URL | 미확정 |
| checksum 배포 | 미확정 |
| 지원 OS matrix | 미확정 |
| 병원별 설치 절차 | field validation 이후 확정 |

## Roadmap

| 단계 | 내용 |
|---|---|
| Preview docs | 현재 repository 구성과 미확정 release 항목 정리 |
| Release artifact | installer, checksum, 지원 OS, 알려진 제한 사항 고정 |
| Field validation | 병원별 네트워크, 저장 위치, 권한, 운영 절차 확인 |
| Operation docs | 실제 artifact와 일치하는 설치/운영/rollback 문서 작성 |
