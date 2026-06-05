# Dev Documentation

이 문서군은 Vital Server Helper를 개발, 패키징, 검증, 유지보수하는 사람을 위한
기술 문서입니다.

release 문서가 공개/운영 독자를 위한 설명이라면, dev 문서는 실제 repository
구조와 runtime 계약을 기준으로 작성합니다.

## 핵심 원칙

- Host와 Guest 책임을 분리합니다.
- 상태 소유자가 제공하지 않은 상태를 추측하지 않습니다.
- missing, invalid, failed, stale, empty를 구분합니다.
- upstream VitalServer의 전제는 wrapper와 guest service stack에서 명시적으로 흡수합니다.
- release 문서의 주장과 dev 문서의 구현 근거가 서로 연결되어야 합니다.

## 문서 목록

| 문서 | 역할 |
|---|---|
| [Service Catalog](service-catalog.md) | repository 안의 서비스와 package 책임 설명 |
| [Package Map](package-map.md) | monorepo package 경계와 공개 여부 설명 |
| [Architecture](architecture.md) | Host/Guest, Linux VM, PWA, Runtime Control 구조 설명 |
| [Health Check Contract](health-check-contract.md) | Health Check 상태 계약과 실패 의미 설명 |
| [API Contracts](api-contracts.md) | Runtime Control, Observer, Audit Proxy API 문서 위치 |
| [Build and Release](build-and-release.md) | build, package, update bundle 생성 흐름 |
| [Testing](testing.md) | testkit, runtime chaos, unit/integration 검증 |
| [Troubleshooting](troubleshooting.md) | 내부 장애 조사와 failure pattern 기록 기준 |
