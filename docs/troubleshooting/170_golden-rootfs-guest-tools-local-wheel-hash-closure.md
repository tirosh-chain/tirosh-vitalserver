# Golden rootfs가 Guest Tools local wheel hash closure에서 실패함

> ID: TS-170
> Category: Packaging / Guest bootstrap
> Owner: macOS runtime packaging
> Status: fixed, package verification pending

## Symptom

Golden rootfs compile이 `stage=guest-tools-install`에서 종료되고 Host에는 다음 proof가 남는다.

```text
guest rootfs preparation failed while waiting for rootfs marker
reason=guest-rootfs-prepare-failed
```

Guest launcher log에는 requirements의 SHA-256 하나가 `unexpected`라고 기록된다.

```text
Guest Tools requirements do not pin every manifest wheel:
missing=[] unexpected=['<sha256>']
```

## Cause

Wheelhouse builder는 Guest Tools가 직접 의존하는 repository-local wheel을
`manifest.localDependencies`에 기록하고 target requirements에도 hash-pin한다.
Runtime installer validator는 `guestTools`와 target별 `wheels`만 expected hash 집합에
넣고 `localDependencies`를 누락했다. 따라서 올바른 requirements가 오히려 extra hash를
가진 것으로 분류되었다. APT, VM boot, wheel download 실패가 아니다.

## Fix direction

Runtime installer는 `localDependencies`가 명시적인 list인지 검증하고, 각 entry의
상대 경로가 wheelhouse root를 벗어나지 않는지, `.whl`인지, 실제 SHA-256이 manifest와
일치하는지를 검증한다. 그 후 guest wheel, local dependency wheels, target wheels의
전체 hash 집합과 requirements hash 집합이 정확히 같은지 확인한다.

## Verification

```bash
uv run pytest -q packages/vitalserver-devtools/tests/unit/test_guest_deploy_bundle.py \
  -k guest_tools_runtime_installer
make internal/vm/dmg/dev
```

두 번째 명령의 golden rootfs proof에서 같은 runId의 `rootfs-ready.json`이 생성되고
`guest-tools-install` stage failure가 없어야 한다.

## Prevention

Requirements closure를 별도의 추정 dependency 목록으로 검증하지 않는다. Wheelhouse
manifest가 소유하는 `guestTools`, `localDependencies`, target `wheels`를 모두 명시적으로
읽어 동일한 closure를 구성한다. 새 manifest wheel category를 추가할 때 builder와
runtime validator의 통합 테스트를 같은 변경에 포함한다.

## Related cases

- `TS-138`: rootfs 준비 후 lifecycle proof 소비 실패
- `TS-162`: staged deploy와 rootfs receipt hash 불일치
