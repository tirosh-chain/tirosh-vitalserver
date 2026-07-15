# Settings Apply 후 Runtime Control 인증이 401로 실패함

> ID: TS-141
> Category: Runtime Control PWA / macOS Helper UI
> Owner: macOS Runtime Control local-session client
> Status: resolved in code; package verification pending

## Symptoms

- Helper에서 설정을 변경하고 `Apply`한 뒤 Settings 화면 전체가 다음 오류만 표시합니다.

```text
platformSettings: runtime control API request failed statusCode=401
detail={"code":"unauthorized","message":"Runtime Control token is missing or invalid."}
```

- Platform Agent launchd service와 Runtime Control API는 실행 중입니다.
- Helper를 완전히 종료하고 다시 열면 설정 조회가 다시 동작할 수 있습니다.

## Impact

Apply 이후 같은 Helper process의 Platform API 읽기와 명령이 인증 실패로 막힙니다.
이 증상만으로 설정 저장 또는 VM 재시작이 실패했다고 판단할 수 없습니다. Host 설정,
VM lifecycle 및 Apply command result를 각각 확인해야 합니다. 데이터 손상이나 automation
token 손상을 의미하지 않으므로 token 또는 Host state를 삭제하면 안 됩니다.

## Cause

login-user Helper는 root-owned automation token을 읽지 않고 Platform Agent가 발급한
loopback browser-session cookie를 사용합니다. Apply가 launchd 구성을 활성화하면서
Platform Agent가 재기동되면 새 Agent process가 새 browser-session token을 소유합니다.

`RuntimeControlAPILocalSessionHTTPClient`는 최초 cookie만 process memory에 캐시했습니다.
재기동 전 cookie로 받은 `401 Unauthorized`를 그대로 반환했고 새 Agent에서 session을
다시 bootstrap하지 않았습니다.

기존 통합 테스트는 최초 login-user 연결이 automation token 없이 성공하는지만
검증했습니다. 동일 HTTP client가 Platform Agent stop/start 경계를 지나 다시 읽는
회귀 시나리오가 없어서 이 결함을 발견하지 못했습니다.

## Checks

```sh
sudo launchctl print system/ai.tirosh.vitalserver.helper.platform-agent
cat "/Library/Application Support/VitalServerHelper/runtime-control-settings.json"

curl -i -X POST \
  -H 'Origin: http://127.0.0.1:18321' \
  http://127.0.0.1:18321/platform/browser-session
```

설정에서 Runtime Control port를 변경했다면 명령의 `18321`을 명시적으로 보고된 현재
port로 바꿉니다. 정상 bootstrap은 `204`와 `Set-Cookie`를 반환합니다. root-owned
automation token 내용은 출력하거나 login-user 권한으로 읽지 않습니다.

## Actions

이전 package에서는 Helper를 완전히 종료한 뒤 다시 엽니다. 새 Helper process는 현재
Platform Agent에 새 browser session을 요청합니다. Platform Agent, token, Host SQLite,
VM disk를 삭제하지 않습니다.

수정된 package는 인증된 요청이 `401`로 거부되면 같은 loopback origin에서 session을
한 번 다시 bootstrap하고 원 요청을 한 번 재전송합니다. 인증 boundary는 handler보다
먼저 요청을 거부하므로 실패한 첫 요청에서 mutation side effect는 실행되지 않습니다.
재bootstrap 또는 재전송도 실패하면 해당 실패를 그대로 노출합니다.

Advanced의 `Recovery operations > Runtime Control connection`에서 `Reconnect Runtime
Control`을 수동으로 실행할 수도 있습니다. macOS Helper는 app을 재실행해 현재 endpoint
설정과 새 session을 함께 읽고, PWA는 console을 reload해 새 session을 요청합니다. 이
작업은 root-owned automation token을 회전하거나 VitalServer를 재시작하지 않습니다.

## Prevention

- Platform Agent를 같은 port에서 stop/start하고 동일 login-user HTTP client로 다시
  Host resource를 읽는 통합 테스트를 유지합니다.
- PWA client도 최초 요청의 `401` 뒤 session bootstrap과 원 요청을 각각 한 번만 다시
  수행하는 테스트를 유지합니다.
- session recovery는 local transport adapter만 소유하며 UI나 domain state로 만들지
  않습니다.
- `401` 이외의 transport/read/decode 실패를 session 만료로 추정하지 않습니다.
- recovery는 한 번으로 제한하고 두 번째 실패를 성공이나 빈 설정으로 변환하지 않습니다.

## Operational Notes

Settings 화면의 401은 Apply 결과와 별개의 후속 read failure입니다. Apply command의
성공 여부와 saved/applied settings revision, VM lifecycle 결과를 별도로 확인합니다.

## Related Cases

- TS-033
- TS-068
- TS-131
- TS-135

## Follow-up

- 2026-07-15: 설치본에서 fresh session `200`, stale cookie `401`을 재현하고 local-session
  client의 1회 재bootstrap 및 Platform Agent restart 통합 테스트를 추가함.
