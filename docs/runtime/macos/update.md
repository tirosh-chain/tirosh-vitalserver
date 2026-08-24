# VitalServer Helper Update

VitalServer Helper의 update bundle이 무엇을 바꾸고, 무엇을 보존하며, 실패했을 때 어디를 봐야 하는지 정리합니다.

## 이 문서에서 바로 알아야 할 것

| 질문 | 답 |
|---|---|
| update 입력 단위는? | signed stable Product Update는 `dist/update-bundles/<update-id>.tar.gz`, legacy VM Image Update는 기존 schema-3 tarball |
| 현장 적용 UI는? | 0.2.2 installed macOS Host는 stable bootstrap verify/apply capability를 제공한다 |
| CLI backend는? | Runtime Control worker가 `verify-update-bootstrap`과 `apply-update-bootstrap --request-id`를 실행한다 |
| 검증 기준은? | publisher signature, target, bundle-owned next updater, specification digest, payload closure를 인증한다 |
| Product Update bundle에 rootfs가 들어가나? | 아니다. `make dist/update/release`는 rootfs를 제외한다 |
| rootfs 포함 bundle은 언제 쓰나? | VM Image/rootfs 자체를 교체해야 할 때 `make dist/image-update/release`를 사용한다 |
| mutable VM disk는 교체하나? | 기본적으로 교체하지 않는다 |
| Redis/Vital files 데이터는 보존하나? | 보존 대상이다 |
| Docker image bundle만 바꾸면 container가 자동 갱신되나? | update 단계에서 guest-side activation을 실행해야 한다 |
| `bootstrap.sh` 수정은 update bundle로 반영되나? | 된다. `guest-deploy.tar.gz`에 포함되고 기본 migration/activation 경로로 반영된다 |
| 실패 시 자동 rollback하나? | apply 중 health check 실패 시 managed backup으로 rollback을 시도한다 |
| update 중 watchdog이 복구를 시도하나? | 안 한다. stable update operation lease가 활성인 동안 watchdog auto-recovery를 suppress한다 |

설치된 launcher를 사용자 shell에서 직접 실행할 때는 installed Host 경계를
명시해야 합니다.

```sh
VITALSERVER_VM_HOME="/Library/Application Support/VitalServerHelper/vm" \
  /usr/local/bin/vitalserver-vm runtime verify-update-bootstrap \
  /path/to/update.tar.gz
```

Runtime Control Platform Agent도 같은 값을 명시적으로 worker environment에
전달합니다. 이 값이 없으면 root service는 `/var/root/.tirosh`를 개발 기본값으로
선택하므로 installed trust store나 journal을 읽은 것으로 인정할 수 없습니다.

Fresh install은 release manifest의 `releaseLabel`과 실제 rootfs staging
archive 바이트로 초기 Container Image-Set 및 Guest Runtime Release 계약을
만든다. Guest bootstrap은 control-store migration 뒤 이 계약을 검증하고,
두 immutable owner와 initial provisioning receipt를 Guest SQLite에 함께
기록한다. 이후 boot는 receipt와 현재 owner 무결성만 검증하며, update로
변경된 current/active identity를 package baseline으로 되돌리지 않는다.

## Historical: 0.2.1 Update Apply 제한

아래는 이전 0.2.1 설치본의 containment 계약입니다. 0.2.2 stable bootstrap의 현재 동작이 아닙니다. 0.2.1 bundle의 `signature` 파일은 `unsigned` placeholder이고 trusted publisher verification 구현과 trust root/config 계약이 없었습니다.

| 진입점 | 0.2.1 계약 |
|---|---|
| Helper native UI / Runtime Control PWA | `canApplyBundle=false`; integrity 확인 가능, apply 비활성 |
| `POST /platform/update-bundles/apply` | 항상 `501`과 `updateApplyUnavailable`; Host apply command를 호출하지 않음 |
| CLI 기본 `apply-bundle <path>` | publisher verification unavailable 오류로 lease/state/staging 전에 거부 |
| stable/unknown installed launcher + dev flag | dev flag가 있어도 lease/state/staging 전에 거부 |
| dev installed launcher + dev flag | 로컬 개발 apply만 허용 |
| Updater bridge/two-phase | publisher trust 우회가 아니며 계속 차단 |

로컬 개발 설치본의 유일한 허용 명령은 다음과 같습니다.

```sh
sudo /usr/local/bin/vitalserver-vm runtime apply-bundle \
  /path/to/update-bundle-dev-<kind>-<releaseLabel>.tar.gz \
  --allow-unsigned-dev-bundle
```

이 flag는 bundle channel을 보고 dev 상태를 추론하지 않습니다. 설치된 binary가 가진 `Constants.launcherChannel`이 명시적으로 `dev`여야 하며 API/native worker는 이 flag를 전달하지 않습니다. Dev apply-smoke만 이 intent를 전달하고 stable apply-smoke는 `sudo` 전에 명시적으로 실패합니다.

## Update 안정성 기준

Update 계약의 목표는 “어떤 설치본에서 어떤 update bundle을 적용하더라도, 실패 원인을 명확히 남기고 재시도/rollback 가능한 상태를 유지하는 것”입니다. Product Update는 설치된 Helper product의 구성 요소를 바꾸고, VM Image Update는 Linux guest OS/base image급 artifact를 바꿉니다. 두 흐름은 위험도와 UI 위치가 다르므로 bundle kind로 구분합니다.

### Bundle Kind

bundle kind는 의도적으로 두 개만 둡니다.

| bundleKind | UI 위치 | 포함 범위 |
|---|---|---|
| `product-update` | Update 탭 | Helper UI, Native Shell, Runtime Control API, Updater, Supervisor, VM Driver, Service Stack, 개별 service/container, host proxy, migrations |
| `vm-image-update` | Danger Zone | VM Image/rootfs/base OS/kernel/initrd class artifact |

Hotfix와 service-only update는 별도 kind를 만들지 않고 `product-update`의 signed specification layer plan으로 표현합니다. Updater bridge와 `requiresTwoPhaseUpdate`는 legacy schema-3 경로에만 남아 있으며 stable bootstrap은 매 release의 signed next updater를 사용합니다.

### Layer And Version Model

`VitalServer Helper`는 최상위 product release입니다. platform별 build는 같은 Helper release 아래의 variant이며, 세부 변경 범위는 component version으로 기록합니다. 각 layer는 platform 종속성과 책임이 다르므로 manifest와 UI에서도 이 경계를 유지합니다.

| Layer | Platform dependency | 책임 | Manifest key |
|---|---|---|---|
| VitalServer Helper | cross-platform product umbrella | 최상위 관리 제품/클라이언트 패키지, support/release note 기준 | `helperVersion` |
| Helper UI | cross-platform Web/PWA primary | iPhone/Android/iPad/desktop browser와 native shell wrapper에서 쓰는 product UI | `components.helperUI` |
| Native Shell | platform-specific | install/bootstrap/pairing/recovery/native picker/tray/menu | `components.nativeShell` |
| Runtime Control API | common API contract, platform-specific host implementation | auth/session/pairing, capability, status/log/update/settings/admin endpoint, progress/log streaming | `components.runtimeControl` |
| Updater | host/platform-specific | signed bootstrap 검증, bundle-owned next updater handoff, 적용/rollback | bootstrap envelope, Product Update Specification |
| Supervisor | host/platform-aware | health/watchdog/recovery, service state loop, auto-recovery suppression | `components.supervisor` |
| VM Driver | platform-specific | macOS Apple Virtualization, Windows provider 등 VM lifecycle provider | `components.vmDriver` |
| Service Stack | mostly guest/service-specific | guest deploy assets, compose, container image bundle, service activation 단위 | `components.serviceStack` |
| VM Image | guest OS/image-specific | Linux guest OS/base rootfs/kernel/initrd class artifact | `components.vmImage` |
| VitalServer service | service-specific | VM 안에서 실행되는 VitalServer app/container | `components.vitalServer` |

Manifest에서는 최상위 product version과 component version을 분리합니다. `helperVersion`은 support/release note 기준이고, 실제로 바뀐 하위 계층은 `components`에 기록합니다. platform별로 다르게 적용되는 bundle은 `targetPlatform`으로 제한합니다.

### 핵심 원칙

| 원칙 | 기준 |
|---|---|
| update protocol은 baseline 계약 유지 | `manifest.json`, Guest Control maintenance API, `runtime-version.json`, status JSON은 지금 정의한 필수 필드와 확장 규칙을 유지한다 |
| updater는 보수적으로 변경 | update를 수행하는 host runtime tool과 guest activation script는 일반 runtime보다 더 강한 호환성 기준을 적용한다 |
| request 필드는 신중히 확장 | 배포 이후 새 필드는 optional 또는 기본값을 가져야 하고, 필수 필드 추가는 bridge/two-phase update 대상이다 |
| 모르는 필드는 무시 | reader는 알 수 없는 JSON field 때문에 실패하면 안 된다 |
| 실패는 상태 파일과 로그에 남김 | 실패 단계, reason code, 사람이 읽을 수 있는 message를 남긴다 |
| 재실행 가능 | 같은 bundle을 다시 적용해도 중간 산출물 때문에 더 망가지면 안 된다 |
| rollback 가능 | 운영 데이터는 보존하고 교체 가능한 artifact만 managed backup으로 되돌린다 |
| update는 runtime 독점 구간 | update/rollback 중 watchdog은 runtime을 재시작하지 않는다 |

### Update Protocol 계약

아래 계약은 update 호환성의 public contract로 취급합니다.

| 계약 | 생산자 | 소비자 | 호환성 기준 |
|---|---|---|---|
| `manifest.json` | build tool | host Updater | `schemaVersion`, `channel`, `helperVersion`, `releaseLabel`, artifact 목록, compatibility field를 포함 |
| `checksums.txt` | build tool | host verifier | artifact path와 sha256/size 검증 기준 |
| `POST /runtime/maintenance/update-activation` | Host Updater | Guest Control API | `requestId`, `version`은 baseline 필수. result는 Guest operation document로 보존 |
| `POST /runtime/maintenance/update-shutdown` | host VM state control | Guest Control API | `requestId`, `version`은 baseline 필수. `poweroff-ready`는 Guest operation result로 보존 |
| `POST /runtime/maintenance/guest-poweroff` | host VM state control | Guest Control API | shutdown operation이 `poweroff-ready`인 뒤 별도 poweroff operation으로 실행 |
| Host operation lease | host Updater/Supervisor | Helper UI/watchdog | active operation owner. `operation`, owner, heartbeat, expiry를 명시 |
| `runtime-progress.json` | host Updater/Supervisor | diagnostics/export | workflow step/progress display artifact. operation/step/status는 enum 계약으로 유지하지만 Runtime Control current read model, active operation, health owner가 아님 |
| `runtime-status.json` | host Updater/Supervisor | diagnostics/export | diagnostics/status projection. current runtimeState, active operation, progress owner가 아님 |
| `runtime-version.json` | installer/Updater | Helper UI/Updater | 현재 installed component version 표시와 rollback 판단 기준 |

현재 baseline에서 Host updater는 Guest Control API에 아래 형식의 body를 보냅니다.

```json
{
  "requestId": "2DD1A7A8-1C51-4D6B-8DF1-89C62B7F63B3",
  "version": "1.2.3"
}
```

| 상황 | 처리 |
|---|---|
| host request에 `requestId` 있음 | result의 `requestId`가 일치해야 completed로 인정 |
| host request에 `requestId` 없음 | baseline 계약 위반으로 실패 |
| result에 `requestId` 없음 | baseline 계약 위반으로 stale/failed 처리 |
| result status가 `failed` | 즉시 실패 처리하고 message를 Helper UI와 command log에 노출 |

### Stable Bootstrap Compatibility

현재 stable update에는 minimum updater version이나 updater bridge gate가 없습니다.
설치된 Host는 고정된 signed envelope에서 publisher, target, next updater
artifact, specification artifact, 그리고 envelope가 직접 소유하는 exact
`payloadArtifacts` closure를 검증합니다. 검증된 next updater만 변경되는
Product Update Specification을 decode합니다. 따라서 `release.json`,
`release-dev.json`, Runtime Control release read model은 minimum updater
version을 소유하거나 노출하지 않습니다.

Bootstrap envelope은 schema `v2`이며 `payloadArtifacts` exact closure를
직접 소유합니다. 설치 Host는 이 고정 계약만으로 모든 파일의 digest/size와
no-extra file closure를 검증하고, specification은 opaque bytes로만 취급해
next updater에 handoff합니다. 설치 Host는 인증된 specification을 decode하지
않으므로, 미래 specification schema에 새 필드가 추가되어도 기존 Host의
bootstrap admission이 막히지 않습니다. v1 envelope는 unsupported schema로
거부되며, v1 Host는 v2 envelope를 수락하지 않습니다. 두 schema를 모두
수락하는 fallback은 없습니다.

검증 순서는 소유 계약 순서를 지킵니다. 먼저 archive path, entry kind,
duplicate와 envelope/next updater/specification/payloadArtifacts 존재 여부만
구조적으로 검사합니다. 이어 publisher signature를 검증하고, envelope이 선언한
next updater/specification/payloadArtifacts 각각의 digest와 size를 확인한 뒤
exact file closure(추가 파일 없음)를 검증합니다. 이 과정에서 specification을
decode하지 않습니다. staging 후에도 같은 envelope-owned closure를 다시
검증합니다.

검증된 next updater만 specification을 decode하고, specification이 선언한
apply/executor/configuration/rollback artifact가 signed `payloadArtifacts`
closure와 정확히 일치하는지 교차 검증합니다. 선언 누락, 추가 artifact, digest
또는 size 불일치는 next updater가 admission을 거부합니다.

필드나 specification이 바뀌어도 기존 Host가 새 specification을 추측하거나
fallback으로 해석하지 않습니다. 기존 Host는 고정 bootstrap 계약만 검증하고,
bundle이 제공한 next updater에 인증된 입력을 그대로 handoff합니다.

`issuedAt`은 단순 `YYYY-MM-DDTHH:MM:SSZ` 문자열 패턴이 아니라 실제로 존재하는
UTC 순간이어야 합니다. publisher(builder/verifier)와 설치 Host의 Swift verifier
가 동일한 canonical UTC 순간을 검증하므로, 존재하지 않는 날짜(예: 2월 30일,
13월, 24시)는 publisher와 verifier 양쪽에서 거부됩니다.
식별자(`id`, `productId`, `signature.keyId`, artifact id, effect executor id)는
ASCII `[A-Za-z0-9._-]{1,128}` 계약을 공유합니다. publisher, bootstrap envelope,
effect configuration, Product Update Specification planner가 동일한 계약을
적용하므로 leading `._-`은 허용되고 `:`와 비-ASCII 문자는 거부됩니다.

### Legacy schema-3 Manifest Compatibility

아래 계약은 전환 기간 동안 남아 있는 legacy publisher/engine에만 적용됩니다.
현재 stable Product Update나 release source of truth 계약이 아닙니다.
`make dist/update/*`는 이 legacy publisher를 사용하지 않습니다. 이 계약은
`make dist/image-update/*`의 VM Image Update에만 남아 있습니다.

```json
{
  "schemaVersion": 3,
  "product": "ai.tirosh.vitalserver.helper",
  "bundleKind": "product-update",
  "channel": "stable",
  "helperVersion": "0.2.0",
  "releaseLabel": "0.2.0",
  "targetPlatform": "macos-arm64",
  "minUpdaterVersion": "0.0.0",
  "components": {
    "helperUI": "0.2.0+macos.1",
    "nativeShell": "0.2.0+macos.1",
    "runtimeControl": "0.2.0+macos.1",
    "updater": "0.2.0",
    "supervisor": "0.2.0",
    "vmDriver": "0.2.0+macos.1",
    "serviceStack": "2.3.4-stack.1",
    "vitalServer": "2.3.4"
  },
  "requiresGuestActivation": true,
  "requiresTwoPhaseUpdate": false
}
```

필드 의미:

| 필드 | 의미 |
|---|---|
| `schemaVersion` | manifest 문법과 required field set의 version. 현재 baseline은 `3` |
| `product` | bundle이 대상으로 하는 product id. 현재 `ai.tirosh.vitalserver.helper` |
| `bundleKind` | `product-update` 또는 `vm-image-update` |
| `channel` | `stable`, `dev` 같은 update channel. 설치된 updater channel과 다르면 preflight에서 거부 |
| `helperVersion` | 최상위 VitalServer Helper product release version. package-safe numeric version |
| `releaseLabel` | artifact/staging/backup/installed version 표시에 쓰는 release identity. 예: `0.2.0`, `0.2.0-dev` |
| `targetPlatform` | 이 bundle을 적용할 수 있는 단일 platform/build variant. 예: `macos-arm64` |
| `minUpdaterVersion` | 이 bundle을 직접 적용할 수 있는 최소 Updater version |
| `components` | bundle이 제공하거나 변경하는 component version map |
| `requiresGuestActivation` | `guest-deploy` 교체 후 VM 내부 activation이 필요한지 |
| `requiresTwoPhaseUpdate` | updater 자체를 먼저 갱신해야 하는 bridge update가 필요한지 |

Legacy reader는 required contract field 누락을 실패로 처리합니다. 이 serializer가 요구하는 `minUpdaterVersion`은 explicit no-gate 값으로만 기록하며 stable/dev release source of truth에는 저장하지 않습니다. Stable/dev artifact identity와 optional container 포함 정책은 `apps/vitalserver-macos-runtime/release.json` 및 `release-dev.json`을 SoT로 삼습니다.

`requiresTwoPhaseUpdate`의 owner 경계는 아래처럼 고정합니다.

| 경계 | 책임 |
|---|---|
| Make/release command | updater bridge 필요 여부를 명시적으로 입력하며 기본값은 `false` |
| release use case | 입력값을 bundle kind나 artifact로 추론하지 않고 manifest builder에 전달 |
| manifest builder | 전달받은 boolean을 `requiresTwoPhaseUpdate`에 그대로 기록 |
| installed Swift Updater | normal apply에서 `true`를 거부하고 bridge 절차가 필요함을 보고 |

따라서 `vm-image-update`이거나 `rootfs-base.raw.gz`를 포함한다는 사실만으로 이 값이 `true`가 되지 않습니다. 일반 VM Image Update는 normal apply preflight를 통과할 수 있어야 하며, 기존 Updater가 새 계약을 이해하지 못하는 실제 bridge Product Update만 build 호출에서 `true`를 명시합니다.

### Two-Phase Update 기준

update system 자체가 바뀌는 경우에는 runtime payload와 updater payload를 한 번에 섞어 처리하지 않습니다.

| 개념 | 의미 |
|---|---|
| Product Update | Helper UI/Native Shell/Runtime Control API/Updater/Supervisor/VM Driver/Service Stack/service 변경 |
| VM Image Update | Linux guest OS/rootfs/base image 변경 |
| Two-phase Update | 기존 Updater가 새 Product Update를 바로 이해하지 못할 때, Updater를 먼저 올리고 본 update를 나중에 적용 |

여기서 two-phase update는 VM Image Update와 Product Update를 같이 묶는다는 뜻이 아닙니다. Two-phase는 Product Update 내부에서 기존 설치본의 Updater가 새 update 계약을 이해하지 못할 때, Updater compatibility layer를 먼저 올리고 그 다음 실제 Product Update payload를 적용하는 절차입니다. VM Image/rootfs/base OS 변경은 별도의 `vm-image-update` 흐름이며 Danger Zone 대상입니다.

```text
Phase 1: updater compatibility layer 갱신
  - updater/runtime-tools
  - guest activation script
  - status/result parser
  - update UI 표시 개선

Phase 2: runtime payload 갱신
  - Supervisor/VM Driver tools
  - guest-deploy
  - Service Stack / Docker image bundle
  - nginx bundle
  - migrations
```

적용 기준:

| 변경 내용 | 단일 bundle 가능 여부 | 비고 |
|---|---|---|
| Helper UI만 변경 | 가능 | app bundle 교체 후 app 재실행 필요 |
| Updater/runtime-tools CLI만 변경 | 가능하지만 주의 | 현재 실행 중인 updater는 중간에 바뀌지 않음 |
| Supervisor/VM Driver만 변경 | 가능 | platform별 component version으로 변경 범위를 표시 |
| Service Stack 변경 | 가능 | guest activation 필수 |
| guest activation request/result 계약 변경 | bridge bundle 권장 | 구버전 host/guest 조합을 고려 |
| Docker image bundle 변경 | 가능 | guest activation 필수 |
| rootfs-base 변경 | 별도 `vm-image-update` bundle | 기존 `vm-disk.img`에는 자동 전개되지 않음 |
| mutable VM disk 교체 | Product Update 금지 | Danger Zone의 별도 VM Image replacement 대상 |

### Bridge Bundle 기준

아래 상황에서는 일반 Product Update bundle 대신 bridge/two-phase Product Update bundle을 먼저 제공합니다.

| 상황 | bridge bundle에 포함할 것 |
|---|---|
| host Updater가 새 manifest를 읽지 못함 | `runtime-tools.tar.gz`, Helper app |
| guest activation script 계약이 바뀜 | `guest-deploy.tar.gz`, cloud-init seed refresh migration |
| result/status parser 계약이 바뀜 | `runtime-tools.tar.gz`, Helper app |
| update progress 표시 방식이 바뀜 | Helper app, runtime-tools |

Bridge bundle은 가능한 작게 유지합니다.

```text
bridge bundle:
  - app-bundle.tar.gz
  - runtime-tools.tar.gz
  - guest-deploy.tar.gz
  - migrations/

일반적으로 제외:
  - rootfs-base.raw.gz
  - 대용량 Docker image bundle
```

Build에서도 bridge 여부를 별도로 선언합니다.

```sh
# 일반 VM Image Update: requiresTwoPhaseUpdate=false
make dist/image-update/dev

# legacy VM Image publisher에서 bridge가 실제로 필요한 경우에만 명시
make dist/image-update/dev VM_IMAGE_UPDATE_REQUIRES_TWO_PHASE_UPDATE=true
```

### Idempotency 기준

update 단계는 중간 실패 후 재실행이 가능해야 합니다. 이를 위해 단계별 marker 또는 result를 남깁니다.

| 단계 | marker/log 기준 |
|---|---|
| integrity check completed; publisher authenticity unverified | command log |
| bundle staged | staged bundle path |
| backup created | `backups/<timestamp>-before-<version>` |
| artifacts replaced | runtime progress step |
| guest activation requested | Guest Control `POST /runtime/maintenance/update-activation` accepted operation |
| guest activation completed | Guest Control operation state `completed` |
| health passed | explicit runtime health owner reads report healthy; `runtime-status.json` may only mirror this as diagnostics projection |
| update committed | `runtime-version.json` version 갱신 |

재실행 시에는 아래를 지켜야 합니다.

- 이미 staged된 같은 bundle은 검증 후 재사용할 수 있다.
- 이미 존재하는 backup은 덮어쓰지 않고 새 backup을 만들거나 명시적으로 재사용한다.
- stale Guest operation result는 operation id와 request id로 구분한다.
- old request/result files are historical install evidence only; current update flow must not use them.
- rollback 중에도 운영 데이터 경로는 삭제하지 않는다.

### Guest Activation Baseline

Guest activation은 Guest Control maintenance operation으로 실행합니다. Host는
`POST /runtime/maintenance/update-activation`을 호출하고, Guest operation document를
polling해서 activation 상태를 확인합니다.

필수 동작:

| 케이스 | 동작 |
|---|---|
| `python3` 없음 | 실패하되 명확한 message와 operation failure 기록. 단, 제품 rootfs에는 `python3`를 필수 포함 |
| `requestId` 없음 | baseline 계약 위반으로 failed operation 기록 |
| `version` 없음 | baseline 계약 위반으로 failed operation 기록 |
| request JSON 파싱 실패 | failed operation과 log 기록 |
| Docker image bundle 없음 | image load는 skip 가능하되 compose recreate는 정책에 따라 진행 |
| compose 실패 | failed operation과 container log 확인 안내 |

구현 기준:

```text
activation operation input:
  - requestId required
  - version required
  - schemaVersion required
  - operation required

activation operation result:
  - schemaVersion always written
  - requestId always written from request
  - status always written
  - message always written
  - updatedAt always written
```

### Guest Update Shutdown Baseline

Product Update가 guest deploy, container image, runtime tool, proxy artifact를 바꿀 때는 VM을 그냥 내리지 않습니다. Host는 먼저 Guest Control `POST /runtime/maintenance/update-shutdown`을 호출하고, Guest operation이 `poweroff-ready`를 남길 때까지 기다린 뒤 VM stop/restart 경로로 진행합니다.

이 shutdown operation은 update-specific operation입니다. Settings restart, watchdog
recovery, service repair가 같은 operation input을 재사용하거나 stale file artifact를
다시 실행하면 안 됩니다.

필수 동작:

| 단계 | 기준 |
|---|---|
| capability preflight | Host는 Guest가 update shutdown capability를 보고한 경우에만 Guest Control operation을 시작한다 |
| operation accepted | Guest Control API는 operation id를 반환하고 `accepted` 또는 `running` 상태를 기록한다 |
| Redis backup | update 전 Redis data backup을 만들고 실패하면 typed failure로 중단한다 |
| compose stop | service별 명시 순서와 timeout으로 container를 중지한다 |
| final sync | filesystem sync가 끝난 뒤에만 poweroff request를 진행한다 |
| poweroff handoff | final sync 직후 Guest Control operation을 `poweroff-ready`로 완료하고, Host가 별도 `guest-poweroff` operation을 요청한다 |
| host wait | Host는 Guest operation state와 VM lifecycle/poweroff wait를 분리해서 관측한다 |

Compose stop은 whole-stack fallback이 아니라 아래 순서의 명시 operation입니다.

```text
edge -> swagger-ui -> redis-ui -> lab -> vitaldb-observer -> redis-relay -> recorder-ingress -> recorder-recovery -> app -> postgres -> redis
```

기본 stop timeout은 30초입니다. `app`은 90초, `redis`는 60초로 둡니다. timeout이나 dependency failure가 발생하면 Guest Control operation failure/result에 아래 정보를 남깁니다.

| field | 의미 |
|---|---|
| `details.failedService` | stop 실패가 발생한 service |
| `details.remainingServices` | 실패 시점에 아직 stop 대상인 service 목록 |
| `details.serviceStates` | failure snapshot의 compose service state |
| `details.failureSnapshotPath` | diagnostics/snapshot artifact 경로 |

Host는 이 Guest operation을 update failure로 소비해야 합니다. 로그 tail, missing marker, VM process 종료 여부로 Guest shutdown success를 추정하지 않습니다.

Rollback 중 health wait에서 `host-proxy-http-*`, `recorder-ingress-http-failed`, `container-service-*-state-exited` 같은 transient reason이 먼저 보일 수 있습니다. 최종적으로 `hostProxyHTTP=200`과 runtime health가 확인되면 rollback health wait는 성공입니다. 다만 rollback 성공은 update 성공이 아니며, command log와 runtime event에는 update failure와 rollback success가 둘 다 남아야 합니다.

### Release Gate

update bundle을 배포 후보로 보려면 아래를 통과해야 합니다.

| 항목 | 기준 |
|---|---|
| fresh install | clean machine 또는 clean runtime home에서 설치 성공 |
| same-version apply | 같은 version bundle을 적용해도 깨지지 않음 |
| previous-version apply | 직전 버전 설치본에서 최신 bundle 적용 성공 |
| invalid operation apply | `requestId` 없는 activation operation은 명확한 failure를 남김 |
| update shutdown | update shutdown capability, operation accepted/running/completed state, ordered compose stop, poweroff handoff 검증 |
| guest activation | Docker image load와 compose recreate가 수행됨 |
| health wait | VitalServer, Redis, network access가 ready |
| rollback | 의도적 실패 bundle에서 update failure와 rollback success가 모두 기록되고 managed backup rollback 성공 |
| logs | Update 탭/Logs 탭에서 현재 단계와 실패 이유를 확인 가능 |

Release gate를 통과하지 못한 bundle은 현장 전달 대상이 아닙니다. 특히 update system 자체가 바뀌는 release는 이전 설치본에서 직접 적용하는 테스트를 반드시 포함합니다.

## Update Bundle 구조

현재 stable Product Update는 publisher가 명시적으로 받은 세 layer의 current와
rollback artifact를 하나의 signed closure로 묶습니다.

```text
dist/update-bundles/<update-id>.tar.gz
```

인증된 specification의 적용 순서는 고정입니다.

```text
Container -> Guest Runtime -> Helper Host Platform
```

각 layer는 immutable current artifact, immutable rollback artifact, effect
executor와 effect configuration을 가집니다. Helper Host Platform archive는
Helper app과 교체 가능한 Host service를 포함하지만 다음 stable owner는
포함하거나 교체할 수 없습니다.

Guest Control endpoint는 signed effect configuration의 일부가 아닙니다.
Platform Agent가 Host-owned Guest address provider에서 현재 주소를 읽고,
`update-bootstrap-handoff/v2`와
`product-update-layer-effect-invocation/v2`를 통해 next updater와
Guest-owned layer executor에 명시적으로 전달합니다. 주소가 missing,
invalid, stale, 또는 read-failed이면 apply를 진행하지 않으며 loopback이나
이전 관측값으로 보정하지 않습니다.

- `/usr/local/bin/vitalserver-host-installation-manager`
- `/usr/local/bin/vitalserver-update-handoff-supervisor`

Host Platform 적용이 실패하면 Host-owned effect를 먼저 되돌리고, Guest
Control API가 여전히 새 owner code를 실행하는 동안 Container를 rollback한
뒤 Guest Runtime을 rollback합니다. 따라서 product layer rollback 순서는
`Host Platform -> Container -> Guest Runtime`입니다. execution report는
전체 ordered apply/rollback receipt를 보존하며, 누락되거나 순서가 다른
receipt는 성공 증거가 아닙니다.

Guest content-addressed artifact store는 같은 digest가 이미 존재해도 incoming
request body를 declared Content-Length까지 소비하고 SHA-256을 검증합니다.
기존 artifact 존재를 이유로 body를 읽지 않고 성공 응답을 반환하면 Host upload
task에는 connection-lost로 관측되므로 idempotent import가 아닙니다.

`rootfs-base.raw.gz`는 stable Product Update에 포함하지 않습니다. VM
Image/rootfs를 바꾸는 경우에만 `make dist/image-update/release`의 별도 legacy
bundle을 사용합니다.

### Installed field proof

`apply-update-bootstrap`의 성공 종료는 durable handoff admission과 launch
성공을 뜻하며 전체 layer 적용 완료를 뜻하지 않습니다. 따라서 field smoke는
고정 sleep이나 apply exit code로 최종 결과를 추측하지 않습니다.

```sh
make dist/update/dev/apply-smoke \
  VM_UPDATE_APPLY_SMOKE_CONFIRM=YES \
  VM_UPDATE_APPLY_REQUEST_ID=<unique-request-id>

make dist/update/dev/rollback-smoke \
  VM_UPDATE_APPLY_SMOKE_CONFIRM=YES \
  VM_UPDATE_ROLLBACK_PROOF_BUNDLE=/path/to/separately-signed-fault-bundle.tar.gz \
  VM_UPDATE_ROLLBACK_PROOF_ID=<fault-update-id> \
  VM_UPDATE_ROLLBACK_PROOF_REQUEST_ID=<unique-request-id>
```

proof command는 명시된 timeout과 poll interval 동안 Host owner SQLite journal의
terminal state를 기다립니다. 이후 digest로 고정된 execution report와 signed
specification을 검증하고, Runtime Control `/platform/operations`가 제공한
stable update journal이 Host owner journal과 동일한지 확인합니다. missing,
read/decode failure, timeout과 terminal failure는 서로 다른 오류입니다.

rollback smoke의 fault bundle은 일반 bundle에서 만들어내거나 암묵적으로
변형하지 않습니다. Host Platform effect가 의도적으로 실패하도록 별도로
구성하고 동일 publisher로 서명한 bundle이어야 하며, proof는
Container/Guest Runtime 적용 성공, Host Platform 적용 실패,
Container/Guest Runtime owner-safe rollback 성공 receipt를 모두 요구합니다.

```text
rootfs-base.raw.gz = immutable base artifact
vm-disk.img        = installed mutable VM instance
```

rootfs update에서 `rootfs-base.raw.gz`를 교체해도 이미 생성된 `vm-disk.img` 내부 OS/package는 자동으로 바뀌지 않습니다. 이미 설치된 VM 내부를 바꾸려면 migration이나 guest-side activation 단계가 필요합니다.

따라서 기존 `vm-disk.img` 자체가 Docker, Docker Compose, Avahi, growpart 같은 runtime package를 가지고 있지 않다면 Product Update bundle만으로는 복구할 수 없습니다. 이 경우에는 새 package로 재설치하거나, 별도의 VM Image replacement 흐름을 사용해야 합니다. 이 흐름은 운영 데이터 보존 정책이 더 민감하므로 Update 탭이 아니라 Danger Zone 대상입니다.

## Rootfs 변경 기준

rootfs는 Linux VM의 OS base입니다. 변경 기준은 “Mac host나 guest deploy 파일이 바뀌었는가”가 아니라, “VM 내부 OS package 또는 boot/runtime base가 바뀌었는가”입니다.

### Rootfs 변경이 필요한 경우

아래 변경은 새 `rootfs-base.raw.gz`를 만들어야 합니다.

| 변경 | 이유 |
|---|---|
| Ubuntu cloud image 변경 | VM OS base 자체가 바뀜 |
| boot asset 변경 | `Image`, `initrd.img`와 rootfs 조합을 다시 검증해야 함 |
| apt package 목록 변경 | 기존 mutable `vm-disk.img`에는 새 package가 자동 설치되지 않음 |
| Docker/Compose OS package 변경 | Docker daemon/compose plugin은 VM OS package에 속함 |
| Avahi/mDNS OS package 변경 | guest network discovery service는 VM OS package에 속함 |
| `cloud-guest-utils`, `growpart` 등 filesystem package 변경 | disk grow/bootstrap preflight에 직접 영향 |
| systemd 기본 service enable 정책 변경 | 새 base image의 기본 부팅 상태에 반영해야 함 |
| 보안 패치가 필요한 OS package 반영 | base image를 새로 준비해야 함 |
| air-gapped rootfs 준비 방식 변경 | 설치 시점에 이미 준비된 OS 상태가 달라짐 |

예를 들어 `prepare-airgap-rootfs.sh`에서 `docker.io`, `python3-minimal`, `avahi-daemon` 같은 package를 추가/제거했다면 rootfs 변경 대상입니다.

### Rootfs 변경이 필요 없는 경우

아래 변경은 일반적으로 rootfs를 새로 만들 필요가 없습니다.

| 변경 | 반영 artifact |
|---|---|
| Helper app UI 변경 | `app-bundle.tar.gz` |
| Updater/Supervisor/VM Driver Swift CLI 변경 | `runtime-tools.tar.gz` |
| host nginx binary/config 변경 | `nginx-bundle.tar.gz` |
| `compose.yaml` 변경 | `guest-deploy.tar.gz` |
| guest `bootstrap.sh`, Guest tools wheel, `nginx/*.conf` 변경 | `guest-deploy.tar.gz` |
| VitalServer container image 변경 | `guest-deploy.tar.gz` 안의 Docker image bundle |
| OpenAPI/Swagger static file 변경 | `guest-deploy.tar.gz` |
| update/rollback host 로직 변경 | `runtime-tools.tar.gz` |

이 경우 update bundle 적용 후 guest-side activation이 Docker image load, compose recreate, guest file activation을 수행해야 합니다.

### 판단 규칙

```text
Mac app / host runtime / guest deploy 변경
  -> rootfs 불필요

container image / compose / guest script 변경
  -> rootfs 불필요, guest activation 필요

Ubuntu / apt / Docker daemon / OS service 변경
  -> rootfs 필요
```

VM Image Update bundle은 `rootfs-base.raw.gz`를 교체하지만, 이미 설치된 mutable `vm-disk.img`를 자동 교체하지 않습니다. 따라서 기존 설치본의 OS package 상태까지 바꿔야 하는 경우에는 Product Update가 아니라 fresh install, VM Image replacement, 또는 offline OS package migration 정책을 함께 설계해야 합니다.

## 보존되는 것과 바뀌는 것

기본 Product Update는 운영 데이터 보존을 우선합니다.

| 구분 | 경로/대상 | update 기본 정책 |
|---|---|---|
| VM mutable disk | `vm/runtime/vm-disk.img` | 보존 |
| VM config | `vm/runtime/vm-config.json` | 보존. Settings/CLI configure로 변경 |
| cloud-init seed | `vm/runtime/seed.iso` | `guest-deploy` 변경 시 갱신. VM 부팅 때 bootstrap 재실행을 유도 |
| Vital files | configured vital files directory | 보존 |
| VR release files | `vm/data/vr-release` | 보존 |
| Redis data | guest Docker volume `redis-data` | 보존 |
| runtime status | `status/runtime-status.json` | diagnostics/status projection으로 갱신. current operation/health owner가 아님 |
| install/update logs | `logs/`, `/private/tmp/tirosh-vitalserver-manager-command.log` | 보존 또는 rotation |
| managed backups | `backups/<timestamp>-before-<version>` | 생성/보존 |
| Helper app | `/Applications/VitalServer Helper.app` | 교체 |
| runtime CLI | `/usr/local/bin/*` | 교체 |
| host nginx bundle | host-platform/current release nginx | 교체 |
| guest deploy bundle | `vm/data/deploy/` | 교체 |

`guest-deploy.tar.gz` 안에 Docker image bundle이 포함되어도, 그것은 “host shared directory에 새 image tar가 놓였다”는 뜻입니다. VM 안의 Docker daemon에 image가 실제로 load되고, 기존 container가 새 image로 recreate되는 것은 별도의 guest-side activation입니다.

따라서 `apps/vitalserver-macos-runtime/Support/Guest/bootstrap.sh` 같은 guest deploy 파일을 수정했다면, 새 update bundle을 만들면 그 수정은 `guest-deploy.tar.gz`에 들어갑니다. 0.2.2 stable Product Update에서는 Guest Runtime layer owner가 signed specification과 authenticated artifact를 적용합니다. 아래 legacy apply 설명은 0.2.1과 schema-3 진단을 위해서만 남깁니다.

## Historical: Legacy schema-3 Apply 과정

아래 lifecycle은 stable bootstrap 이전의 schema-3 apply 흐름입니다. 0.2.1에서는 installed dev launcher가 명시적 개발 intent를 받은 경우에만 실행됐고, Helper Update 탭과 Runtime Control API는 이 lifecycle을 시작하지 않았습니다. 0.2.2의 현재 Product Update 흐름은 앞의 `Installed field proof`와 signed three-layer specification을 기준으로 합니다.

```text
1. check bundle integrity; publisher authenticity remains unverified
2. stage bundle
3. free-space preflight
4. create managed backup
5. stop runtime services
6. replace host-side artifacts
7. run migrations
8. refresh cloud-init seed when guest deploy changed
9. write runtime-version.json
10. restart services
11. activate guest update when guest deploy changed
12. wait runtime health
13. success or rollback
```

각 단계의 의미는 아래입니다.

| 단계 | 설명 |
|---|---|
| integrity check | `manifest.json`, `checksums.txt`, artifact sha256/size 검증. publisher authenticity는 검증하지 않음 |
| stage | bundle을 product root의 `bundles/` 아래로 복사 |
| preflight | stage/apply/backup에 필요한 여유 공간 확인 |
| backup | rollback 가능한 artifact를 `backups/` 아래에 저장 |
| stop services | VM/proxy/watchdog launchd service 중지 |
| replace | app/runtime-tools/nginx/guest-deploy 교체. rootfs-base는 bundle에 포함된 경우에만 교체 |
| migrations | executable migration을 순서대로 실행 |
| cloud-init refresh | `guest-deploy`가 바뀐 경우 새 instance-id로 seed를 갱신해 bootstrap 재실행을 유도 |
| restart | 이전에 runtime이 running 상태였으면 VM/proxy/watchdog 재시작 |
| guest activation | VM 내부에서 Docker image load, compose recreate, Guest Control/Postgres read model 갱신 |
| health wait | guest HTTP, host proxy, Redis UI, Swagger UI 등 runtime health 대기 |
| rollback | health wait 실패 또는 migration 실패 시 backup 복원 시도 |

개발 apply가 실행되는 동안 Helper의 기존 진단 projection은 Command log를 1초 단위로 갱신할 수 있습니다. 상세 로그는 Logs 탭의 `Command log`, `Update activation`, `Containers` source에서 확인합니다. 이 진단 표시는 UI apply capability를 허용하지 않습니다.

## Watchdog Coordination

Update와 watchdog은 같은 runtime 자원을 만집니다.

```text
update:
  stop/start VM service
  stop/start proxy service
  replace Updater/Supervisor/VM Driver tools
  replace guest deploy
  request guest activation
  wait for runtime readiness

watchdog:
  read runtime health
  restart VM service
  restart proxy service
  publish diagnostics/status projection
```

따라서 update가 진행 중인 동안 watchdog이 auto-recovery를 실행하면 경쟁 상태가 생깁니다. 대표적인 실패 흐름은 아래입니다.

```text
apply-bundle starts
  -> VM/proxy/watchdog stopped
  -> artifacts replaced
  -> VM/proxy/watchdog restarted
  -> guest activation still running
watchdog wakes up
  -> guest readiness is not ready yet
  -> VM/proxy restart
  -> apply-bundle waits for health against a moving target
```

정책은 명확합니다.

| owner contract | 상태 | watchdog 동작 |
|---|---|---|
| Host operation lease | active lease | auto-recovery suppress |
| Host operation lease | missing/stale/failed read | 일반 health/recovery 정책 적용 또는 typed blocker 유지 |
| `runtime-status.json` | any status projection | active operation lock으로 사용하지 않음 |
| `runtime-progress.json` | any workflow progress | active operation lock이나 health/recovery state로 사용하지 않음 |

suppression은 영구 정지가 아닙니다. Lease가 없거나 stale이면 watchdog은 status/progress 문서에서 operation을 추론하지 않고 일반 recovery 정책으로 돌아갑니다.

`runtime-status.json`은 diagnostics/status projection artifact입니다. Workflow progress detail은 Runtime Control operation-state/API owner contract에서 읽고, `runtime-progress.json`은 diagnostics/export artifact로 남깁니다. Watchdog은 status/progress 문서에서 active operation ownership이나 health/recovery state를 재구성하지 않습니다.

중요한 세부 기준:

- update/rollback process가 명시적으로 VM/proxy/watchdog lifecycle을 소유한다.
- watchdog은 update/rollback 중 VM/proxy를 재시작하지 않는다.
- update가 실패하면 apply flow가 rollback을 먼저 시도한다.
- rollback까지 실패하거나 상태가 stale이면 watchdog이 다시 복구 책임을 가진다.
- guest readiness는 `/ready` endpoint 기준으로 기록한다. `/`는 VitalServer app redirect 때문에 readiness source로 쓰지 않는다.

## Guest-Side Activation

Guest-side activation은 update 계약에서 가장 조심해야 하는 부분입니다.

`guest-deploy.tar.gz`는 host shared directory의 deploy bundle을 교체합니다. 하지만 VM 내부에서 아래 작업이 자동으로 보장되는 것은 아닙니다.

```text
docker load -i /mnt/tirosh/deploy/docker-images/vitalserver-images.tar.gz
docker compose down
docker compose up -d
old wrong-arch image cleanup
guest systemd unit 재설치
guest-side health 재검증
```

첫 설치에서는 cloud-init이 `bootstrap.sh`를 실행하고, 이 과정에서 Docker image bundle을 load합니다. 반면 update에서는 `guest-deploy`를 host shared directory에 교체하는 것만으로는 VM 내부 Docker daemon이 자동 갱신되지 않습니다.

이를 보완하기 위해 update flow는 `guest-deploy` 변경 시 두 단계를 수행합니다.

| 단계 | 목적 |
|---|---|
| cloud-init seed refresh | 새 instance-id를 가진 `seed.iso`를 만들어 VM 부팅 시 `bootstrap.sh`가 다시 실행될 수 있게 함 |
| guest activation request | Guest Control `POST /runtime/maintenance/update-activation`으로 VM 안의 activation adapter가 image load/compose recreate를 수행하게 함 |

호환성을 위해 update bundle에도 `001-refresh-cloud-init-seed` migration을 기본 포함합니다. 이유는 중요합니다. 이미 설치된 구버전 Helper가 bundle을 적용하면, 새 Swift apply 로직은 아직 실행될 수 없습니다. 하지만 구버전 apply도 migration은 실행하므로, 이 migration이 `seed.iso`를 갱신해 VM 부팅 시 새 `guest-deploy/bootstrap.sh`가 실행될 수 있게 합니다.

게스트 activation은 아래 로그와 Guest operation document를 남깁니다.

```text
/mnt/tirosh/run/activate-update.log
GET /runtime/operations/{operationId}
```

호스트 update command는 이 operation이 `completed`가 될 때까지 기다린 뒤 runtime health check로 넘어갑니다.

표준 흐름은 아래입니다.

```text
host apply-bundle
  -> replace guest-deploy on shared directory
  -> refresh cloud-init seed when guest deploy changed
  -> restart VM/proxy/watchdog
  -> run guest activation operation
      -> POST /runtime/maintenance/update-activation
      -> VM 내부에서 image load
      -> docker compose recreate
      -> Guest Control/Postgres read model 갱신
  -> host health wait
```

이 단계가 없으면 host에는 새 `guest-deploy`가 보이지만, VM Docker daemon은 이전 image/cache를 그대로 사용할 수 있습니다.

## 실패 패턴: Guest Activation 누락

Bundle 검증과 host-side artifact 교체가 통과했더라도, guest-side activation이 빠지면 VM 내부 Docker daemon은 이전 image/cache를 계속 사용할 수 있습니다.

```text
bundle integrity checked; publisher authenticity unverified
bundle staged
backup created
replace-update-artifacts completed
run-migrations: no migrations
start-runtime-services completed
wait-runtime-health started
```

이 경우 실패 지점은 보통 runtime health wait입니다.

```text
step=wait-runtime-health status=failed error=runtime health check failed
```

runtime status에는 아래와 같은 failure reason이 남을 수 있습니다.

```text
host-proxy-http-502
proxy-port-80-in-use-by-nginx-66291_nginx-66292
redis-ui-http-502
swagger-ui-http-502
guest-http-000failed
```

VM container log에는 Redis나 다른 container가 아래처럼 반복 실패할 수 있습니다.

```text
redis-1 | exec /usr/local/bin/docker-entrypoint.sh: exec format error
```

해석은 아래입니다.

| 관찰 | 의미 |
|---|---|
| `exec format error` | guest CPU architecture와 container image architecture가 맞지 않음 |
| bundle 내부 Docker image config는 정상 | bundle은 올바르지만 VM 내부 Docker daemon에 load되지 않았을 수 있음 |
| installed `guest-deploy`는 교체됨 | 새 compose와 새 image bundle은 host shared directory에 배치됨 |
| `bootstrap.log`에 최초 설치 기록만 있음 | update 후 새 image load가 수행되지 않았을 수 있음 |
| guest activation log가 없음 | Docker image load/compose recreate 단계가 실행되지 않았을 수 있음 |

이 패턴의 핵심은 “새 bundle에 올바른 image가 없었다”가 아니라, **새 Docker image bundle을 VM 내부 Docker daemon에 load/recreate하는 update 단계가 빠진 것**입니다. 이전 잘못된 image cache가 남아 있으면 compose는 계속 그 image를 사용할 수 있고, Redis 같은 서비스는 `exec format error`로 재시작 루프에 빠집니다.

부가적으로 rollback이 실패할 수도 있습니다.

```text
rollback-restore-update-artifacts failed
NSPOSIXErrorDomain Code=24 "Too many open files"
```

즉 health wait 실패 후 managed backup으로 돌아가려 했지만, app bundle 복원 중 file descriptor 한계에 걸릴 수 있습니다. 이 경우 runtime은 `critical` 상태로 남을 수 있습니다.

이 실패 패턴은 보통 세 가지가 겹칩니다.

1. guest Docker image activation 부재로 Redis가 wrong-arch image를 계속 실행
2. port 80에 이전 nginx listener가 남아 host proxy health가 502 또는 port-in-use로 실패
3. rollback 복원 중 `Too many open files`로 rollback 자체도 실패

## 필수 보강 항목

Update flow는 아래 보강을 포함해야 합니다.

| 항목 | 이유 |
|---|---|
| guest deploy activation | Docker image bundle load, compose recreate, guest bin/systemd 갱신을 update 과정에 포함 |
| cloud-init seed refresh | activation unit이 없는 이전 설치본도 부팅 시 bootstrap을 다시 수행할 수 있게 함 |
| qemu preflight 제거 | arm64 image로 운영하므로 `qemu-x86_64-static`은 runtime 필수 조건이 아님 |
| image architecture preflight | bundle의 image config가 guest architecture와 맞는지 verify 단계에서 표시 |
| stale/wrong image cleanup | 동일 tag의 wrong-arch image가 남아도 새 image를 확실히 사용하게 함 |
| rollback copy 안정화 | app bundle 복원 시 `Too many open files`를 피하도록 tar/ditto 기반 atomic restore 사용 |
| proxy port preflight | apply 전 port 80을 점유한 stale nginx를 감지하고 중단 또는 repair 안내 |
| health reason 정규화 | `guest-http-000failed`, `host-proxy-http-`처럼 빈 code가 나오지 않게 표현 정리 |

## 실패 패턴: Mutable VM Disk의 OS Package 누락

Update bundle에 guest activation 보강이 포함되어 있어도, 기존 설치본의 `vm-disk.img`가 air-gapped runtime package를 갖고 있지 않은 경우에는 VM 내부 bootstrap 단계에서 실패할 수 있습니다.

대표 로그:

```text
error: missing runtime package in air-gapped rootfs
The target bootstrap never runs apt-get. Rebuild the package rootfs with make devtools/golden-rootfs.
Required commands/services: curl, docker, docker compose, avahi-daemon, growpart.
```

이 메시지는 Product Update bundle에 rootfs가 빠졌거나, VM Image Update bundle의 `rootfs-base.raw.gz`가 잘못 교체됐다는 뜻이 아닙니다. 이미 설치되어 사용 중인 mutable disk인 `vm-disk.img` 안에 필요한 OS package가 없다는 뜻입니다.

중요한 제약:

| 항목 | 설명 |
|---|---|
| `rootfs-base.raw.gz` | VM Image Update bundle에서만 교체됨. 새 설치 또는 VM disk 재생성 기준 |
| `vm-disk.img` | 운영 중인 mutable disk. Product Update에서는 보존됨 |
| guest deploy | update로 교체됨. VM 안에서 bootstrap/activation이 실행되어야 반영됨 |
| OS package | 기존 `vm-disk.img` 안에 없으면 일반 guest deploy update만으로 추가할 수 없음 |

이 상태에서 가능한 선택지는 아래입니다.

1. 새 package로 재설치한다. `.vital` 저장 경로와 backup 보존 여부를 먼저 확인합니다.
2. Danger Zone에 VM Image replacement 기능을 추가해 `vm-disk.img`를 새 rootfs에서 재생성하고, Redis/Vital files 같은 운영 데이터를 별도로 보존/복원합니다.
3. 현장용 offline OS package bundle을 별도로 만들어 guest migration에서 설치합니다. 완전 air-gapped 제품에서는 이 방식도 artifact 검증과 rollback 정책이 필요합니다.

단순히 같은 bundle을 다시 적용하면 같은 bootstrap 실패가 반복됩니다. mutable VM disk의 OS package 상태가 원인인 경우에는 Product Update bundle이 아니라 재설치, VM Image replacement, 또는 별도 offline OS package migration이 필요합니다.

## 확인해야 할 로그

Update 실패 시 우선 아래를 봅니다.

```sh
tail -f /private/tmp/tirosh-vitalserver-manager-command.log
cat "/Library/Application Support/VitalServerHelper/status/runtime-status.json"
tail -n 200 "/Library/Application Support/VitalServerHelper/vm/data/run/container-logs.log"
tail -n 200 "/Library/Application Support/VitalServerHelper/vm/logs/proxy.err.log"
cat "/Library/Application Support/VitalServerHelper/vm/data/run/runtime-observation.json"
```

bundle 자체를 확인할 때:

```sh
tar -xOf dist/update-bundles/update-bundle-<channel>-<kind>-<releaseLabel>.tar.gz \
  update-bundle-<channel>-<kind>-<releaseLabel>/manifest.json
tar -xOf dist/update-bundles/update-bundle-<channel>-<kind>-<releaseLabel>.tar.gz \
  update-bundle-<channel>-<kind>-<releaseLabel>/guest-deploy.tar.gz | tar -tzf - | grep docker-images
```

Docker image bundle architecture를 확인할 때:

```sh
tar -xOf dist/update-bundles/update-bundle-<channel>-<kind>-<releaseLabel>.tar.gz \
  update-bundle-<channel>-<kind>-<releaseLabel>/guest-deploy.tar.gz > /tmp/guest-deploy.tar.gz
tar -xOf /tmp/guest-deploy.tar.gz deploy/docker-images/vitalserver-images.tar.gz > /tmp/vitalserver-images.tar.gz

tar -xOf /tmp/vitalserver-images.tar.gz manifest.json
```

`manifest.json`의 각 image config blob에서 `"architecture":"arm64"`인지 확인합니다.

## Recovery 원칙

Update 실패 시 가장 중요한 것은 운영 데이터 보존입니다.

1. 먼저 `runtime-status.json`과 command/container log를 저장합니다.
2. `backups/<timestamp>-before-<version>`이 있는지 확인합니다.
3. Redis data와 vital files directory를 임의로 삭제하지 않습니다.
4. rollback이 실패했다면 같은 bundle을 반복 적용하기 전에 실패 원인을 제거합니다.
5. Docker image architecture 문제가 있으면 guest-side activation 또는 재설치가 필요할 수 있습니다.
6. 재설치를 선택하더라도 `.vital` 파일 경로와 backups 보존 여부를 먼저 확인합니다.

같은 실패가 반복되는 경우에는 `Apply Bundle`을 계속 누르기보다, guest activation 로그와 container log를 먼저 확인한 뒤 원인에 맞는 recovery 절차를 선택합니다.
