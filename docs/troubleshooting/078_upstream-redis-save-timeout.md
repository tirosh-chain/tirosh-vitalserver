# Upstream Redis SAVE Timeout

## Case Metadata

| Field | Value |
|---|---|
| ID | TS-078 |
| Category | Packaging / Troubleshooting Tools / Redis migration |
| Owner | Troubleshooting Tools command |
| Status | implemented |

## Symptoms

`Create Upstream Redis Backup.command`를 실행하고 Redis URL prompt에서 Enter를 누르면 아래 로그 이후
터미널이 멈춘 것처럼 보입니다.

```text
upstream redis SAVE started
```

이 상태에서는 folder picker가 뜨지 않고 archive 생성 단계로 진행되지 않습니다.

## Cause

Troubleshooting command가 bundled Redis SAVE helper를 직접 실행하고 완료를 무기한 기다렸습니다.
Redis endpoint가 응답하지 않거나, TCP 연결/Redis protocol response/SAVE command가 예상 시간 안에
끝나지 않으면 command 전체가 외부 process 상태에 묶입니다.

Redis SAVE는 upstream Redis가 소유한 runtime state를 최신 `dump.rdb`로 쓰기 위한 선택 단계입니다.
Host command는 이 외부 상태를 성공으로 추정하면 안 되고, 응답하지 않는 dependency를 무기한 기다려도
안 됩니다.

## Actions

`Create Upstream Redis Backup.command`는 SAVE helper를 timeout wrapper로 실행합니다.
기본 timeout은 15초이며, 필요할 때만 아래 환경 변수로 조정합니다.

```bash
UPSTREAM_REDIS_SAVE_TIMEOUT_SECONDS=60 ./Create\ Upstream\ Redis\ Backup.command
```

Timeout이 발생하면 command는 helper process를 종료하고 archive 생성을 중단합니다. 운영자는 아래 중
하나를 명시적으로 선택해야 합니다.

- Redis URL이 잘못됐으면 reachable Redis URL로 다시 실행합니다.
- 이미 `dump.rdb`가 최신이면 prompt에 `skip`을 입력하고 data directory를 선택합니다.
- Redis가 느리지만 정상이라면 timeout 값을 늘려 다시 실행합니다.

## Prevention

- Troubleshooting Tools command는 external service call을 무기한 기다리면 안 됩니다.
- Timeout은 성공 fallback이 아닙니다. Timeout 후 archive를 계속 만들지 말고 명시 실패로 중단합니다.
- `dump.rdb` 최신 여부는 Redis SAVE/BGSAVE 또는 운영자 선택으로 명시되어야 하며, Host가 file 존재만으로
  최신성을 추정하면 안 됩니다.

## Related Cases

- [Backup/Restore 계약](../runtime/macos/runtime-data-backup.md)
