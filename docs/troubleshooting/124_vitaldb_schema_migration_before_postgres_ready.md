# VitalDB schema migration runs before Postgres readiness

> ID: TS-124
> Category: Guest bootstrap / Data store
> Owner: Guest bootstrap workflow
> Status: active

## Symptoms

Golden rootfs compile과 DMG artifact verification은 통과하지만 마지막 runtime boot smoke가 실패합니다.

```text
error: runtime boot smoke bootstrap failed:
stage=bootstrap-result reasonCodes=['guest-bootstrap-failed']
```

같은 runId의 launcher log에는 다음 dependency failure가 있습니다.

```text
VitalDB database schema migration failed
connection to server at "127.0.0.1", port 15432 failed: Connection refused
Command '['/usr/local/bin/tirosh-runtime-observation', 'once']' returned non-zero exit status 1
```

## Impact

Bootstrap completed proof가 만들어지지 않으므로 runtime smoke와 표준 `make dist/dmg/dev` gate가 실패합니다. DMG 파일이 만들어졌더라도 delivery proof가 아니며 배포 대상으로 사용하면 안 됩니다.

## Cause

Bootstrap workflow가 control SQLite migration 직후, Docker와 Compose를 시작하기 전에 초기 runtime observation을 실행했습니다. VitalDB schema owner가 SQLAlchemy migration을 observation 유무와 관계없이 수행하도록 수정된 뒤에는 이 observation이 아직 시작되지 않은 Product Postgres에 연결했습니다.

Postgres connection refusal를 empty read model이나 성공 observation으로 바꾸는 것은 올바른 조치가 아닙니다. Dependency state는 실제 failure이며, bootstrap lifecycle이 migration을 실행할 수 있는 명시 readiness 상태에 아직 도달하지 않은 것이 순서 위반입니다.

## Checks

```sh
sed -n '1,220p' \
  .tmp/vitalserver-vm-golden-runtime-smoke/data/run/bootstrap-result.json
rg -n -C 8 'schema migration|Connection refused|runtime-observation' \
  .tmp/vitalserver-vm-golden-runtime-smoke/logs/launcher.log
```

`bootstrap-result.json.bootID`와 runtime smoke run의 boot ID가 같은지 확인하고 다른 run의 connection failure를 현재 상태로 해석하지 않습니다.

## Actions

Bootstrap의 ordered Compose start를 완료합니다. 이 operation은 Postgres container를 먼저 시작하고 readiness를 확인한 뒤 나머지 product service를 시작합니다. 그 다음 초기 runtime observation을 실행해 schema migration과 explicit read model state를 기록합니다.

Workflow 순서는 다음 invariant를 가져야 합니다.

```text
prepare runtime data
→ migrate control SQLite
→ start Docker
→ start ordered Compose and wait for Postgres
→ write initial runtime observation and migrate VitalDB schema
→ wait for edge readiness
```

## Prevention

Bootstrap state machine은 `write-initial-runtime-observation`이 `start-compose` 완료 전에 실행되는 것을 guard로 거부합니다. Postgres failure는 typed dependency failure로 유지하고 retry/default/empty state로 숨기지 않습니다.

Schema lifecycle에는 두 조건이 모두 필요합니다.

- observation payload가 아직 없어도 schema owner는 migration을 수행해야 합니다.
- Product Postgres readiness가 확인되기 전에는 migration transition을 시작하지 않아야 합니다.

## Operational Notes

이미 생성된 DMG가 있더라도 runtime smoke failure 이후에는 표준 delivery gate가 완료되지 않은 상태입니다. 수정 후 clean golden compile과 runtime smoke를 모두 다시 실행합니다.

## Related Cases

- TS-122: VitalDB read model schema startup race
- TS-123: Guest Tools air-gap dependency missing from wheelhouse

## Follow-up

- 2026-07-13: psycopg air-gap 설치 수정 후 runtime smoke가 초기 observation의 Postgres connection refusal를 드러냈습니다. Initial observation을 ordered Compose/Postgres readiness 이후로 이동하고 workflow guard test를 추가했습니다.
