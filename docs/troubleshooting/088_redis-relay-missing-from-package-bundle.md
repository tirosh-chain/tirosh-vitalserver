# Redis Relay Missing From Package Bundle

> ID: TS-088
> Category: Packaging / Guest bootstrap
> Owner: `packages/vitalserver-devtools`, macOS runtime release manifest
> Status: implemented

## Symptoms

- Fresh install 직후 Helper Status가 `VM state: Failed`를 표시합니다.
- `VM errors`에 `Guest runtime state stale`, `Guest bootstrap failed`가 함께 보입니다.
- Service liveness는 대부분 `Initializing`에 머물고, VitalServer는 `HTTP missing-vm-ip`를 표시할 수 있습니다.
- guest observability에는 Redis container만 올라오고 `tirosh-vitalserver-compose.service`가 `failed`로 남습니다.

## Impact

- 설치는 완료된 것처럼 보일 수 있지만 guest service stack이 올라오지 않습니다.
- VitalServer UI, My Files, observer, recorder ingress, Redis Relay가 모두 사용할 수 없습니다.
- Redis data 자체 문제는 아니며, 새 설치 bootstrap 산출물 구성 문제입니다.

## Cause

`redis-relay` compose service가 추가됐지만 macOS package/build/provision contract에 같은 변경이 끝까지 반영되지 않았습니다.

- `Support/Guest/compose.yaml`에는 `redis-relay` service와 `apps/vitalserver-redis-relay/Dockerfile` build path가 존재했습니다.
- `config/vm-build.toml`의 Docker image bundle 목록에는 `vitalserver-redis-relay:0.1.0`이 없었습니다.
- `guest.deploy.include`에도 `apps/vitalserver-redis-relay`가 없었습니다.
- 설치된 guest deploy directory에는 relay Dockerfile/source가 없고, image bundle에도 relay image가 없어 bootstrap compose 단계가 실패했습니다.
- 이후 image/source 누락을 고친 뒤에도 fresh install provisioning이 relay bind source directory를 만들지 않으면 같은 bootstrap 실패가 재발합니다. `redis-relay`가 disabled여도 compose는 아래 Host-owned bind source를 요구합니다.
  - `/mnt/tirosh/deploy/redis-relay-config/redis-relay.toml`
  - `/mnt/tirosh/deploy/redis-relay-secrets`
  - `/mnt/tirosh/run/redis-relay-status`

## Checks

설치된 장비에서 원인을 볼 때는 아래 파일을 먼저 확인합니다.

```sh
sudo cat "/Library/Application Support/VitalServerHelper/vm/data/run/bootstrap-result.json"
sudo cat "/Library/Application Support/VitalServerHelper/vm/data/run/guest-observability/latest.json"
sudo grep -n "redis-relay" "/Library/Application Support/VitalServerHelper/vm/data/deploy/compose.yaml"
sudo find "/Library/Application Support/VitalServerHelper/vm/data/deploy/apps" -maxdepth 2 -type d
sudo find "/Library/Application Support/VitalServerHelper/vm/data/deploy/redis-relay-config" -maxdepth 1 -type f
sudo find "/Library/Application Support/VitalServerHelper/vm/data/deploy/redis-relay-secrets" -maxdepth 1
sudo find "/Library/Application Support/VitalServerHelper/vm/data/run/redis-relay-status" -maxdepth 1
```

패키징 source tree에서는 아래 계약이 함께 있어야 합니다.

```sh
grep -n "redis_relay" config/vm-build.toml
grep -n "vitalserver-redis-relay" config/vm-build.toml
grep -n "apps/vitalserver-redis-relay" config/vm-build.toml
grep -n "redisRelay" apps/vitalserver-macos-runtime/release-dev.json
```

## Actions

수정된 package로 재빌드합니다.

1. `release.json`과 `release-dev.json`에 `redisRelay` service를 추가합니다.
2. `config/vm-build.toml`에 relay image, Dockerfile, deploy include를 추가합니다.
3. Docker image bundle build가 `vitalserver-redis-relay:0.1.0`을 빌드하고 저장하는지 확인합니다.
4. install-provision이 relay config/secrets/status bind source directory와 기본 disabled `redis-relay.toml`을 생성하는지 확인합니다.
5. `make dist/dmg/dev/compile` 또는 `make dist/dmg/dev/all`을 실행해 compose image/build contract preflight를 통과시킵니다.
6. 기존 설치본은 clean uninstall 후 새 DMG로 다시 설치합니다.

## Prevention

- macOS package preflight는 guest compose에 선언된 service image가 `guest.docker_images.images` 또는 `optional_images`에 존재하는지 검사합니다.
- compose build dockerfile은 `guest.docker_images.*_dockerfile`과 일치해야 합니다.
- compose build dockerfile path는 `guest.deploy.include`에 포함되어야 합니다.
- Host install-provision은 disabled optional service도 compose bind mount 계약에 필요한 config/secrets/status source를 생성해야 합니다. UI disabled는 process 동작 여부이지 bind source 부재를 의미하지 않습니다.
- `dist/dmg/dev/compile`에서 이 contract가 깨지면 Docker build나 DMG 생성 전에 실패해야 합니다.
- `dist/dmg/dev/all`은 compile을 포함하므로 같은 누락을 설치 전 gate에서 막아야 합니다.

## Operational Notes

- Redis Relay가 UI에서 disabled인 것은 relay process의 동작 여부입니다. compose service와 image bundle 계약에서는 필수 service로 취급합니다.
- Helper UI의 `Disabled` 상태와 package bundle에서 image/source가 없는 상태는 다른 의미입니다.
- Helper UI의 `Disabled` 상태와 install-provision에서 기본 relay config directory가 없는 상태도 다른 의미입니다.
- 같은 증상이 재발하면 runtime status만 보지 말고 installed deploy directory와 image bundle 구성도 확인합니다.

## Related Cases

- `TS-082`: 배포 target이 phase별 검증 완료를 명확히 증명하지 못함
- `TS-087`: OOM recovery 이후 watchdog service가 빠져 status가 recovering에 머묾

## Follow-up

- 2026-06-19: fresh install에서 Redis만 올라오고 `redis-relay` build source/image가 누락된 상태를 확인했습니다. 패키지 preflight에 compose image/build/deploy contract 검사를 추가했습니다.
- 2026-06-19: image/source 포함 후에도 fresh install에서 `redis-relay-config`, `redis-relay-secrets`, `redis-relay-status` bind source가 없어 compose start가 실패하는 상태를 확인했습니다. Host install-provision이 기본 disabled relay config를 생성하도록 수정했습니다.
