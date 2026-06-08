# Delivery & Validation

이 문서는 Vital Server Helper artifact를 만들고 검증할 때 사용하는 command, release
원칙, test 기준을 함께 정리합니다.

Release artifact는 설치 파일 하나로 끝나지 않습니다. Helper package, guest service
assets, Docker image bundle, update bundle은 네트워크 접근이 제한된 환경에서도 같은
검증 절차를 통과할 수 있어야 합니다.

## 1. Release Commands

| 목적 | command |
|---|---|
| release DMG 생성 | `make dist/dmg/release` |
| release Clean Uninstaller 생성 | `make dist/clean-uninstaller/release` |
| release Product Update bundle 생성 | `make dist/update/release` |
| release Product Update bundle 검증 | `make dist/update/verify/release` |
| VM Image update bundle 생성 | `make dist/image-update/release` |
| VM Image update bundle 검증 | `make dist/image-update/verify/release` |
| installed runtime health 확인 | `make dist/installed/health` |
| testkit release wheel 설치 | `make testkit/install-release TESTKIT_VERSION=<version>` |

## 2. Release Artifacts

| Artifact | 용도 |
|---|---|
| DMG | 신규 현장 설치 매체 |
| PKG | macOS installer payload |
| Clean Uninstaller PKG | fresh install이 막힌 Mac에서 Clean Uninstall만 수행하는 복구 package |
| Product Update bundle | Helper UI, runtime tools, proxy, service stack update |
| VM Image update bundle | rootfs/base image class update |
| Docker image bundle | air-gapped guest service stack 실행 |
| guest deploy bundle | guest 내부 service activation 입력 |

## 3. Release Checks

- Product Update와 VM Image Update를 구분합니다.
- rootfs 교체는 일반 Product Update에 넣지 않습니다.
- update 적용 전후 health check 결과를 확인합니다.
- rollback 실패와 health check 실패는 명시적으로 기록합니다.
- release note는 package별 변경 범위를 설명합니다.

build 세부 구현은 `packages/vitalserver-devtools`와
`docs/runtime/macos/packaging.md`를 기준으로 확정합니다.

## 4. Validation Scenarios

Testkit은 실제 Recorder 장비를 항상 연결할 수 없는 상황에서 수집 경로를 반복 확인하기
위한 도구입니다. 여러 Recorder가 동시에 데이터를 보내는 상황, 일정 시간 동안 계속
데이터가 들어오는 상황, release 전 기본 smoke test를 재현하는 데 사용합니다.

`.vital` file validation scenario는 계획 중이며, 현재 preview 검증 범위에는 포함하지
않습니다.

| 범위 | 목적 |
|---|---|
| unit test | domain policy, contract, parser, formatter 검증 |
| integration test | observer, testkit, API client, package plan 검증 |
| testkit smoke | simulated recorder와 Vital Server 연결 확인 |
| testkit load | 반복 `send_data` 처리와 저장 흐름 확인 |
| runtime chaos | permission, update, observability failure injection |
| Health Check scenario | VR observed/missing/stale 상태 확인 |

## 5. Test Rules

테스트의 우선순위는 happy path보다 state meaning과 failure boundary 보존입니다. 새 동작을
추가하거나 책임을 이동할 때는 정상 흐름 1개보다 missing, invalid, permission failure,
decode failure, dependency failure, stale, zero, empty를 분리해서 검증하는 테스트가 더
중요합니다.

| Layer | 반드시 검증할 것 | 실패/chaos 기준 |
|---|---|---|
| `Contracts` | 문서 decode/encode, enum case, explicit result shape | missing/invalid/failed/stale/zero/empty가 서로 바뀌지 않아야 함 |
| `Domain` | transition, guard, invariant | 불완전 입력은 전이 금지 또는 명시 failure decision으로 유지 |
| `Application/UseCases` | stateless decision, command/effect/event 계산 | dependency 실패를 empty/default success로 바꾸지 않아야 함 |
| `Workflow` | 진행 순서, progress, wait/retry loop, status persistence | failed/best-effort/degraded 결과가 status/event에 명시적으로 남아야 함 |
| `Adapters/Outbound` | filesystem/process/network/repository read-write | permission/decode/dependency failure를 typed result로 보고해야 함 |
| `Bootstrap` | dependency graph와 allowed composition만 존재 | process/filesystem/network/JSON 실행 책임이 들어오면 architecture test가 실패해야 함 |
| `Hosts` | process boundary와 host-owned effect closure | host state read/write 실패를 inward layer에 숨기지 않아야 함 |

Architecture boundary test는 regression guard입니다. 새 파일이나 새 target을 추가할 때는
해당 책임이 어느 layer에 속하는지 먼저 정하고, import direction, state ownership,
fallback 가능 여부를 함께 테스트합니다.

## 6. Change Completion Rules

구조 변경이나 runtime behavior 변경은 최소 아래 기준을 만족해야 합니다.

1. 대표 happy path를 1개 이상 검증합니다.
2. missing state를 별도로 검증합니다.
3. invalid input 또는 decode failure를 별도로 검증합니다.
4. dependency/effect failure를 별도로 검증합니다.
5. stale 또는 partial state가 의미 있는 slice라면 별도 케이스를 둡니다.
6. fallback 금지 layer에서는 fallback success가 불가능함을 검증합니다.
7. fallback 허용 layer에서는 결과가 explicit degraded/display-only임을 검증합니다.
8. boundary/import/file-absence test로 책임 위치가 되돌아가지 않게 고정합니다.

## 7. Test Organization

테스트 파일도 source와 같은 책임 신호를 가져야 합니다. test target이 integration 편의를 위해
여러 source module을 함께 import해야 하더라도, 관련 없는 테스트를 target root에 평평하게
쌓지 않고 boundary별 하위 폴더로 묶습니다.

`MacControlPanelHostTests/OutboundClient/`는 Mac control panel test target 안에서 실행되지만
macOS runtime control outbound client를 검증하는 테스트를 모읍니다.

## 8. Test Commands

```sh
make dev/check
make testkit/smoke
make testkit/load
make runtime/chaos
```

필요 시 package별 test를 직접 실행합니다.

```sh
uv run pytest packages/vitalserver-testkit/tests
uv run pytest packages/vitalserver-devtools/tests
uv run pytest packages/vitalserver-guest-tools/tests
uv run pytest apps/vitaldb-observer/tests
```

PWA와 audit proxy는 각각 Node 기반 검증을 실행합니다.

```sh
npm --prefix apps/vitalserver-runtime-pwa run check
npm --prefix apps/vitalserver-runtime-pwa test
npm --prefix apps/vitalserver-audit-proxy run check
npm --prefix apps/vitalserver-audit-proxy test
```

## 9. Repository Workflow

GitHub issue와 pull request는 재현 가능한 상태, contract, test 기준으로 다룹니다.
병원별 설치, 보안, 개인정보 협의는 공개 GitHub issue로 다루지 않습니다.

GitHub Issues: <https://github.com/tirosh-chain/tirosh-vitalserver/issues>

| 유형 | 기준 |
|---|---|
| Bug report | 재현 절차, 기대 결과, 실제 결과, 관련 상태 문서 또는 로그가 있음 |
| Documentation issue | 깨진 link, 틀린 command, 불명확한 설치/운영 설명 |
| Contract issue | API response, runtime document, Health Check 상태 의미가 깨짐 |
| Testkit issue | simulated recorder, `.vital` upload, smoke/load scenario 재현 가능 |
| Contribution proposal | 변경 목적, 영향 범위, 관련 test 계획이 있음 |

Public issue에는 환자 정보, 병원 내부 IP, 인증 정보, 비밀번호, token, 개인식별정보를
남기지 않습니다. 병원별 보안 정책 협의, 현장 설치 일정, 장비 반입, 네트워크 변경 승인,
의료 행위 또는 임상 판단도 공개 issue로 다루지 않습니다.

### 9-1. Issue Shape

```text
Summary:
Environment:
Expected:
Actual:
Explicit state:
Reproduction:
Related logs or documents:
```

`missing`, `invalid`, `failed`, `stale`, `empty`는 서로 다른 의미입니다. read failure를
empty success로 쓰거나, stale state를 healthy state로 추정하지 않습니다.

### 9-2. Pull Request Shape

- 한 가지 목적에 집중합니다.
- package 경계를 지킵니다.
- domain/core code는 외부 상태를 직접 읽지 않습니다.
- contract 변경은 관련 문서와 test를 함께 갱신합니다.
- recovery, update, parsing, settings, Health Check 변경은 실패 case test를 포함합니다.
- release 문서의 운영 주장과 dev 문서의 구현 근거가 어긋나지 않게 합니다.

## 10. Before Release

release 전에는 최소 아래를 확인합니다.

1. package build 성공
2. update bundle verify 성공
3. installed health 성공
4. testkit smoke 성공
5. 주요 failure pattern regression 없음

GitHub issue나 pull request에서 검증 실패를 보고할 때는 command, 환경, 실패 로그,
기대 결과를 함께 적습니다.
