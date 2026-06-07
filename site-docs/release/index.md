# Vital Server Helper

Vital Server Helper는 VitalDB/Vital Server를 대체하는 제품이 아닙니다. macOS host에서
Vital Server 운영을 보조하기 위한 Helper app, runtime CLI, 관측 도구, 문서를 포함하는
preview package입니다.

현재 release 문서는 공개 안정 버전 안내가 아니라 repository preview 안내입니다. installer
download path, checksum, 지원 OS matrix, 병원별 설치 절차는 아직 확정되지 않았습니다.

## Release Documents

| 문서 | 내용 |
|---|---|
| [Usage](usage.md) | preview package build entrypoint, 설치 후 CLI, 주요 설치 경로 |
| [Capabilities](scope.md) | 현재 확인할 수 있는 항목, VitalDB와의 관계, 미지원 항목, roadmap |
| [Status Reference](runtime-status.md) | 운영자가 보는 runtime 상태와 이벤트 의미 |

## Supported Platform

현재 release preview는 macOS host에 설치되는 Helper package만 다룹니다. Windows 또는
Linux host용 설치물은 현재 release 범위가 아닙니다.

| 구분 | 현재 범위 |
|---|---|
| 지원 host OS | macOS |
| 설치 artifact | macOS Helper package preview |
| 포함 실행물 | Helper app, `vitalserver-vm` runtime CLI |
| runtime 실행 위치 | macOS host 위의 local VM/runtime |

| 현재 범위 아님 | 상태 |
|---|---|
| Windows host installer | 제공하지 않음 |
| Linux host installer | 제공하지 않음 |
| 공개 안정 installer URL | 아직 확정하지 않음 |
| checksum/지원 OS matrix | 아직 확정하지 않음 |

## Limitations

- 의료 행위나 임상 판단을 자동화하지 않습니다.
- VitalDB/Vital Server 원 프로젝트와 공식 배포물을 대체하지 않습니다.
- 병원 승인 없는 환자 데이터 외부 전송을 기본 기능으로 설명하지 않습니다.
- 환자 데이터, 병원 내부 IP, 인증 정보, token, 로그 원문은 공개 GitHub issue에
  올리지 않습니다.
- runtime 상태와 이벤트는 운영 판단 보조 정보이며, 장애 원인 확정이나 임상 판단의
  단독 근거가 아닙니다.
- preview release 문서는 안정 지원 계약, SLA, 보안 인증, 병원별 검수 완료를 의미하지
  않습니다.
- installer, checksum, 지원 OS matrix, 병원별 설치 절차는 안정 release 전까지 확정된
  계약으로 보지 않습니다.
