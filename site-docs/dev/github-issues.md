# Repository Workflow

이 문서는 Vital Server Helper repository에서 issue와 pull request를 다룰 때 필요한
최소 기준을 설명합니다.

목표는 큰 커뮤니티 운영 체계를 만드는 것이 아닙니다. 재현 가능한 기술 문제와
범위가 분명한 변경을 작은 팀이 처리할 수 있는 형태로 정리하는 것입니다.

## Good Issues

| 유형 | 기준 |
|---|---|
| Bug report | 재현 절차, 기대 결과, 실제 결과, 관련 상태 문서 또는 로그가 있음 |
| Documentation issue | 깨진 link, 틀린 command, 불명확한 설치/운영 설명 |
| Contract issue | API response, runtime document, Health Check 상태 의미가 깨짐 |
| Testkit issue | simulated recorder, `.vital` upload, smoke/load scenario 재현 가능 |
| Contribution proposal | 변경 목적, 영향 범위, 관련 test 계획이 있음 |

GitHub Issues: <https://github.com/tirosh-chain/tirosh-vitalserver/issues>

## Not For Public Issues

- 환자 정보, 병원 내부 IP, 인증 정보, 비밀번호, token, 개인식별정보
- 병원별 보안 정책 협의
- 현장 설치 일정, 장비 반입, 네트워크 변경 승인
- 의료 행위 또는 임상 판단에 관한 요청

## Issue Shape

```text
Summary:
Environment:
Expected:
Actual:
Explicit state:
Reproduction:
Related logs or documents:
```

`missing`, `invalid`, `failed`, `stale`, `empty`는 서로 다른 의미입니다. read failure를
empty success로 쓰거나, stale state를 healthy state로 추정하지 않습니다.

## Pull Request Shape

- 한 가지 목적에 집중합니다.
- package 경계를 지킵니다.
- domain/core code는 외부 상태를 직접 읽지 않습니다.
- contract 변경은 관련 문서와 test를 함께 갱신합니다.
- recovery, update, parsing, settings, Health Check 변경은 실패 case test를 포함합니다.
- release 문서의 운영 주장과 dev 문서의 구현 근거가 어긋나지 않게 합니다.
