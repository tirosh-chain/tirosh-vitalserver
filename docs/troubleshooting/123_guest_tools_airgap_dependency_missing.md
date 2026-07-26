# Guest Tools air-gap dependency missing from wheelhouse

> ID: TS-123
> Category: Packaging / Guest bootstrap
> Owner: devtools Guest wheelhouse staging
> Status: active

## Symptoms

`make dist/dmg/dev` 또는 golden rootfs compile이 현재 run의 failure proof를 보고 중단됩니다.

```text
error: guest rootfs preparation failed while waiting for rootfs marker:
stage=guest-tools-install exitCode=1 reason=guest-rootfs-prepare-failed
```

`launcher.log`의 같은 run에는 offline pip 실패가 있습니다.

```text
ERROR: Could not find a version that satisfies the requirement psycopg==3.3.4
ERROR: No matching distribution found for psycopg==3.3.4
error: Guest Tools offline dependency installation failed: exitCode=1
```

APT plan이 `allowed`이고 runtime package 설치가 끝났더라도 `rootfs-ready`는 생성되지 않는 것이 정상입니다. Guest Tools dependency closure가 완전하지 않은 rootfs는 product compile 성공 상태가 아닙니다.

## Impact

Golden rootfs와 DMG compile이 중단됩니다. 실패한 temporary golden VM은 종료되고 불완전한 rootfs는 package input으로 승격되지 않습니다. 설치된 runtime data를 변경하는 단계에는 도달하지 않습니다.

## Cause

Guest Tools project metadata에 `psycopg[binary]==3.3.4`가 추가됐지만 CPython 3.12용 architecture별 air-gap lock에는 `psycopg`와 `psycopg-binary`가 없었습니다. Repository root `uv.lock`은 Host 개발 Python 계약이며 Guest runtime lock의 authority가 아닙니다.

기존 wheelhouse staging은 target lock에 적힌 wheel의 hash와 파일 존재만 검증했습니다. 새로 만든 Guest Tools wheel의 `Requires-Dist`와 staged dependency 전체를 offline resolver로 대조하지 않아, 누락이 Host staging이 아니라 VM의 `guest-tools-install`에서 늦게 발견됐습니다.

ARM64에서는 `psycopg-binary 3.3.4`가 `manylinux_2_28_aarch64` wheel을 제공하는 반면 일부 기존 dependency는 `manylinux2014_aarch64` wheel을 제공합니다. Guest Ubuntu 24.04가 허용하는 두 platform tag를 target contract에 함께 표현해야 하나의 명시 dependency closure를 구성할 수 있습니다.

## Checks

현재 run의 explicit failure와 실제 pip 오류를 확인합니다.

```sh
sed -n '1,220p' .tmp/vitalserver-vm-golden/data/run/rootfs-failure.json
sed -n '1,220p' .tmp/vitalserver-vm-golden/data/run/rootfs-apt-plan.json
rg -n 'No matching distribution|offline dependency installation failed' \
  .tmp/vitalserver-vm-golden/logs/launcher.log
```

Guest metadata와 target-specific lock을 각각 확인합니다.

```sh
sed -n '1,40p' packages/vitalserver-guest-tools/pyproject.toml
sed -n '1,80p' packages/vitalserver-guest-tools/requirements/guest-runtime-linux-aarch64.txt
sed -n '1,80p' packages/vitalserver-guest-tools/requirements/guest-runtime-linux-amd64.txt
```

## Actions

1. Guest Tools의 direct/transitive dependency를 ARM64와 AMD64 lock에 version/hash로 명시합니다.
2. 각 target에 실제로 제공되는 CPython 3.12 wheel platform tag를 확인합니다.
3. 두 architecture wheelhouse를 독립적으로 staging해 offline closure를 검증합니다.
4. 검증 후 clean golden rootfs compile을 다시 실행합니다.

```sh
tmpdir="$(mktemp -d)"
uv run python scripts/stage_guest_runtime_wheelhouse.py \
  --project packages/vitalserver-guest-tools \
  --output "$tmpdir/arm64" \
  --target linux-aarch64
uv run python scripts/stage_guest_runtime_wheelhouse.py \
  --project packages/vitalserver-guest-tools \
  --output "$tmpdir/amd64" \
  --target linux-amd64
```

## Prevention

Wheelhouse staging은 다운로드된 lock 파일 집합만 검사하지 않습니다. 생성한 Guest Tools wheel을 포함한 최종 requirements를 target Python/platform 조건과 `--no-index --require-hashes`로 다시 resolve합니다. Project dependency, extra dependency, target lock 또는 wheel이 하나라도 빠지면 VM 시작 전 Host compile 단계에서 실패합니다.

Target-specific lock을 repository root `uv.lock`으로 대체하거나 missing wheel을 Guest network install로 보정하지 않습니다. Guest Python version과 platform compatibility는 release input으로 명시합니다.

## Operational Notes

`rootfs-failure.json`의 `runId`가 `golden-rootfs-run.json`의 runId와 같은지 먼저 확인합니다. 다른 run의 launcher log나 failure marker를 현재 실패로 해석하지 않습니다.

## Related Cases

- TS-069: Golden rootfs proof와 current run 경계
- TS-071: Golden rootfs external dependency fast-fail
- TS-120: Generated Guest wheel과 rootfs fingerprint

## Follow-up

- 2026-07-13: `psycopg[binary]` 추가 후 target lock 누락으로 `guest-tools-install`이 실패했습니다. ARM64 compatible platform tag와 architecture별 hashes를 명시하고 Host-side offline dependency closure validation을 추가했습니다.
