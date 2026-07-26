# Vital Server Helper

이 문서 site는 `tirosh-vitalserver` repository의 사전 검증 문서입니다. Vital Server Helper는
VitalServer 운영을 지원하기 위한 별도 Helper project입니다. VitalServer, Vital
Recorder, VRecorder 관련 이름과 권리는 각 원 소유자에게 있습니다.

현재 문서군은 공개 안정 버전 안내가 아닙니다. release artifact, installer download path,
checksum, 지원 OS matrix, 병원별 설치 절차는 아직 확정되지 않았습니다.

Vital Server Helper는 병원 내부망 가까이에 설치된 VitalServer를 운영자가 확인하고
장애 조사에 필요한 자료를 모으기 위한 preview 단계의 Helper project입니다. 현재 문서군은 설치형
운영 환경에서 무엇을 확인할 수 있는지, 아직 무엇이 확정되지 않았는지, 개발자가
어떤 기준으로 구조를 나누고 있는지를 설명합니다.

## 1. 문서 site의 역할

이 문서 site는 두 가지 질문에 답합니다.

| 질문 | 문서군 | 독자 |
|---|---|---|
| release 전에 무엇을 확인할 수 있고, 아직 무엇이 범위 밖인가? | [Release](release/index.md) | 도입 검토자, 운영 검토자, 연구 과제 관계자 |
| 이 repository는 어떤 구조와 검증 기준으로 움직이는가? | [Dev](dev/index.md) | 개발자, 기술 검토자, runtime/API/Product Lab/dev testkit 유지보수자 |

## 2. 현재 상태

| 항목 | 현재 상태 |
|---|---|
| repository | macOS runtime, Runtime Control PWA, Product Lab, observer, recorder ingress, dev testkit 포함 |
| release 문서 | preview 검증과 도입 검토 기준 |
| 안정 release | 아직 확정되지 않음 |
| VitalServer와의 관계 | VitalServer 공식 배포와 별도의 Helper project |

## 3. 중요한 경계

- VitalServer 자체 기능을 대체하지 않습니다.
- 의료 행위나 임상 판단을 자동화하지 않습니다.
- missing, invalid, failed, stale, empty 상태는 서로 다른 의미로 유지해야 합니다.
- 공개 GitHub issue에는 환자 정보, 병원 내부 IP, 인증 정보, token을 올리지 않습니다.

## 4. GitHub

재현 가능한 코드 문제, 문서 오류, 범위가 작은 변경 제안은 GitHub repository에서
다룹니다. 병원별 설치, 보안, 개인정보 협의는 공개 GitHub issue로 다루지 않습니다.

- Repository: <https://github.com/tirosh-chain/tirosh-vitalserver>
- Issues: <https://github.com/tirosh-chain/tirosh-vitalserver/issues>
