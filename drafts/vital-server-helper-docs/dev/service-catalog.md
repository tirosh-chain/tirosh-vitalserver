# Service Catalog

이 문서는 Vital Server Helper를 구성하는 repository 서비스와 package 책임을 정리합니다.

## 서비스 목록

| 서비스/패키지 | 공개 문서 노출 | 책임 |
|---|---|---|
| `apps/vitalserver` | VitalServer service | upstream VitalServer wrapper와 runtime shim |
| `apps/vitalserver-macos-runtime` | Vital Server Helper | macOS Helper app, host runtime, VM orchestration, packaging |
| `apps/vitalserver-runtime-pwa` | Runtime Control UI | browser/PWA 기반 runtime control surface |
| `apps/vitaldb-observer` | Health Check 내부 collector | Redis/proxy 기반 VitalDB observation snapshot 생성 |
| `apps/vitalserver-recorder-ingress` | command audit 기능 | VRecorder command/audit event sidecar |
| `packages/vitalserver-testkit` | 검증 도구 | simulated recorder, `.vital` upload, smoke/load validation |
| `packages/vitalserver-devtools` | dev 전용 | build machine packaging, VM/update bundle tooling |
| `packages/vitalserver-guest-tools` | dev 전용 | Linux guest-side runtime state, update, logs, repair commands |
| `infra/macos-nginx` | release installation에서 간접 설명 | Mac host proxy config and launchd template |

## 책임 경계

`apps/vitalserver`는 upstream VitalServer를 제품 실행 단위로 감쌉니다. upstream code의
Windows 중심 전제는 wrapper와 preload에서 흡수합니다.

`apps/vitalserver-macos-runtime`는 Mac hardware appliance 위에서 VM lifecycle,
host proxy, packaging, update, recovery entrypoint를 관리합니다.

`apps/vitalserver-runtime-pwa`는 cross-platform Runtime Control UI입니다. host별
native UI를 반복 구현하지 않고 같은 API contract 뒤에서 local/remote runtime을
다룹니다.

`apps/vitaldb-observer`는 Redis와 proxy/access log를 읽어 VitalDB observation snapshot을
만듭니다. 최종 운영 상태 source of truth는 runtime read model입니다.

`packages/vitalserver-guest-tools`는 Linux guest 내부 상태, update activation,
container logs, runtime state writer를 담당합니다.

`packages/vitalserver-testkit`는 실제 VRecorder 없이 recorder stream, `.vital` upload,
smoke/load 검증을 수행합니다.
