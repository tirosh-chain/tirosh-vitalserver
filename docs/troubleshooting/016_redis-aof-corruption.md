# 016 Redis AOF 손상으로 runtime health가 회복되지 않음

> ID: TS-016  
> Category: Data store  
> Owner: macOS runtime  
> Status: active

증상:

bundle update 이후 VitalServer, Network access, Redis UI, Swagger UI가 502 또는 500을 반환하고, Redis container log에 아래 오류가 반복됩니다.

```text
Bad file format reading the append only file
make a backup of your AOF file, then use ./redis-check-aof --fix <filename>
```

원인:

Redis append-only file이 손상되면 Redis가 기동하지 못하고 재시작을 반복합니다. VitalServer app은 Redis에 의존하므로 Redis가 준비되지 않으면 app readiness도 실패하고, host proxy는 최종적으로 502를 반환합니다.

조치:

최신 guest compose는 Redis container 시작 전에 `redis-check-aof`를 실행합니다. AOF가 깨져 있으면 기존 파일을 `.bak.<timestamp>`로 백업한 뒤 `redis-check-aof --fix`를 수행하고 Redis를 시작합니다.

이미 이전 bundle로 update가 진행 중이라면, 실행 중인 old runtime binary에는 이 복구 로직이 없습니다. 현재 apply/rollback 작업이 끝난 뒤 Redis AOF 복구가 포함된 새 bundle을 다시 적용합니다.

최신 runtime에서는 아래 복구 명령도 사용할 수 있습니다.

```sh
sudo vitalserver-vm runtime repair-datastore
```

이 명령은 host에서 `/Library/Application Support/TiroshVitalServer/vm/data/run/repair-datastore.request`를 만들고, VM 내부의 `tirosh-vitalserver-repair-datastore.path`가 이를 감지해 Redis AOF를 검사/복구합니다. 복구 결과는 아래 파일에 기록됩니다.

```text
/Library/Application Support/TiroshVitalServer/vm/data/run/repair-datastore-result.json
/Library/Application Support/TiroshVitalServer/vm/data/run/repair-datastore.log
```

그래도 회복되지 않으면 managed backup rollback을 다시 시도하거나, vital files를 보존한 상태로 runtime을 재설치합니다.

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
