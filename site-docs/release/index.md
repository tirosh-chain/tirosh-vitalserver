# Vital Server Helper

Vital Server Helper는 macOS host에서 VitalServer 운영을 보조하기 위한 Helper app,
runtime CLI, 관측 도구, 문서를 포함하는
사전 검증용 배포본입니다.

이 release 문서는 사전 검증용 배포본의 설치와 확인에 필요한 정보를 정리합니다.
정식 배포용 installer URL, checksum, 지원 OS matrix, 병원별 rollout 절차는 release 준비
과정에서 별도 문서로 확정합니다.

## 1. Release Documents

| 문서 | 내용 |
|---|---|
| [Usage](usage.md) | 사전 검증용 배포본 생성 명령, 설치 후 CLI, 주요 설치 경로 |
| [Force Clean Uninstaller](clean-uninstall.md) | fresh install이 막힌 Mac에 전달할 강제 정리 복구 절차 |
| [Capabilities](scope.md) | 현재 확인할 수 있는 항목, VitalServer 지원 범위, 미지원 항목, roadmap |
| [Status Reference](runtime-status.md) | Helper app에서 보는 runtime, recorder, bed, service 상태 |
| [Observability Events](observability-events.md) | Observability 화면의 event, anomaly, relationship history 의미 |

## 2. Supported Platform

현재 사전 검증용 배포본은 macOS host에 설치되는 Helper 패키지만 다룹니다. Windows 또는
Linux host용 설치물은 현재 release 범위가 아닙니다.

| 구분 | 현재 범위 |
|---|---|
| 지원 host OS | macOS |
| 설치 artifact | macOS Helper 사전 검증용 패키지 |
| 포함 실행물 | Helper app, `vitalserver-vm` runtime CLI |
| runtime 실행 위치 | macOS host 위의 local VM/runtime |

| 현재 범위 아님 | 상태 |
|---|---|
| Windows host installer | 제공하지 않음 |
| Linux host installer | 제공하지 않음 |
| 공개 안정 installer URL | 아직 확정하지 않음 |
| checksum/지원 OS matrix | 아직 확정하지 않음 |

## 3. Limitations

- 의료 행위나 임상 판단을 자동화하지 않습니다.
- VitalServer 원 프로젝트와 공식 배포물을 대체하지 않습니다.
- 병원 승인 없는 환자 데이터 외부 전송을 기본 기능으로 설명하지 않습니다.
- 환자 데이터, 병원 내부 IP, 인증 정보, token, 로그 원문은 공개 GitHub issue에
  올리지 않습니다.
- runtime 상태와 이벤트는 운영 판단 보조 정보이며, 장애 원인 확정이나 임상 판단의
  단독 근거가 아닙니다.
- 사전 검증용 release 문서는 안정 지원 계약, SLA, 보안 인증, 병원별 검수 완료를 의미하지
  않습니다.
- installer, checksum, 지원 OS matrix, 병원별 설치 절차는 안정 release 전까지 확정된
  계약으로 보지 않습니다.
