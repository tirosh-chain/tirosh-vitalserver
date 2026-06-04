# Background

Vital Server Helper는 저출산 극복 기술개발 중점연구와 K-MFDB 구축 맥락에서,
병원 현장의 VitalDB 기반 데이터 수집 환경을 더 안정적으로 운영하기 위해
공개/배포하는 서비스입니다.

## 배경

K-MFDB 구축에는 병원 현장에서 수집되는 생체신호 데이터가 안정적으로 저장되고,
운영자가 수집 상태를 확인할 수 있는 현장 서비스가 필요합니다.

upstream VitalServer는 연구와 실험에 필요한 기본 기능을 제공하지만, 병원 현장에서
장기간 운영하려면 설치, 상태 확인, 장애 대응, update, 데이터 sanity check 같은
제품형 운영 기능이 필요합니다.

Vital Server Helper는 upstream VitalServer를 직접 대체하지 않습니다. 대신 병원
현장에서 운영 가능한 appliance 형태로 감싸고, 필요한 검증과 관측 기능을 제공합니다.

## 공개/배포 목적

Vital Server Helper 공개/배포의 목적은 아래와 같습니다.

| 목적 | 설명 |
|---|---|
| 현장 운영성 확보 | 병원 내부망에서 장기간 켜둘 수 있는 운영 단위 제공 |
| 데이터 수집 신뢰도 확인 | VRecorder 연결과 `.vital` 저장 데이터 상태를 명시적으로 확인 |
| 장애 대응 가능성 확보 | 상태, 로그, update 결과, health check 결과를 운영자가 확인 |
| 병원 정책 대응 | outbound가 없는 병원 내 모드를 기본으로 하고, 허용 병원에만 cloud 모드 추가 |

## 비목표

이 문서군은 VitalServer 내부 구현을 설명하지 않습니다. 내부 package 구조,
Linux VM, PWA, Runtime Control API, wrapper/preload 구조는 dev 문서군에서 다룹니다.
