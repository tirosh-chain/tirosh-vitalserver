# Vital Server Helper

이 site는 `tirosh-vitalserver` repository의 preview 문서입니다. Vital Server Helper는
VitalDB 또는 Vital Server의 공식 배포물이 아닙니다. VitalDB, Vital Server, Vital
Recorder, VRecorder 관련 이름과 권리는 각 원 소유자에게 있습니다.

현재 문서군은 공개 안정 버전 안내가 아닙니다. release artifact, installer download
path, checksum, 지원 OS matrix, 병원별 설치 절차는 아직 확정되지 않았습니다.

## What This Site Is For

이 site는 두 가지 질문에 답합니다.

| 질문 | 문서군 | 독자 |
|---|---|---|
| release 전에 무엇을 확인해야 하는가? | [Release](release/index.md) | 도입 검토자, 운영 검토자, 연구 과제 관계자 |
| 이 repository는 어떤 구조와 검증 기준으로 움직이는가? | [Dev](dev/index.md) | 개발자, 기술 검토자, runtime/API/testkit 유지보수자 |

## Current Facts

| 항목 | 현재 상태 |
|---|---|
| repository | macOS runtime, Runtime Control PWA, observer, audit proxy, testkit 포함 |
| release docs | preview와 도입 검토 기준 |
| stable release | 아직 확정되지 않음 |
| official VitalDB/Vital Server distribution | 아님 |

## Boundaries

- Vital Server 자체 기능을 대체하지 않습니다.
- 의료 행위나 임상 판단을 자동화하지 않습니다.
- missing, invalid, failed, stale, empty 상태는 서로 다른 의미로 유지해야 합니다.
- 공개 GitHub issue에는 환자 정보, 병원 내부 IP, 인증 정보, token을 올리지 않습니다.

## GitHub

재현 가능한 코드 문제, 문서 오류, 범위가 작은 변경 제안은 GitHub repository에서
다룹니다. 병원별 설치, 보안, 개인정보 협의는 공개 GitHub issue로 다루지 않습니다.

- Repository: <https://github.com/tirosh-chain/tirosh-vitalserver>
- Issues: <https://github.com/tirosh-chain/tirosh-vitalserver/issues>
