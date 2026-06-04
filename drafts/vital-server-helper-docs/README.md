# Vital Server Helper Draft Docs

이 디렉터리는 MkDocs에 반영하기 전 Vital Server Helper 공개/배포 문서 초안을
작성하는 임시 작업 공간입니다.

정식 문서 반영 전까지 `docs/`에는 넣지 않습니다. 문서 구조와 작성 기준은
`docs/release-dev-documentation-plan.md`를 따릅니다.

## 문서군

| 문서군 | 독자 | 역할 |
|---|---|---|
| `release/` | 연구 과제 관계자, 병원 IT 담당자, 병원 운영자, 도입 검토자 | 공개 배포 대상 서비스 설명 |
| `dev/` | repository 개발자, packaging/release 담당자, runtime/API/testkit 유지보수자 | 구현 구조, 계약, 빌드/검증 설명 |

## Release 읽는 순서

1. `release/index.md`
2. `release/background.md`
3. `release/mac-hardware-appliance.md`
4. `release/health-check-service.md`
5. `release/deployment-modes.md`
6. `release/installation.md`
7. `release/operation.md`
8. `release/troubleshooting.md`

## Dev 읽는 순서

1. `dev/index.md`
2. `dev/service-catalog.md`
3. `dev/package-map.md`
4. `dev/architecture.md`
5. `dev/health-check-contract.md`
6. `dev/api-contracts.md`
7. `dev/build-and-release.md`
8. `dev/testing.md`
9. `dev/troubleshooting.md`
