# API Contracts

이 문서는 Vital Server Helper 관련 API 계약의 위치와 역할을 정리합니다.

## API 목록

| API | 위치 | 역할 |
|---|---|---|
| Runtime Control API | `docs/runtime/macos/runtime-control.openapi.json` | PWA/native shell과 host runtime 사이의 contract |
| VitalDB Observer API | `docs/api/vitaldb-observer.openapi.yaml` | observer container 내부 API |
| Audit Proxy API | `docs/api/audit-proxy.openapi.yaml` | command audit sidecar endpoint |
| VitalServer API | `docs/api/vitalserver.openapi.yaml` | upstream VitalServer route에서 추출한 API 문서 |

## Runtime Control API

Runtime Control API는 UI와 host runtime 사이의 primary contract입니다.

PWA는 observer container나 guest internals를 직접 읽지 않습니다. runtime read model과
Runtime Control API가 제공하는 명시 상태를 사용합니다.

## Observer API

VitalDB Observer API는 Redis와 proxy/access log를 읽어 observation snapshot을 만듭니다.
이 API는 내부 collector API입니다. 최종 product-facing source of truth는 runtime
observability read model입니다.

## Audit Proxy API

Audit Proxy API는 VRecorder command 흐름과 audit event를 관측하기 위한 sidecar
contract입니다.

## 문서 작성 기준

- API 문서에는 request, response, failure state를 구분해서 적습니다.
- read failure를 empty success로 표현하지 않습니다.
- stale state와 missing state를 구분합니다.
- UI fallback은 display label 수준으로 제한합니다.
