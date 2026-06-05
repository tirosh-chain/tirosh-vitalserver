# 014 update 후 Redis가 `exec format error`로 실패

> ID: TS-014  
> Category: Update  
> Owner: macOS runtime  
> Status: resolved

증상:

```text
redis-1 | exec /usr/local/bin/docker-entrypoint.sh: exec format error
```

동시에 runtime status에는 아래처럼 표시될 수 있습니다.

```text
host-proxy-http-502
redis-ui-http-502
swagger-ui-http-502
guest-http-000failed
```

원인:

guest VM architecture와 Docker image architecture가 맞지 않을 때 발생합니다. 단, update bundle 내부 image가 `arm64`로 맞아 있어도 실패할 수 있습니다. update가 `guest-deploy.tar.gz`를 host shared directory에 교체하는 것만으로는 VM 내부 Docker daemon에 새 image가 load되지 않습니다. 최초 설치 때만 cloud-init bootstrap이 image bundle을 load합니다.

확인:

```sh
tail -n 200 "/Library/Application Support/TiroshVitalServer/vm/data/run/container-logs.log"
tail -n 200 "/Library/Application Support/TiroshVitalServer/vm/data/run/bootstrap.log"
cat "/Library/Application Support/TiroshVitalServer/status/runtime-status.json"
```

bundle 내부 image architecture 확인:

```sh
tar -xOf dist/update-bundles/update-bundle-<channel>-<kind>-<releaseLabel>.tar.gz \
  update-bundle-<channel>-<kind>-<releaseLabel>/guest-deploy.tar.gz | tar -xOzf - \
  deploy/docker-images/vitalserver-images.tar.gz > /tmp/vitalserver-images.tar.gz

tar -xOf /tmp/vitalserver-images.tar.gz manifest.json
```

조치:

`guest-deploy`나 Docker image bundle을 바꾸는 update는 반드시 guest activation까지 진행되어야 합니다. 현재 update bundle은 기본 migration으로 cloud-init seed를 갱신하고, 새 runtime은 `activate-update.request`를 통해 VM 안에서 Docker image bundle을 다시 load하고 기존 container를 recreate합니다. 단순히 host shared directory만 교체되면 이전 wrong-arch image cache를 계속 사용할 수 있습니다.

0.1.3에서 확인한 상세 원인은 [Update 문서의 0.1.3 실패 분석](../runtime/macos/update.md#013-실패-분석)에 남겨둡니다.

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
