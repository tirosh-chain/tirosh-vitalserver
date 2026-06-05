# Package Map

이 repository는 monorepo입니다. 각 package와 app은 역할 경계를 유지해야 합니다.

## Top-level 구조

| 경로 | 역할 |
|---|---|
| `apps/` | 실행 app, UI, runtime, observer, proxy |
| `packages/` | Python package 기반 devtools, guest tools, testkit |
| `infra/` | host proxy, swagger, deployment infrastructure |
| `config/` | build, packaging, testkit 설정 |
| `scripts/` | repository-level 운영/검증 script |
| `vendor/` | upstream VitalServer fork submodule |
| `docs/` | 정식 문서 |
| `drafts/` | 정식 반영 전 문서 초안 |

## 공개/내부 경계

| 항목 | 공개 여부 | 설명 |
|---|---|---|
| Vital Server Helper | 공개 | release 문서의 최상위 서비스명 |
| Health Check | 공개 | Vital Server Helper가 제공하는 기능 |
| Runtime Control API | dev 중심 | public UI와 host runtime 사이의 계약 |
| Linux VM guest stack | dev 중심 | 동일 service appliance 운용환경 |
| wrapper/preload | dev 전용 | upstream 전제 보정 |
| devtools | dev 전용 | packaging/build machine tooling |

## dependency 방향

Domain/Core는 Host, Guest, filesystem, network, logs, command output을 직접 읽지 않습니다.

Application/Workflow는 port를 통해 명시 상태를 읽고, Domain/Core policy를 호출하고,
adapter가 수행할 command/effect를 조립합니다.

Adapters/Host/Guest infrastructure는 외부 상태를 읽고 씁니다. 읽기 실패, 권한 실패,
decode 실패, dependency 실패는 명시적인 typed result로 inward layer에 전달합니다.

Presentation/UI는 명시 상태를 표시합니다. UI가 domain state를 추측하거나 복구하지 않습니다.
