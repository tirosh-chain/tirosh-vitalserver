# Build and Release

이 문서는 Vital Server Helper build, package, update bundle 생성 흐름을 설명합니다.

## 주요 command

| 목적 | command |
|---|---|
| release DMG 생성 | `make dist/dmg/release` |
| release Product Update bundle 생성 | `make dist/update/release` |
| release Product Update bundle 검증 | `make dist/update/verify/release` |
| VM Image update bundle 생성 | `make dist/image-update/release` |
| installed runtime health 확인 | `make dist/installed/health` |
| testkit release wheel 설치 | `make install-testkit-release TESTKIT_VERSION=<version>` |

## Artifact

| Artifact | 용도 |
|---|---|
| DMG | 신규 현장 설치 매체 |
| PKG | macOS installer payload |
| Product Update bundle | Helper UI, runtime tools, proxy, service stack update |
| VM Image update bundle | rootfs/base image class update |
| Docker image bundle | air-gapped guest service stack 실행 |
| guest deploy bundle | guest 내부 service activation 입력 |

## Release 원칙

- Product Update와 VM Image Update를 구분합니다.
- rootfs 교체는 일반 Product Update에 넣지 않습니다.
- update 적용 전후 health check 결과를 확인합니다.
- rollback 실패와 health check 실패는 명시적으로 기록합니다.
- release note는 package별 변경 범위를 설명합니다.

## 문서 연결

build 세부 구현은 `packages/vitalserver-devtools`와
`docs/macos-runtime/packaging.md`를 기준으로 확정합니다.
