# Update Activation Compose/Systemd Race

> ID: TS-060  
> Category: Update  
> Owner: guest update activation  
> Status: active

## Symptoms

- VitalServer helper update가 실패하고 rollback이 수행된다.
- `activate-update-result.json`에는 `Guest update activation failed. See activate-update.log.`가 기록된다.
- `activate-update.log`에는 `docker compose ... up -d edge` 실패가 보인다.
- 실패 직후 health는 회복될 수 있지만, host update 결과는 `bundle apply failed; rollback completed: runtime health check failed`처럼 남는다.

## Impact

- update bundle activation이 실패하고 rollback으로 돌아간다.
- Redis backup/shutdown race와 달리, 이 케이스 자체는 guest filesystem 손상이나 rootfs 불안정의 직접 증거가 아니다.
- 실패 직후 runtime health가 정상이어도 update 결과는 실패로 남을 수 있다.

## Cause

Guest boot/bootstrap path와 update activation path가 같은 Docker Compose project를 동시에 조작했다.

확인된 실패에서는 `tirosh-vitalserver-compose.service`와 `tirosh-vitalserver-testkit.service`가 failed 상태였고, 동시에 `tirosh-vitalserver-activate-update.service`가 `docker compose --project-name vitalserver ... up -d edge`를 실행하고 있었다. 즉 Docker 자체나 Linux rootfs보다 systemd unit orchestration 경합이 원인에 가깝다.

## Checks

```sh
sudo cat "/Library/Application Support/VitalServerHelper/vm/data/run/activate-update-result.json"
sudo tail -n 200 "/Library/Application Support/VitalServerHelper/vm/data/run/activate-update.log"
sudo cat "/Library/Application Support/VitalServerHelper/vm/data/run/guest-observability/activation-failure.latest.json"
```

Guest 안에서는 다음 상태를 확인한다.

```sh
systemctl status tirosh-vitalserver-activate-update.service
systemctl status tirosh-vitalserver-compose.service
systemctl status tirosh-vitalserver-testkit.service
docker ps -a --filter name=vitalserver
```

## Actions

- 최신 guest-tools update activation에서는 activation 시작 전에 `tirosh-vitalserver-testkit.service`와 `tirosh-vitalserver-compose.service`를 stop하고 inactive/failed 상태가 될 때까지 기다린다.
- failed unit은 activation recreate 전에 `reset-failed`로 정리한다.
- activation 중 compose/testkit unit이 systemd에 의해 동시에 시작되지 않도록 activation unit에 `Conflicts=`를 둔다.
- testkit unit은 compose unit을 직접 `Wants=`하지 않고, 둘이 같이 시작될 때 순서만 보장하도록 `After=`만 유지한다.

## Prevention

- 같은 Docker Compose project를 조작하는 owner를 activation 순간에는 하나로 제한한다.
- update activation은 boot/bootstrap의 compose start 상태를 추정하지 않고, systemd unit 상태를 명시적으로 읽고 실패를 드러낸다.
- optional TestKit provisioning은 activation 완료 후 비동기로 예약하되, activation 본체의 compose recreate와 동시에 실행하지 않는다.

## Operational Notes

- activation 실패 후 runtime health가 정상으로 돌아왔더라도 update는 성공으로 해석하지 않는다. rollback 결과와 activation 로그를 함께 확인한다.
- `activate-update.log`의 단일 compose 실패만으로 rootfs나 kernel 문제로 단정하지 않는다. 같은 시각의 systemd unit state와 process snapshot을 먼저 확인한다.

## Related Cases

- TS-012
- TS-013
- TS-053

## Follow-up

- 2026-06-09: helper update 실패 로그에서 activation과 compose/testkit systemd unit 경합을 확인했다. guest-tools activation quiesce와 systemd unit conflict로 예방한다.
