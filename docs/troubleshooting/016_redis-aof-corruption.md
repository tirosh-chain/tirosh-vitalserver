# 016 Redis AOF 손상으로 runtime health가 회복되지 않음

> ID: TS-016  
> Category: Data store  
> Owner: macOS runtime  
> Status: active

증상:

bundle update 또는 재부팅 이후 VitalServer, Network access, Redis UI, Swagger UI가
502 또는 500을 반환하고, Redis container가 재시작을 반복합니다. Redis container
log에는 AOF 검사 결과와 함께 아래 startup 거부 메시지가 기록됩니다.

```text
Bad file format reading the append only file
make a backup of your AOF file, then use ./redis-check-aof --fix <filename>
Redis append-only file validation failed; automatic repair is disabled.
Run the explicit datastore repair workflow before restarting Redis.
```

원인:

Redis append-only file이 손상되면 Redis가 기동하지 못하고 재시작을 반복합니다.
VitalServer app은 Redis에 의존하므로 Redis가 준비되지 않으면 app readiness도
실패하고, host proxy는 최종적으로 502를 반환합니다.

Guest Compose의 Redis startup은 `redis-check-aof`를 read-only 검사로만 사용합니다.
검사가 실패하면 startup은 원본 AOF를 복사하거나 `--fix`로 변경하지 않고 실패합니다.
이는 자동 복구 성공이 아닙니다. 손상 상태와 원본 파일을 보존하여 명시적인 datastore
repair operation이 판단하고 변경하도록 하는 fail-closed 동작입니다.

조치:

먼저 Redis container log와 runtime health에서 AOF 손상인지 확인합니다. 손상이
확인되었을 때만 아래 명시적 복구 작업을 실행합니다.

```sh
sudo vitalserver-vm runtime repair-datastore
```

이 명령은 Guest Control maintenance API에 `repair-datastore` operation을 생성합니다.
Guest Control SQLite operation store가 accepted, running, completed 또는 failed 상태를
소유합니다. Guest repair adapter는 원본 AOF를
`appendonly.aof.bak.<timestamp>`로 복사하는 데 성공한 뒤에만
`redis-check-aof --fix`를 실행하고 Compose를 다시 시작합니다. Backup copy 실패,
AOF repair 실패, Compose restart 실패는 operation failure로 남으며 startup이 이를
성공으로 보정하지 않습니다.

Guest repair log는 아래 위치에서 확인할 수 있습니다.

```text
/Library/Application Support/VitalServerHelper/vm/data/run/repair-datastore.log
```

그래도 회복되지 않으면 managed backup rollback을 다시 시도하거나, vital files를
보존한 상태로 runtime을 재설치합니다.

## 예방 원칙

- Container startup은 datastore를 검사할 수 있지만 repair state를 소유하거나 파일을
  자동 변경하지 않습니다.
- AOF를 절단할 수 있는 `redis-check-aof --fix`는 persisted Guest Control operation을
  통해서만 실행합니다.
- Repair는 원본 backup 생성 성공을 선행 조건으로 삼습니다. `cp` 실패를 무시한 채
  repair를 진행하지 않습니다.
- Redis가 손상된 상태에서 unavailable인 것은 정상적인 fail-closed 결과입니다.
  Empty/default success나 자동 정상 상태로 바꾸지 않습니다.

## Follow-up

- 2026-07-27: Guest Compose startup의 `cp ... || true`와 자동
  `redis-check-aof --fix`를 제거했습니다. Startup은 read-only 검사 실패를 보고하고
  종료하며, 명시적인 Guest Control datastore repair operation만 AOF backup과 repair를
  수행합니다.
