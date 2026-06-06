# Research Context

Vital Server Helper는 저출산 극복 기술개발 중점연구와 K-MFDB 구축 맥락에서,
병원 현장의 VitalDB 기반 데이터 수집 환경을 더 안정적으로 운영하기 위해
정리된 현장 운영 도구입니다.

## Context

K-MFDB 구축에는 병원 현장에서 수집되는 생체신호 데이터가 안정적으로 저장되고,
운영자가 수집 상태를 확인할 수 있는 현장 서비스가 필요합니다.

Vital Server는 연구와 데이터 수집에 필요한 기본 기능을 제공합니다. Helper는
그 기능 위에서 병원 현장 운영자가 확인해야 하는 설치, 상태 확인, 장애 대응, update,
데이터 sanity check 같은 보조 운영 기능을 분리해 제공합니다.

Vital Server Helper는 Vital Server를 직접 대체하지 않습니다. 대신 병원
현장에서 운영 가능한 appliance 형태로 연결하고, 필요한 검증과 관측 기능을 제공합니다.

## Why Document This Separately

이 문서는 Vital Server 내부 구현을 설명하기보다, 현장 운영자가 판단해야 하는 운영
문제를 분리합니다.

| 운영 질문                           | 문서화 이유                                             |
| ----------------------------------- | ------------------------------------------------------- |
| 수집 상태를 어떻게 확인하는가?      | VRecorder activity와 `.vital` 저장 상태를 따로 봐야 함  |
| 실패와 빈 결과를 어떻게 구분하는가? | read/decode/permission failure가 empty로 숨겨지면 안 됨 |
| 병원 내부망에서 어떻게 운영하는가?  | outbound 없는 운영을 기본 모드로 둬야 함                |
| update 이후 무엇을 확인하는가?      | runtime status와 Health Check를 다시 확인해야 함        |

## 비목표

이 문서군은 Vital Server 내부 구현을 설명하지 않습니다. 내부 package 구조,
Linux VM, PWA, Runtime Control API, wrapper/preload 구조는 dev 문서군에서 다룹니다.
