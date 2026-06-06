# Hardware Profile

Vital Server Helper의 1차 현장 appliance는 Mac mini/Mac Studio 계열 하드웨어를
기준으로 합니다.

이 선택의 주된 이유는 macOS 자체가 아니라 하드웨어 표준화입니다. 현장별 장비 편차를
줄이면 설치, update, 교체, 장애 대응 절차를 더 좁은 범위에서 반복 검증할 수 있습니다.

## Why A Standard Appliance

Vital Server Helper는 병원 내부망에서 장기간 켜져 있는 현장 appliance를 목표로
합니다. 이 문서의 주장은 Mac이 모든 서버 요구에 더 적합하다는 뜻이 아닙니다.
초기 공개/현장 검증 범위를 좁히기 위해 1차 target을 Mac mini/Mac Studio 계열로
제한한다는 뜻입니다.

## Selection Criteria

| 이유 | 설명 |
|---|---|
| 제한된 SKU | Mac mini/Mac Studio 계열로 시작하면 CPU, firmware, storage, network, thermal profile의 조합 수를 줄일 수 있습니다. |
| 반복 가능한 검증 | 같은 하드웨어 계열에서 설치, network, update, 교체, 장애 대응 절차를 반복 검증하기 쉽습니다. |
| 소형 현장 배치 | Mac mini/Mac Studio는 별도 rack 없이 병원 내부망 가까이에 둘 수 있는 소형 장비입니다. |
| Apple Silicon runtime | Apple Silicon 기반 장비는 전력 대비 성능이 좋아 장시간 켜두는 현장 appliance 후보로 검토하기 좋습니다. |
| host 기능 통합 | macOS 위에서 Helper app, local proxy, packaging, permission, Apple Virtualization 기반 VM lifecycle을 같은 host 기준으로 다룰 수 있습니다. |
| 교체 절차 단순화 | 1차 target을 제한하면 장비 교체와 재설치 절차를 더 좁은 범위에서 문서화할 수 있습니다. |

## Boundaries

Mac 하드웨어가 모든 서버 요구에 더 적합하다는 뜻은 아닙니다.

중앙 인프라, 대규모 HA, redundant PSU, ECC memory, hot-swap storage, IPMI/iDRAC
class 원격 관리, rack mounting, server vendor SLA가 핵심 요구라면 전통적인
server 또는 industrial PC가 더 적합할 수 있습니다.

Vital Server Helper의 Mac 선택 논리는 그 요구를 부정하지 않습니다. 병원 내부망
가까이에 둘 표준 소형 현장 appliance라는 범위에서, 초기 검증 대상을 Mac 계열로
제한한다는 선택입니다.

## Role Of macOS

macOS 자체는 주된 선택 이유가 아닙니다. macOS는 Mac 하드웨어 위에서 host runtime,
local proxy, packaging, Helper app을 구동하기 위한 운영 환경입니다.

Linux VM, PWA, host별 VM provider 같은 구현 구조는 dev 문서에서 설명합니다.
