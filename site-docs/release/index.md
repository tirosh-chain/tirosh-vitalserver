# Vital Server Helper

Vital Server Helper는 VitalServer를 더 쉽게 운영하고 지원하기 위한 macOS Helper입니다.
Helper app, runtime CLI, 관측 도구, update/repair 흐름, 문서를 함께 제공합니다.

이 문서군은 현장 검증 단계에서 Helper를 설치하고, 상태를 확인하고, 문제가 생겼을 때 어떤
자료를 전달해야 하는지 설명합니다.

## 1. 무엇을 제공하나

Vital Server Helper는 VitalServer 자체를 대체하지 않습니다. VitalServer 주변에서 운영자가
확인해야 하는 상태와 지원 자료를 모으는 역할을 합니다.

| 확인하려는 것 | Helper가 제공하는 것 |
|---|---|
| runtime이 켜져 있는가 | Helper app과 Runtime Control API의 상태 화면 |
| recorder/bed activity가 보이는가 | Recorders/Beds 화면과 observability event |
| 문제가 생겼을 때 자료를 모을 수 있는가 | logs, runtime event, support bundle |
| update를 적용할 수 있는가 | Product Update bundle 검증과 적용 흐름 |
| 제거와 재설치 복구의 차이를 이해할 수 있는가 | Clean Uninstall and Reset Installer |
| 재설치가 막힌 Mac을 정리할 수 있는가 | Reset Installer |

### 1-1. 현재 문서의 범위

현재 release 문서는 macOS Helper 기반 현장 검증 흐름을 다룹니다. 공개 installer URL,
checksum, 지원 OS matrix, 병원별 rollout 절차는 안정 release 준비 과정에서 별도 확정합니다.

이 문서에서 설명하는 기본 실행 방식은 Helper-managed runtime입니다. 이미 운영 중인
VitalServer에 연결하는 `External VitalServer mode`는 지원 예정 범위입니다.

### 1-2. 문서 읽는 순서

처음 읽는다면 아래 순서가 좋습니다.

1. [Usage](usage.md)에서 설치 후 어떤 화면과 절차를 쓰는지 봅니다.
2. [Support Scope](scope.md)에서 현재 제공하는 범위와 지원 예정 범위를 확인합니다.
3. [Runtime Status](runtime-status.md)에서 Helper app 상태값의 의미를 봅니다.
4. [Observability Events](observability-events.md)에서 event와 anomaly를 해석합니다.
5. [Clean Uninstall and Reset Installer](clean-uninstall.md)에서 내부 clean uninstall과 reset package의 차이를 봅니다.
6. [Reset Installer](reset-installer.md)는 재설치가 막혔을 때만 봅니다.

## 2. 현재 설치 대상

현재 현장 검증용 설치 대상은 macOS host입니다.

| 구분 | 현재 범위 |
|---|---|
| host OS | macOS |
| 설치 파일 | macOS Helper package |
| 포함 실행물 | Helper app, `vitalserver-vm` runtime CLI |
| runtime 위치 | macOS host 위의 local VM/runtime |

Windows host installer와 Linux host installer는 아직 release 범위가 아닙니다. 다만 구조상
Host/Guest/PWA 경계를 나누고 있어, 이후 platform 확장을 별도 주제로 다룰 수 있게 설계합니다.

## 3. 중요한 경계

- 의료 행위나 임상 판단을 자동화하지 않습니다.
- VitalServer 원 프로젝트와 공식 배포물을 대체하지 않습니다.
- 환자 데이터, 병원 내부 IP, 인증 정보, token, 로그 원문은 공개 GitHub issue에 올리지 않습니다.
- runtime 상태와 event는 운영 판단을 돕는 자료이며, 장애 원인 확정이나 임상 판단의 단독 근거가 아닙니다.
- 안정 지원 계약, SLA, 보안 인증, 병원별 검수 완료는 별도 release 절차에서 확정합니다.
