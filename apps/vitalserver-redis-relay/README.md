# vitalserver-redis-relay

`vitalserver-redis-relay`는 VitalServer Source Redis에서 허용된 key snapshot을 읽어
운영자가 지정한 Target Redis로 전달하는 Protocol v1 publisher입니다. Source에는 write하지
않고 session, authentication, credential key를 전달하지 않습니다.

제품 구조, 설정, 전송 계약과 Native 운영 방법은
[Redis Relay 문서](../../docs/redis-relay/index.md)를 기준으로 봅니다.

## 1. Source layout

| Module | 책임 |
|---|---|
| `settings.py` | TOML, endpoint, credential file 계약 검증 |
| `key_filter.py` | scope allow policy와 고정 deny policy |
| `replication.py` | 한 batch의 순수 복제 workflow와 결과 |
| `redis_client.py` | RESP connection, Source read, Target atomic publish adapter |
| `relay_loop.py` | 설정 reload, batch 실행, status 조립 |
| `status.py` | status schema v1과 atomic file publisher |
| `status_owner.py` | HTTP와 Unix socket status owner adapter |
| `status_publisher.py` | status publisher port, composite 결과와 실패 계약 |
| `__main__.py` | CLI와 adapter composition |

Application loop는 status의 저장 위치나 transport를 추측하지 않습니다. CLI가 File, HTTP,
Unix socket adapter를 명시적으로 조립하고, replication policy는 filesystem이나 network 상태를
읽지 않습니다.

## 2. Local development

저장소 root에서 wheel을 만들고 개발용 venv에 설치합니다.

```sh
uv build --package tirosh-vitalserver-redis-relay --wheel
uv venv .venv-redis-relay
uv pip install --python .venv-redis-relay/bin/python --no-deps \
  dist/tirosh_vitalserver_redis_relay-0.2.0-py3-none-any.whl
.venv-redis-relay/bin/vitalserver-redis-relay --help
.venv-redis-relay/bin/python -m vitalserver_redis_relay --help
```

`.venv-redis-relay`는 개발 확인용입니다. launchd와 systemd에는 사용하지 않습니다. Native
system venv와 supervisor 설치는 [운영 가이드](../../docs/redis-relay/operations.md)를 따릅니다.

## 3. Validation

```sh
uv run pytest apps/vitalserver-redis-relay/tests
uv run ruff check \
  apps/vitalserver-redis-relay/vitalserver_redis_relay \
  apps/vitalserver-redis-relay/tests
uv run mypy \
  apps/vitalserver-redis-relay/vitalserver_redis_relay \
  apps/vitalserver-redis-relay/tests
```

## 4. Documentation

| 문서 | 내용 |
|---|---|
| [Redis Relay 개요](../../docs/redis-relay/index.md) | 목적, 아키텍처, 책임 경계 |
| [설정과 보안](../../docs/redis-relay/configuration.md) | TOML, scope, credential 계약 |
| [Protocol v1](../../docs/redis-relay/protocol-v1.md) | Target key, event, consumer 책임 |
| [운영 가이드](../../docs/redis-relay/operations.md) | Native 설치, supervisor, status, 장애 판단 |
