# VM Image Update is incorrectly marked as requiring an Updater bridge

> ID: TS-185
> Category: Update / Packaging
> Owner: macOS release Make / installed Swift Updater
> Status: implemented; apply-smoke pending

## Symptoms

- `make dist/image-update/dev` 또는 release target으로 만든 공식 `vm-image-update` bundle이 static verification은 통과합니다.
- 같은 bundle을 normal apply하면 다음 오류로 preflight에서 즉시 거부됩니다.

  ```text
  update bundle requires a bridge/two-phase update
  ```

- Manifest를 확인하면 rootfs bundle인데 `requiresTwoPhaseUpdate`가 `true`입니다.

## Impact

- 실제 Updater bridge가 필요하지 않은 VM Image/rootfs update도 설치본에 적용할 수 없습니다.
- build/static verify가 성공해 release artifact가 정상으로 보이지만, apply 경계에서만 실패하므로 배포 직전에 발견될 수 있습니다.
- 운영자가 VM Image Update와 updater bridge/two-phase Product Update를 같은 개념으로 오해할 수 있습니다.

## Cause

`internal/vm/image-update` Make target이 rootfs 포함 여부와 무관한 `VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE := true`를 강제로 설정했습니다.

Release use case와 manifest builder는 전달받은 값을 그대로 기록하고, installed Swift Updater는 정상적으로 `requiresTwoPhaseUpdate=true`인 bundle을 normal apply에서 거부했습니다. 즉 Swift compatibility gate가 원인이 아니라 Make가 두 독립적인 domain 의미를 합친 것이 원인입니다.

- `bundleKind=vm-image-update`: VM Image/rootfs/base OS 변경
- `requiresTwoPhaseUpdate=true`: 기존 Updater를 먼저 교체해야 하는 compatibility bridge

## Checks

Bundle manifest를 확인합니다.

```sh
tar -xOf dist/update-bundles/update-bundle-*-vm-image-update-*.tar.gz '*/manifest.json'
```

일반 VM Image Update의 기대값은 다음과 같습니다.

```json
{
  "bundleKind": "vm-image-update",
  "requiresTwoPhaseUpdate": false
}
```

## Actions

1. 영향받는 build의 VM Image Update를 normal apply에 반복 제출하지 않습니다.
2. 수정된 release Make target으로 bundle을 다시 생성합니다.
3. static verify 후 installed Updater의 apply preflight 또는 guarded apply-smoke까지 확인합니다.
4. 실제 manifest/schema/result 계약 변경 때문에 Updater bridge가 필요한 경우에만 별도 Product Update를 `VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE=true`로 생성합니다.

## Prevention

- Make의 기본 bridge flag는 `false`이며 image/rootfs target에서 덮어쓰지 않습니다.
- release use case는 명시 입력을 bundle kind나 artifact로 추론하지 않고 manifest builder에 전달합니다.
- manifest contract 테스트는 rootfs가 포함된 `vm-image-update`의 flag가 `false`인 것과 명시적인 bridge Product Update의 flag가 `true`인 것을 각각 검증합니다.
- Swift Application 테스트는 일반 VM Image Update가 apply preflight를 통과하고 명시적 bridge bundle은 계속 거부되는 것을 검증합니다.
- static verification만 release proof로 사용하지 않고 apply preflight contract test를 유지합니다.

## Operational Notes

- VM Image Update가 Danger Zone 대상이라는 사실은 updater bridge 필요 여부와 별개입니다.
- `minUpdaterVersion`이 현재 설치된 Updater보다 높으면 `requiresTwoPhaseUpdate=false`여도 compatibility preflight에서 별도로 거부됩니다. 두 gate를 같은 상태로 합치지 않습니다.
- 이 수정은 signature 검증이나 migration rollback 의미를 변경하지 않습니다.

## Related Cases

- [TS-027](027_update-stale-pwa-assets.md)
- [TS-035](035_update-guest-capability-contract-missing.md)
- [ADR 0004](../adr/0004-product-update-and-vm-image-update-contract.md)

## Follow-up

- 2026-07-27: Make의 image-update 강제 flag를 제거하고 Make/manifest/Swift apply-preflight contract tests를 추가했습니다. 실제 설치본 guarded apply-smoke는 아직 필요합니다.
