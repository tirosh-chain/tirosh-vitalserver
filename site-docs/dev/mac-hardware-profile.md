# Mac Hardware Profile

현재 repository의 macOS runtime package는 Mac 계열 host를 중심으로 개발되어
있습니다. 이 문서는 Mac mini/Mac Studio 계열을 1차 검토 대상으로 두는 이유를
설명합니다.

이 문서는 Mac 하드웨어가 release 지원 범위로 확정되었다고 주장하지 않습니다. 공개
release에서는 지원 하드웨어와 OS version을 별도로 고정해야 합니다.

## Why A Standard Target

Mac이 모든 서버 요구에 더 적합하다는 뜻은 아닙니다. 초기 검토와 개발 범위를
좁히기 위해 1차 target을 Mac mini/Mac Studio 계열로 둔다는 뜻입니다.

## Selection Criteria

| 이유 | 설명 |
|---|---|
| 제한된 SKU | Mac mini/Mac Studio 계열로 시작하면 CPU, firmware, storage, network, thermal profile의 조합 수를 줄일 수 있습니다. |
| 반복 가능한 검증 | 같은 하드웨어 계열에서 설치, network, update, 교체, 장애 대응 절차를 검토하기 쉽습니다. |
| 소형 장비 | Mac mini/Mac Studio는 별도 rack 없이 배치 가능한 소형 장비입니다. |
| Apple Silicon runtime | Apple Silicon 기반 장비는 장시간 실행 후보로 검토하기 좋습니다. |
| host 기능 통합 | macOS 위에서 Helper app, local proxy, packaging, permission, Apple Virtualization 기반 VM lifecycle을 같은 host 기준으로 다룰 수 있습니다. |
| 문서 범위 축소 | 1차 target을 제한하면 지원 범위와 검증 항목을 더 좁게 문서화할 수 있습니다. |

## Boundaries

Mac 하드웨어가 모든 서버 요구에 더 적합하다는 뜻은 아닙니다.

중앙 인프라, 대규모 HA, redundant PSU, ECC memory, hot-swap storage, IPMI/iDRAC
class 원격 관리, rack mounting, server vendor SLA가 핵심 요구라면 전통적인
server 또는 industrial PC가 더 적합할 수 있습니다.

Vital Server Helper의 Mac 선택 논리는 그 요구를 부정하지 않습니다. 현재 문서는
초기 검토 대상을 Mac 계열로 제한한다는 선택만 설명합니다.

## Role Of macOS

macOS 자체는 주된 선택 이유가 아닙니다. macOS는 Mac 하드웨어 위에서 host runtime,
local proxy, packaging, Helper app을 구동하기 위한 운영 환경입니다.

Linux VM, PWA, host별 VM provider 같은 구현 구조는 dev 문서에서 설명합니다.
