# Why Mac Hardware

Vital Server Helper의 1차 현장 appliance는 Mac mini/Mac Studio 계열 하드웨어를
기준으로 합니다.

이 선택의 주된 이유는 macOS가 아니라 Mac 하드웨어의 QA 일관성, 표준화, 장기
호환성입니다.

## 핵심 주장

Vital Server Helper는 병원 내부망에서 장기간 켜져 있는 현장 appliance를 목표로
합니다. 일반 Linux/Windows PC는 제조사와 부품 조합이 다양해 현장별 검증 범위가
커질 수 있습니다. 반면 Mac 기반 표준 장비는 설치, 검증, 교체, 장애 대응 절차를
좁힐 수 있습니다.

## 선택 이유

| 이유 | 설명 |
|---|---|
| 하드웨어 QA 일관성 | Apple은 설계, 제조, 펌웨어, 전원, 열, 부품 조합을 통합 관리합니다. 현장 장비 편차와 하드웨어 품질 리스크를 줄이는 데 유리합니다. |
| 표준화된 하드웨어 SKU | 제조사, 메인보드, BIOS/UEFI, 전원부, 네트워크 칩셋 조합이 다양한 일반 PC보다 검증 대상을 제한하기 쉽습니다. |
| 검증 범위 축소 | Mac mini/Mac Studio 계열로 배포 target을 제한하면 설치, 네트워크, update, 교체 절차를 같은 하드웨어 기준으로 반복 검증할 수 있습니다. |
| 24/7 소형 appliance | 24시간 상시 운영 가능한 일반 PC는 대개 rack/server class로 올라갑니다. Mac mini/Mac Studio는 작은 크기로 병원 내부망 가까이에 둘 수 있습니다. |
| 장기 제품 호환성 | 동일 계열 제품의 호환성과 지원 기간이 길어 현장 설치물과 runtime 검증 결과를 오래 유지하기 쉽습니다. |
| 낮은 운영 부담 | 서버랙, 별도 전산실, 복잡한 하드웨어 조달 없이 표준 장비 교체와 재설치 절차를 단순화할 수 있습니다. |
| 저전력 장기 운영 | Apple Silicon 기반 Mac mini/Mac Studio는 전력 대비 성능이 좋아 24시간 상시 운영 비용을 줄이는 데 도움이 됩니다. |

## 경계

Mac 하드웨어가 모든 서버 요구에 더 적합하다는 뜻은 아닙니다.

중앙 인프라, 대규모 HA, redundant PSU, ECC memory, hot-swap storage, IPMI/iDRAC
class 원격 관리, rack mounting, server vendor SLA가 핵심 요구라면 전통적인
server 또는 industrial PC가 더 적합할 수 있습니다.

Vital Server Helper의 Mac 선택 논리는 그 요구를 부정하지 않습니다. 병원 내부망
가까이에 둘 표준 소형 현장 appliance라는 범위에서 Mac 하드웨어가 적합하다는
주장입니다.

## OS의 역할

macOS 자체는 주된 선택 이유가 아닙니다. macOS는 Mac 하드웨어 위에서 host runtime,
local proxy, packaging, Helper app을 구동하기 위한 운영 환경입니다.

Linux VM, PWA, host별 VM provider 같은 구현 구조는 dev 문서에서 설명합니다.
