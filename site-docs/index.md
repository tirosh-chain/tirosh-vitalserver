# Vital Server Helper

Vital Server Helper는 병원 내부망에서 VitalServer를 장기간 운영하고, VRecorder
연결 상태와 저장 데이터 상태를 확인하기 위한 현장 appliance 서비스입니다.

이 GitHub Pages site는 공개 운영 문서와 오픈소스 개발 문서를 분리해서 제공합니다.
repository 내부 troubleshooting, ADR, runtime 구현 세부 문서는 root `docs/`에 따로
유지합니다.

## 문서 구분

| 문서군 | 독자 | 역할 |
|---|---|---|
| [Release](release/index.md) | 연구 과제 관계자, 병원 IT 담당자, 병원 운영자, 도입 검토자 | Vital Server Helper가 무엇을 제공하고 현장에서 어떻게 설치/운영되는지 설명 |
| [Dev](dev/index.md) | 오픈소스 contributor, package/release 담당자, runtime/API/testkit 유지보수자 | 공개 repository의 서비스 경계, package 책임, build/release/test 기준 설명 |

## 원칙

- Release 문서는 내부 구현 세부보다 현장 운영자가 필요한 설치, 운영, 장애 확인을 우선합니다.
- Dev 문서는 오픈소스 repository를 이해하고 기여하기 위한 package, contract, test 기준을 설명합니다.
- missing, invalid, failed, stale, empty 상태 의미는 공개 문서에서도 섞지 않습니다.
