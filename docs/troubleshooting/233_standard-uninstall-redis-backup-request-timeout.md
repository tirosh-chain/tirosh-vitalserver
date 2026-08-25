# Standard uninstall times out while Redis backup completes

> ID: TS-233  
> Category: Uninstall / Data store / Runtime Control  
> Owner: macOS Runtime Guest Control adapter  
> Status: active

## Symptoms

표준 제거가 파일을 지우기 전에 다음 오류로 중단됩니다.

```text
step=create-vitalserver-backup status=started
standard uninstall aborted because VitalServer backup did not complete
error=guest control API request failed url=http://<guest>:18330/runtime/maintenance/redis-backup reason=The request timed out.
```

설치 receipt가 그대로 남으므로 같은 `0.2.2` PKG를 이어서 설치하면 `intent=same-version-repair`와 `fresh-only` gate에 의해 차단됩니다. 이 두 번째 오류는 설치기 결함이 아니라, 앞선 표준 제거가 완료되지 않았다는 명시적 결과입니다.

## Impact

표준 제거와 뒤이은 fresh install이 진행되지 않습니다. 제거 workflow는 backup failure 뒤 파일 삭제를 시작하지 않으므로 product data는 보존됩니다. `--clean` 또는 force-clean으로 우회하면 보존 의도가 달라지므로 자동 조치로 사용하면 안 됩니다.

## Cause

Guest의 `POST /runtime/maintenance/redis-backup`은 operation을 영속화한 뒤 Redis `SAVE`, volume archive 생성, terminal operation 저장을 동기 완료하고 응답합니다. Host adapter는 이 요청에 일반 Guest 상태 조회와 같은 5초 timeout을 사용했습니다.

2026-08-25 설치 환경에서 같은 API의 정상 완료는 4.160640초가 걸렸습니다. 정상 경로의 여유가 1초보다 작아 Redis 크기나 실행 부하가 조금만 달라져도 Host가 먼저 transport timeout을 냈습니다. Timeout은 Guest operation 실패와 같은 의미가 아니며, archive 또는 로그 존재만으로 성공으로 바꿀 수도 없습니다.

## Checks

먼저 설치 receipt와 uninstall log를 확인합니다.

```sh
tail -n 200 "/Library/Application Support/VitalServerHelper/logs/uninstall.log"
pkgutil --pkg-info ai.tirosh.vitalserver.helper
```

Guest readiness는 backup 성공 증거가 아니라 dependency 진단입니다.

```sh
curl --silent --show-error --max-time 10 \
  http://<guest-address>:18330/ready
```

## Actions

수정된 Host CLI를 포함한 package에서는 Redis/PostgreSQL backup POST가 명시적인 900초 request timeout을 사용합니다. 표준 제거를 다시 실행하고, completed operation의 archive를 받아 통합 VitalServer backup까지 완료된 뒤에만 fresh install을 진행합니다.

수정 전 설치본에서 이 증상이 발생하면 `--clean`으로 우회하지 않습니다. 제품 데이터를 보존해야 한다면 수정된 Host CLI로 동일한 표준 uninstall workflow를 실행하거나, 지원 절차를 통해 기존 설치를 업데이트한 뒤 제거합니다.

## Prevention

- 일반 상태 조회 timeout과 archive 생성 timeout을 같은 값으로 공유하지 않습니다.
- 장시간 작업은 명시적이고 bounded한 시간 예산을 사용합니다.
- Timeout, Guest operation failure, completed operation은 서로 다른 의미로 유지합니다.
- Host는 archive 파일이나 로그를 보고 operation 성공을 추정하지 않습니다.
- Gateway 회귀 테스트는 Redis/PostgreSQL backup request의 timeout 값을 검증합니다.

## Operational Notes

표준 제거 실패 직후 `same-version-repair` install 차단은 정상입니다. 설치 receipt를 수동 삭제하거나 direct PKG gate를 우회하지 않습니다. 기존 데이터 보존 여부를 명시적으로 결정하기 전에는 clean uninstall을 실행하지 않습니다.

## Related Cases

- [TS-042 Host install/uninstall state contract gap](042_host-install-uninstall-state-contract-gap.md)
- [TS-078 Upstream Redis SAVE timeout](078_upstream-redis-save-timeout.md)
- [TS-187 Standard uninstall retained data blocks fresh package install](187_standard-uninstall-retained-data-blocks-fresh-install.md)

## Follow-up

- 2026-08-25: 표준 제거에서 같은 Redis backup 5초 timeout이 반복 재현됐습니다. 같은 installed Guest API를 120초 관찰 창으로 호출했을 때 operation `op_redis-backup_redis-backup_9476b7c57109424fad42d3cd29afbf83`이 4.160640초에 `completed`로 끝나고 명시적 archive path를 반환했습니다.
