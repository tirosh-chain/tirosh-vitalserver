# Vital Server Helper

Vital Server Helper는 Vital Server를 병원 내부망에서 운영할 때 필요한 현장
appliance 계층입니다. VRecorder 연결 상태, `.vital` 저장 데이터, runtime service
상태를 한 곳에서 확인할 수 있도록 구성합니다.

이 문서군은 도입 검토자가 아래 질문에 답할 수 있도록 작성합니다.

- 이 도구가 어떤 현장 문제를 다루는가?
- 병원 내부망 운영과 cloud 선택 모드는 어떻게 다른가?
- 설치 전 무엇을 확인해야 하는가?
- Health Check 결과를 어떻게 해석해야 하는가?
- 공개 GitHub issue로 다룰 수 있는 문제와 다루면 안 되는 문제는 무엇인가?

## Preview Status

현재 문서는 공개 안정 버전 안내가 아니라 preview 문서와 도입 검토를 위한 문서입니다.
installer 다운로드 위치, checksum, 지원 OS version, rollback 절차는 안정 버전이
확정될 때 release note에 함께 기록합니다.

## 관계와 책임 범위

Vital Server Helper는 VitalDB 또는 Vital Server의 공식 배포물이 아닙니다.

- Vital Server를 직접 대체하지 않습니다.
- VitalDB/Vital Server/Vital Recorder/VRecorder의 상표와 권리는 원 소유자에게 있습니다.
- 병원 내부망 운영, 상태 확인, 업데이트, 장애 대응을 돕는 별도 운영 계층입니다.
- 의료 행위나 임상 판단을 자동화하지 않습니다.

## Field Problem

Vital Server는 연구와 데이터 수집에 필요한 핵심 기능을 제공합니다. Helper는 그
기능을 대체하기보다, 병원 현장에서 장기간 운영할 때 필요한 배포, 관측,
업데이트, 장애 기록 계층을 보조합니다.

| 운영 문제 | Vital Server Helper가 다루는 방식 |
|---|---|
| 서비스가 계속 접근 가능한지 확인 | Status와 Health Check에서 runtime 상태 확인 |
| VRecorder가 실제로 연결/전송 중인지 확인 | 최근 activity와 stale 상태를 구분 |
| `.vital` 파일이 저장되고 있는지 확인 | 파일 발견, 파일명, 크기, 읽기 가능성을 구분 |
| 장애가 빈 결과인지 실패인지 구분 | missing, invalid, failed, stale, empty 의미 유지 |
| offline 환경에서 update 적용 | update bundle 검증과 적용 흐름 분리 |

## Operating Shape

| 항목 | 기본 입장 |
|---|---|
| 기본 위치 | 병원 내부망 |
| 1차 하드웨어 | Mac mini/Mac Studio 계열 appliance |
| service stack | Linux guest 안의 Vital Server wrapper, Redis, observer, sidecar |
| 운영 UI | Helper app과 browser/PWA 기반 Runtime Control UI |
| 기본 네트워크 | 외부 outbound 없이 내부망 운영 |
| cloud 연계 | 병원 정책이 허용할 때만 별도 검토 |

## Scope

| 다루는 범위 | 다루지 않는 범위 |
|---|---|
| 설치 전 검토 항목 | Vital Server 자체 기능 변경 |
| runtime/service 상태 확인 | 의료기기 연결 자체의 임상 검증 |
| VRecorder activity 확인 | 의료 행위 또는 임상 판단 |
| `.vital` 저장 상태 sanity check | 병원 승인 없는 환자 데이터 외부 전송 |
| update와 rollback 결과 확인 | 병원별 보안 정책 대행 |

## 다음 문서

| 목적 | 문서 |
|---|---|
| 연구 배경과 현장 문제 이해 | [Research Context](background.md) |
| 병원 내/외 운영 모드 비교 | [Deployment Modes](deployment-modes.md) |
| Mac 기반 appliance 선택 이유 | [Hardware Profile](mac-hardware-appliance.md) |
| Health Check 결과 의미 이해 | [Health Check Model](health-check-service.md) |
| 설치 흐름 확인 | [Installation](installation.md) |
| 일상 운영 확인 | [Daily Operation](operation.md) |
| 공개 범위와 GitHub issue 기준 확인 | [Scope and GitHub Issues](scope-and-issues.md) |
| 장애 대응 흐름 확인 | [Troubleshooting](troubleshooting.md) |
