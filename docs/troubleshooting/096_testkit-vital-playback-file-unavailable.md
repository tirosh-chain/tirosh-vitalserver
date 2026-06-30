# 096 TestKit vital playback file unavailable

> ID: TS-096
> Category: TestKit / macOS runtime
> Owner: vitalserver-testkit
> Status: active

## Symptoms

VitalServer Helper의 Test 탭에서 `.vital` 파일을 선택해 Virtual VRecorder playback을 시작하면 TestKit operation에 다음과 같은 오류가 표시됩니다.

```text
{"detail":"real vital file is unavailable: /mnt/tirosh-vital-files/.../case.vital"}
```

TestKit service 자체는 running이고, VitalServer의 file storage나 My Files upload 경로는 정상으로 보일 수 있습니다.

## Impact

Virtual VRecorder session이 시작되지 않습니다. 운영자는 host의 configured `Vital files directory` 아래 파일을 선택했기 때문에 파일이 존재한다고 판단하지만, TestKit container는 별도 filesystem namespace에서 실행되므로 container bind가 빠져 있으면 같은 path를 읽을 수 없습니다.

## Cause

macOS Host의 `Vital files directory`는 Linux guest에 virtiofs share로 mount되고, Docker Compose service는 필요한 container에 다시 bind mount해야 합니다.

`app` service만 `${VITALSERVER_VITAL_FILES_DIR:-/mnt/tirosh-vital-files}`를 bind mount하고 `testkit` service가 같은 source를 mount하지 않으면, VitalServer app은 `.vital` storage를 볼 수 있지만 TestKit replay reader는 `/mnt/tirosh-vital-files/...` 파일을 볼 수 없습니다.

Helper UI의 path 변환만으로는 이 문제를 해결할 수 없습니다. Host path `/Users/Shared/VitalServerHelper/vital-files/...`는 guest-readable path `/mnt/tirosh-vital-files/...`로 변환되어야 하고, 그 guest path는 TestKit container 안에도 bind mount되어야 합니다.

## Checks

guest에서 vital files share가 mount되어 있는지 확인합니다.

```sh
mountpoint -q /mnt/tirosh-vital-files
ls -la /mnt/tirosh-vital-files
```

TestKit container 안에서 같은 파일이 보이는지 확인합니다.

```sh
docker compose --project-name tirosh-vitalserver \
  -f /mnt/tirosh/deploy/compose.yaml \
  exec testkit ls -la /mnt/tirosh-vital-files
```

Compose service에 bind가 있는지도 확인합니다.

```sh
docker compose --project-name tirosh-vitalserver \
  -f /mnt/tirosh/deploy/compose.yaml \
  config | grep -A8 -n 'testkit:'
```

정상 구성에서는 `testkit` service volumes에 다음 bind가 있어야 합니다.

```yaml
- type: bind
  source: ${VITALSERVER_VITAL_FILES_DIR:-/mnt/tirosh-vital-files}
  target: /mnt/tirosh-vital-files
  read_only: true
```

## Actions

제품 수정 방향:

1. `testkit` compose service에 `${VITALSERVER_VITAL_FILES_DIR:-/mnt/tirosh-vital-files}`를 `/mnt/tirosh-vital-files`로 read-only bind mount합니다.
2. Helper Test 탭의 `.vital` playback picker는 configured `Vital files directory`를 시작 위치로 엽니다.
3. Helper는 선택된 host path를 `/mnt/tirosh-vital-files/...` guest path로 변환해 TestKit API에 전달합니다.
4. 선택 파일이 configured `Vital files directory` 밖이면 session 시작 전에 UI에서 명시적으로 차단합니다.
5. TestKit reader는 파일 없음과 read failure를 internal server error가 아니라 explicit unavailable failure로 보고합니다.

기존 runtime에 이미 compose가 배포되어 있으면, 수정된 compose를 포함한 Helper/runtime bundle로 업데이트한 뒤 TestKit service를 restart해야 합니다.

## Prevention

Host path, guest mount path, container bind path를 같은 상태로 취급하지 않습니다.

`.vital` playback source path는 TestKit container가 읽을 수 있는 explicit path여야 합니다. UI는 host path를 표시할 수 있지만, application/request boundary에는 guest-readable path를 전달해야 합니다. Compose tests는 `app`과 `testkit` service가 같은 vital files bind source를 사용하는지 검증해야 합니다.

## Related Cases

- `TS-084`: TestKit vital upload가 My Files에 표시되지 않음
- `TS-086`: TestKit bed suffix가 Web Monitoring에서 보이지 않음

## Follow-up

- 2026-07-01: `.vital` playback start 시 TestKit operation에 `real vital file is unavailable: /mnt/tirosh-vital-files/...`가 표시되는 증상을 확인했습니다.
- 2026-07-01: Helper path 변환은 `/mnt/tirosh-vital-files/...`로 정상 동작했지만, `testkit` compose service에 vital files bind가 없어 container 안에서 파일을 읽을 수 없음을 확인했습니다.
