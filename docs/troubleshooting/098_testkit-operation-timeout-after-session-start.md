# 098 TestKit operation timeout after session start

> ID: TS-098  
> Category: TestKit / macOS Helper UI  
> Owner: macOS runtime TestKit client  
> Status: active

## Symptoms

VitalServer Helper Test tab의 `TestKit virtual recorders` 카드에서 `Enabled`와 `Status`는 running이고 `Sessions`, `Recorders`, `Messages` 값은 증가하지만, `Operation` 행에 다음 오류가 빨간색으로 남습니다.

```text
The request timed out.
```

이 상태에서 VitalServer Web Monitoring에는 recorder 또는 waveform 전송이 이미 보일 수 있습니다.

## Impact

Virtual recorder 전송 자체는 시작됐을 수 있지만, Helper UI의 마지막 command result가 실패로 표시되어 운영자가 실제 streaming failure로 오해할 수 있습니다. 재설치나 데이터 삭제가 필요한 증상은 아닙니다.

## Cause

TestKit session start/restart command와 status/health read가 같은 short request timeout을 사용했습니다. `.vital` file source처럼 TestKit server가 파일을 열고 replay source를 준비하는 명령은 5초를 넘길 수 있습니다.

그 경우 Helper의 HTTP request는 timeout으로 실패하지만, TestKit server는 요청 처리를 계속 마치고 session을 만들 수 있습니다. 그래서 `Operation`은 timeout을 표시하고, `Sessions`, `Recorders`, `Messages`는 증가하는 상반된 화면이 됩니다.

## Checks

Helper 화면에서 다음 값을 함께 봅니다.

```text
Operation: The request timed out.
Sessions: 1 이상
Recorders: 1 이상
Messages: 증가
Target: http://edge/
```

TestKit container health와 session API도 확인합니다.

```sh
docker compose ps testkit
docker compose logs --tail=200 testkit
curl -fsS http://<testkit-api-host>:18322/sessions
```

## Actions

1. `Sessions`, `Recorders`, `Messages`가 증가하면 streaming은 진행 중인 것으로 보고 Web Monitoring에서 recorder 상태를 별도로 확인합니다.
2. `.vital` file source start/restart가 반복 timeout을 보이면, long-running command timeout이 포함된 Helper/runtime 버전으로 업데이트합니다.
3. `Sessions`가 생성되지 않고 `Messages`도 0이면 timeout이 아니라 TestKit API, file mount, source path unavailable 문제를 함께 확인합니다.

## Prevention

TestKit API client는 request timeout을 `standard`와 `longRunningCommand`로 분리합니다. Health/status read는 짧게 실패하고, session start/restart 및 large file upload command는 explicit long-running timeout을 사용합니다.

## Operational Notes

`Operation` 행은 마지막 Helper command result입니다. TestKit session state, recorder count, message count와 같은 runtime state를 대체하지 않습니다. 서로 다른 상태 소유자가 제공한 값이므로, 하나를 다른 하나의 fallback으로 보정하지 않습니다.

## Related Cases

- `TS-084`: TestKit vital upload가 My Files에 표시되지 않음
- `TS-096`: TestKit vital playback file unavailable

## Follow-up

- 2026-07-01: `.vital` playback start 후 messages는 증가하지만 Helper `Operation`에 timeout이 남는 증상을 확인했습니다.
