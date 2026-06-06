# Vital Server Helper

Vital Server Helper는 VitalDB Vital Server를 병원 내부망 또는 연구기관 현장
환경에서 운영하기 위한 비공식 deployment and operations toolkit입니다.

이 프로젝트는 VitalDB 또는 Vital Server의 공식 배포물이 아닙니다. VitalDB,
Vital Server, Vital Recorder, VRecorder 관련 이름과 권리는 각 원 소유자에게
있습니다. Vital Server Helper는 Vital Server를 대체하지 않고, 현장 운영,
상태 확인, 업데이트, 장애 대응을 돕는 별도 운영 계층을 제공합니다.

Vital Server가 제공하는 연구 및 데이터 수집 기능을 기반으로, Helper는 병원 현장에서 해당 기능을 보다 예측 가능하게 운영하기 위한 보조 계층에 집중합니다.

## What This Site Is For

이 site는 두 가지 질문에 답합니다.

| 질문                                                  | 문서군                      | 독자                                                  |
| ----------------------------------------------------- | --------------------------- | ----------------------------------------------------- |
| 이 도구가 우리 현장에 맞는가?                         | [Release](release/index.md) | 병원 IT 담당자, 연구 과제 관계자, 운영자, 도입 검토자 |
| 이 repository는 어떤 구조와 검증 기준으로 움직이는가? | [Dev](dev/index.md)         | 개발자, 기술 검토자, runtime/API/testkit 유지보수자   |

## Operating Assumptions

- 기본 운영 위치는 병원 내부망입니다.
- 외부 outbound 또는 cloud 연계는 병원 정책이 허용할 때만 별도로 검토합니다.
- Health Check는 운영 상태를 표시합니다. 의료 행위나 임상 판단을 자동화하지 않습니다.
- missing, invalid, failed, stale, empty 상태는 서로 다른 의미로 유지합니다.
- 공개 GitHub issue에는 환자 정보, 병원 내부 IP, 인증 정보, token을 올리지 않습니다.

## GitHub

재현 가능한 코드 문제, 문서 오류, 범위가 작은 변경 제안은 GitHub repository에서
다룹니다. 병원별 설치, 보안, 개인정보 협의는 공개 GitHub issue로 다루지 않습니다.

- Repository: <https://github.com/tirosh-chain/tirosh-vitalserver>
- Issues: <https://github.com/tirosh-chain/tirosh-vitalserver/issues>
