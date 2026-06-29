# 086 TestKit bed suffix가 Web Monitoring에서 보이지 않음

> ID: TS-086
> Category: TestKit / Upstream integration
> Owner: testkit
> Status: active

## Symptoms

VitalServer Helper의 Test 탭에서 여러 TestKit bed를 생성하고 Virtual VRecorder를 실행하면, VitalServer Web Monitoring tile title이 모두 `testkit-bed`로 표시됩니다.

TestKit API와 Helper Test 탭에는 `testkit-bed-5f83`처럼 서로 다른 generated room name이 보이지만, Web Monitoring 화면에서는 suffix가 사라져 여러 tile을 구분하기 어렵습니다.

## Impact

실시간 waveform streaming 자체는 동작하지만, 운영자가 Web Monitoring 화면에서 어떤 virtual VRecorder가 어떤 generated bed에 붙었는지 확인하기 어렵습니다. `.vital` export/upload의 파일명과 My Files 표시도 실제 room name을 기준으로 검증하므로, 화면 label과 TestKit 상태가 어긋나 보입니다.

## Cause

TestKit generated bed room name이 `prefix-xxxx` 형식이었습니다. upstream VitalServer Web Monitoring은 room title을 만들 때 마지막 hyphen suffix를 표시명에서 잘라내는 동작을 하므로, `testkit-bed-5f83`, `testkit-bed-1908`, `testkit-bed-5166`이 모두 `testkit-bed`로 보입니다.

이 표시 문제는 Host나 UI가 room name을 추정해서 고칠 수 없습니다. generated room name의 소유자는 TestKit bed identity domain이고, recorder payload와 `.vital` filename도 그 명시 이름을 그대로 써야 합니다.

## Checks

TestKit generated bed와 recorder session request를 확인합니다.

```sh
curl -s http://127.0.0.1:18082/beds
curl -s http://127.0.0.1:18082/sessions
```

`beds[].roomName`과 `sessions[].request.bedRoomNames[]`가 서로 다르지 않은데 Web Monitoring만 `testkit-bed`로 표시되면 hyphen suffix 표시 규칙에 걸린 것입니다.

## Actions

제품 수정 방향:

1. TestKit generated bed room name은 suffix 앞에 추가 hyphen을 넣지 않습니다.
2. 기본 prefix `testkit-bed`와 suffix `5f83`은 `testkit-bed5f83`으로 생성합니다.
3. TestKit API, Helper Test 탭, recorder payload `roomname`, `.vital` filename prefix가 모두 같은 explicit room name을 사용하게 유지합니다.

기존에 생성된 `testkit-bed-xxxx` bed는 reset/delete 후 새로 생성해야 Web Monitoring title이 구분됩니다.

## Prevention

Display boundary에서 room name을 재구성하지 않습니다. TestKit domain이 생성한 explicit bed room name을 outward adapters와 UI가 그대로 전달하고 표시해야 합니다.

VitalServer upstream 화면의 label heuristic과 충돌하는 문자를 generated suffix delimiter로 쓰지 않습니다.

## Related Cases

- `TS-084`: TestKit vital upload가 My Files에 표시되지 않음

## Follow-up

- 2026-06-17: `testkit-bed-xxxx` generated names가 Web Monitoring에서 모두 `testkit-bed`로 보이는 증상을 확인했습니다.
- 2026-06-17: generated bed room suffix를 `prefixxxxx` 형식으로 붙여 Web Monitoring title, TestKit status, recorder payload, `.vital` filename이 같은 explicit room name을 보도록 수정했습니다.
