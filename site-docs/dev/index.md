# Dev Documentation

Dev 문서는 Vital Server Helper가 어떤 구조와 기준으로 만들어지는지 설명합니다.

Release 문서가 설치와 사용 흐름을 다룬다면, Dev 문서는 그 뒤의 판단을 다룹니다.
Host/Guest 경계, runtime contract, package 책임, 검증 기준을 통해 Helper가 현장 운영
제품으로 확장될 수 있는 구조인지 확인할 수 있습니다.

Vital Server Helper의 목적은 VitalServer 운영을 지원하는 것입니다. 현재 사전 검증용
release는 Helper-managed runtime을 중심으로 다룹니다. 이미 운영 중인 VitalServer에
연결해 상태 확인, recorder/bed 관측, 로그/지원 자료 수집을 제공하는
`External VitalServer mode`는 지원 예정 범위입니다. 두 실행 방식은 같은 이름으로
섞지 않고, 상태 소유권과 측정 가능한 정보를 contract에서 분리합니다.

## 1. 읽는 방법

처음 읽는다면 아래 순서가 좋습니다.

1. [Architecture](architecture.md)에서 Host, Linux guest, PWA, Runtime Control API가
   어떻게 분리되는지 봅니다.
2. [Runtime Contracts](runtime-contracts.md)에서 상태 의미와 API surface를 확인합니다.
3. [Repository Map](repository-map.md)에서 repository 안의 실행 단위와 책임을 봅니다.
4. [Delivery & Validation](delivery-validation.md)에서 package 생성, test, GitHub workflow를 봅니다.

## 2. 설계 기준

- Host는 runtime/process/filesystem 상태를 소유합니다.
- Guest는 Host가 제공한 명시 contract를 소비합니다.
- Domain/Core는 외부 상태를 직접 읽지 않습니다.
- missing, invalid, failed, stale, empty는 서로 다른 의미로 유지합니다.
- Vital Server integration은 Helper runtime contract 뒤에서 명시적으로 연결합니다.
- release 문서의 운영 주장과 dev 문서의 구현 근거가 서로 어긋나지 않아야 합니다.

## 3. 기술 역량 신호

이 문서군은 기술 용어 자체보다 현장 제품을 만들 때 필요한 판단과 경계를 보여주는 데
목적이 있습니다.

| 역량 | 이 프로젝트에서 드러나는 방식 |
|---|---|
| 현장 운영 제품화 | macOS host, Linux guest, proxy, update, recovery, sleep prevention을 하나의 운영 표면으로 묶음 |
| 기존 VitalServer 지원 예정 | 기존 운영 환경에 연결하는 External mode를 별도 소유권과 상태 contract로 설계 |
| 상태 해석 안정성 | missing, invalid, failed, stale, empty를 합치지 않고 UI/API까지 같은 의미로 전달 |
| Clean Architecture 적용 | 핵심 판단과 외부 작업을 분리해 변경 영향을 제한하고, VM/Redis/nginx 없이도 상태 판단과 실패 케이스를 테스트 |
| DDD 기반 언어 정리 | recorder, bed, runtime, observer, support bundle 같은 운영 개념을 코드와 문서에서 같은 뜻으로 사용 |
| 반복 검증 체계 | testkit, contract test, runtime chaos, release check로 실제 장비가 없어도 주요 흐름을 재현 |

Clean Architecture와 DDD는 이름 자체보다 효과가 중요합니다. 이 repository에서는 상태 소유자,
핵심 판단, 외부 작업, 표시 책임을 나눠서 External VitalServer mode, managed runtime,
update/recovery 같은 기능이 서로의 의미를 흐리지 않게 합니다. 또한 실제 VM, Redis,
nginx를 항상 준비하지 않아도 missing, failed, stale 같은 상태 판단과 실패 케이스를
반복 검증할 수 있게 합니다.

## 4. 문서 구성

| 문서 | 역할 |
|---|---|
| [Architecture](architecture.md) | 제품 구조, Host/Guest, Linux VM, PWA, 1차 hardware target 설명 |
| [Runtime Contracts](runtime-contracts.md) | 상태 의미, Runtime Control, Observer, Audit Proxy API 계약 설명 |
| [Repository Map](repository-map.md) | 실행 단위, package 책임, monorepo 경계 설명 |
| [Delivery & Validation](delivery-validation.md) | package/update bundle 생성, testkit, runtime chaos, release 검증, GitHub workflow 설명 |

## 5. GitHub 사용

GitHub issue와 pull request는 재현 가능한 상태, contract, test 기준으로 다룹니다.
병원별 설치, 보안, 개인정보 협의는 공개 GitHub issue로 다루지 않습니다.

GitHub Issues: <https://github.com/tirosh-chain/tirosh-vitalserver/issues>
