# Golden Runtime Smoke Missing Runtime Settings

> ID: TS-093  
> Category: Packaging / Guest bootstrap  
> Owner: macOS runtime packaging  
> Status: active

## Symptoms

- `make dist/dmg/dev/verify` 또는 golden runtime smoke가 아래처럼 실패합니다.

```text
manifest missing: .tmp/vitalserver-vm-golden-runtime-smoke/data/run/runtime-boot-smoke-manifest.json
Check VM launcher log: .tmp/vitalserver-vm-golden-runtime-smoke/logs/launcher.log
make[3]: *** [internal/vm/wait/runtime-boot-smoke] Error 1
```

- `launcher.log`에는 VM boot 이후 `tirosh-vitalserver-compose.service`가 실패한 기록이 남습니다.

```text
FAILED Failed to start tirosh-vitalserver-compose.service
subprocess.CalledProcessError: Command '['systemctl', 'start', 'tirosh-vitalserver-compose.service']' returned non-zero exit status 1.
```

## Impact

- golden runtime smoke가 runtime boot proof를 만들지 못해 dev DMG/pkg verify가 실패합니다.
- VM guest는 부팅될 수 있지만 Compose stack이 시작되지 않으므로 VitalServer, Redis UI, Swagger UI health probe가 모두 실패합니다.
- 이 증상 자체는 data loss가 아니라 packaging input contract 누락입니다.

## Cause

Guest compose runner는 deploy `runtime-settings.json`을 명시 runtime settings contract로 읽습니다. golden smoke deploy bundle이 `Support/Guest` 파일을 복사할 때 이 파일이 없으면 compose runner가 env 생성 전에 실패하고, bootstrap은 runtime smoke manifest를 만들 단계까지 가지 못합니다.

`runtime-boot-smoke-manifest.json` 누락은 최종 원인이 아니라 bootstrap 실패의 결과입니다.

## Checks

```sh
vm_home=".tmp/vitalserver-vm-golden-runtime-smoke"

cat "$vm_home/data/run/bootstrap-result.json"
tail -n 200 "$vm_home/logs/launcher.log"
ls "$vm_home/data/deploy/runtime-settings.json"
```

확인할 증거는 아래입니다.

- `bootstrap-result.json` status가 `failed`
- `launcher.log`에 `tirosh-vitalserver-compose.service` start failure
- deploy directory에 `runtime-settings.json` 누락

## Actions

- packaging source에 `apps/vitalserver-macos-runtime/Support/Guest/runtime-settings.json`이 포함되어 있는지 확인합니다.
- 파일이 누락된 빌드 산출물은 guest deploy bundle 또는 dev DMG/pkg를 다시 빌드합니다.
- 실패한 `.tmp/vitalserver-vm-golden-runtime-smoke`는 다음 verify에서 새 deploy staging이 반영되도록 stale artifact로 판단합니다.

## Prevention

- `Support/Guest/runtime-settings.json`을 기본 guest deploy contract로 유지합니다.
- devtools deploy bundle test는 `runtime-settings.json`이 deploy directory로 복사되는지 확인해야 합니다.
- packaging template test는 recorder ingress hot/cold path 관련 기본 설정값이 settings 문서에 들어 있는지 확인해야 합니다.

## Related Cases

- `TS-082`: Distribution verification phase gaps
- `TS-088`: Redis Relay Missing From Package Bundle
- `TS-091`: Golden Rootfs Cleanup Wait Timeout

## Follow-up

- 2026-06-29: recorder ingress runtime settings를 guest compose env로 연결한 뒤 golden runtime smoke가 `runtime-settings.json` 누락으로 실패하는 경로를 확인했습니다. 기본 settings contract를 `Support/Guest`에 추가하고 devtools packaging/deploy tests로 고정했습니다.
