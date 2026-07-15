# Product acceptance features

이 디렉터리는 [제품 사용 시나리오 카탈로그](../docs/product/user-scenarios.md)의
사용자-visible acceptance intent를 Gherkin `.feature`로 관리합니다.

## 현재 실행 상태

현재 feature는 BDD runner에 연결되지 않은 명세입니다. 모든 scenario에는
`@bdd-pending` tag가 있으며 `make product/scenarios/check`는 다음 구조만 검증합니다.

- 카탈로그 ID와 feature의 `@US-*` tag가 1:1로 일치함
- 각 scenario가 정확히 하나의 scenario ID와 BDD 실행 상태 tag를 가짐
- 각 scenario에 `Given`, `When`, `Then`이 존재함

이 검증은 실제 제품 실행이나 Gherkin runner의 step execution을 대신하지 않습니다.
기존 unit/integration/smoke test는 카탈로그의 acceptance evidence이고, feature 자체가
통과했다는 뜻은 아닙니다.

## 작성 규칙

- English Gherkin keyword를 사용하고 domain 문장은 한국어로 작성합니다.
- 하나의 `Scenario`는 정확히 하나의 `@US-*` ID를 가집니다.
- 자동화 전에는 `@bdd-pending`, step definition과 제품 adapter가 연결된 뒤에는
  `@bdd-automated`를 사용합니다.
- Given은 명시적인 owner state, When은 사용자 action, Then은 사용자-visible 결과를
  기술합니다.
- log, 파일명, 이전 출력 또는 데이터 부재에서 상태를 추론하는 step을 만들지 않습니다.
- 구현 class나 test 이름은 feature가 아니라 카탈로그 evidence에 기록합니다.

## 자동화 도입 기준

BDD runner를 연결할 때 step definition이 별도의 모의 domain state를 새로 만들면 안 됩니다.
빠른 contract scenario는 실제 Domain/Application port를 호출하고, 설치·재부팅·network
scenario는 package/runtime acceptance fixture를 호출해야 합니다. 외부 조건 때문에 실행할
수 없는 scenario는 skip 성공으로 바꾸지 말고 명시적인 unavailable/blocked result를
보고해야 합니다.
