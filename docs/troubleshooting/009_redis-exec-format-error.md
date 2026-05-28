# 009 Redis가 `exec format error`를 출력함

> ID: TS-009  
> Category: Guest containers  
> Owner: macOS runtime  
> Status: resolved

증상:

```text
redis-1 | exec /usr/local/bin/docker-entrypoint.sh: exec format error
```

원인:

guest VM은 arm64 Ubuntu인데 Docker image bundle이나 compose 설정이 amd64 image를 강제로 사용하면 container entrypoint를 실행하지 못합니다. 이 경우 Redis뿐 아니라 다른 container도 같은 방식으로 실패할 수 있습니다.

조치:

- Docker image bundle은 `linux/arm64`로 생성합니다.
- Compose에서 특정 service에 `platform: linux/amd64`를 강제하지 않습니다.
- Redis Commander처럼 운영 UI container도 `latest` 대신 pinned multi-arch image를 사용합니다.

현재 기준:

```text
docker image platform: linux/arm64
Redis Commander: ghcr.io/joeferner/redis-commander:0.9.0
```

이미 잘못된 bundle을 적용했다면 수정된 bundle을 다시 적용하거나 runtime을 재설치한 뒤 health를 확인합니다.

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
