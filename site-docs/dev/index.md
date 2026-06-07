# Dev Documentation

이 문서군은 Vital Server Helper repository의 구조와 설계 선택을 기록합니다.

Release 문서가 도입과 운영 판단에 필요한 내용을 설명한다면, Dev 문서는 그 뒤의
구조를 설명합니다. Host/Guest 경계, runtime contract, Health Check 상태 의미,
hardware 검토 기준, update와 recovery 검증 방식을 다룹니다.

## 읽는 방법

처음 읽는다면 아래 순서가 좋습니다.

1. [Service Catalog](service-catalog.md)에서 repository 안의 실행 단위와 책임을 봅니다.
2. [Architecture](architecture.md)에서 Host, Linux guest, PWA, Runtime Control API가
   어떻게 분리되는지 봅니다.
3. [Mac Hardware Profile](mac-hardware-profile.md)에서 1차 hardware target 검토 기준을 봅니다.
4. [Health Check Contract](health-check-contract.md)에서 상태 의미를 확인합니다.
5. [Testing](testing.md)에서 이 구조를 어떤 검증으로 유지하는지 봅니다.

## 설계 기준

- Host는 runtime/process/filesystem 상태를 소유합니다.
- Guest는 Host가 제공한 명시 contract를 소비합니다.
- Domain/Core는 외부 상태를 직접 읽지 않습니다.
- missing, invalid, failed, stale, empty는 서로 다른 의미로 유지합니다.
- Vital Server integration은 helper runtime contract 뒤에서 명시적으로 연결합니다.
- release 문서의 운영 주장과 dev 문서의 구현 근거가 서로 어긋나지 않아야 합니다.

## GitHub 사용

GitHub issue와 pull request는 재현 가능한 상태, contract, test 기준으로 다룹니다.
병원별 설치, 보안, 개인정보 협의는 공개 GitHub issue로 다루지 않습니다.

GitHub Issues: <https://github.com/tirosh-chain/tirosh-vitalserver/issues>

## 문서 목록

| 문서 | 역할 |
|---|---|
| [Repository Workflow](github-issues.md) | GitHub issue와 PR을 다루는 최소 기준 |
| [Service Catalog](service-catalog.md) | repository 안의 서비스와 package 책임 설명 |
| [Package Map](package-map.md) | monorepo package 경계와 문서 노출 범위 설명 |
| [Architecture](architecture.md) | Host/Guest, Linux VM, PWA, Runtime Control 구조 설명 |
| [Mac Hardware Profile](mac-hardware-profile.md) | Mac 계열을 1차 검토 대상으로 둔 이유 |
| [Health Check Contract](health-check-contract.md) | Health Check 상태 계약과 실패 의미 설명 |
| [API Contracts](api-contracts.md) | Runtime Control, Observer, Audit Proxy API 문서 위치 |
| [Build and Release](build-and-release.md) | build, package, update bundle 생성 흐름 |
| [Testing](testing.md) | testkit, runtime chaos, unit/integration 검증 |
| [Troubleshooting](troubleshooting.md) | 장애 조사와 failure pattern 기록 기준 |
