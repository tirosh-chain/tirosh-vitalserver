# Helper가 Host SQLite를 직접 열어 전체 runtime 상태가 unavailable로 표시됨

> ID: TS-135
> Category: Runtime health / macOS Helper UI / Host state persistence
> Owner: macOS runtime
> Status: resolved in code; package verification pending

## Symptoms

- Host services와 VM이 실행 중인데 Helper Status는 `VM state Unknown`, `VM IP Waiting`, `Runtime product services unavailable`로 표시됩니다.
- Settings에 다음 오류가 반복됩니다.

```text
Host settings SQLite read failed path=/Library/Application Support/VitalServerHelper/vm/runtime/runtime-state.sqlite
reason=unable to open database file
```

- Lab은 `Runtime endpoint SQLite read failed` 또는 `Host runtime state database open failed`로 unavailable입니다.
- 데이터 디렉터리에 실제 설치 설정이 아닌 `/Users/Shared/VitalServerHelper/vital-files`가 표시될 수 있습니다.
- root Platform Agent와 proxy launchd service는 실행 중이고 SQLite 파일은 `root:wheel 0600`입니다.

## Impact

일반 사용자로 실행되는 Control Panel이 Host 상태와 설정을 읽지 못합니다. UI는 제어 기능을 비활성화하고 실제로 실행 중인 VM을 Unknown으로 표시할 수 있습니다. SQLite 자체가 손상된 증거는 아니며, 이 문제만으로 database 권한을 넓히거나 VM을 재설치하면 안 됩니다.

## Cause

Host 상태를 JSON에서 SQLite로 전환한 composition 변경이 Control Panel에도 SQLite repository를 직접 주입했습니다. 설치된 database는 의도대로 secret-bearing Host 설정을 보호하기 위해 `root:wheel 0600`이므로 login-user Helper의 open은 실패합니다.

동시에 두 cutover가 완결되지 않았습니다.

1. Platform Agent API는 owner state를 제공했지만 Control Panel은 해당 API 대신 database를 직접 열었습니다.
2. proxy script가 계속 `runtime-endpoint.json`을 만들고 Platform Agent는 SQLite endpoint를 갱신하지 않았습니다.

설정 API 실패는 `RuntimeSettings` 초기 preset과 함께 전달되어, presentation이 `/Users/Shared/...` 기본값을 실제 상태처럼 사용했습니다. Compile은 각 Swift target의 type correctness와 일부 repository 테스트만 검증했고, root owner와 login-user consumer를 분리한 설치 권한 통합 경계를 실행하지 않아 이 문제를 잡지 못했습니다.

## Checks

```sh
ls -l "/Library/Application Support/VitalServerHelper/vm/runtime/runtime-state.sqlite"
sudo launchctl print system/ai.tirosh.vitalserver.platform-agent
curl -i -X POST -H 'Origin: http://127.0.0.1:18321' \
  http://127.0.0.1:18321/platform/browser-session
```

Database가 `root:wheel` mode `0600`인 것은 정상입니다. mode를 `0644`나 `0660`으로 바꾸는 것은 수정이 아닙니다.

## Actions

수정된 package/update를 설치합니다. 수정본은 다음 경계를 사용합니다.

1. root Platform Agent만 Host SQLite repository를 구성합니다.
2. Control Panel은 loopback browser session으로 `/platform`, `/platform/settings`, operation/endpoint resources를 읽습니다.
3. `Set-Cookie` 응답을 네이티브 client가 명시적으로 보존하여 후속 API 요청에 전달합니다.
4. Platform Agent가 `vm-ip` bootstrap evidence를 검증하고 현재 VM lifecycle run에 묶어 SQLite endpoint를 갱신합니다.
5. proxy는 nginx route만 구성하고 legacy `runtime-endpoint.json`을 만들지 않습니다.
6. settings owner read가 실패하면 form preset을 숨기고 실패 상태만 표시합니다.

## Prevention

- Architecture test는 Control Panel composition의 SQLite repository 생성을 금지합니다.
- Packaging test는 production template의 `runtime-endpoint.json` reader/writer를 금지합니다.
- Platform Agent service test는 root-owned SQLite를 login-user loopback session으로 읽고 automation token이 노출되지 않음을 검증합니다.
- Platform state API adapter test는 Settings 입력이 상태를 재구성하지 않음을 검증합니다.
- 설치 permission test는 SQLite/token `0600`과 non-secret Runtime Control endpoint settings `0644`를 구분합니다.
- Compile 성공을 설치 권한/다중 프로세스 통합 성공으로 해석하지 않습니다. DMG/PKG 검증에는 실제 root Platform Agent와 login-user Helper 경계를 포함해야 합니다.

## Operational Notes

기존 설치본에서 진단 목적으로 database를 복사해야 한다면 root 권한으로 별도 안전 경로에 복사하고 원본 mode를 유지합니다. Control Panel을 root로 실행하거나 database owner/mode를 변경하지 않습니다.

## Related Cases

- TS-100
- TS-102
- TS-110
- TS-127
- TS-132
- TS-134

## Follow-up

- 2026-07-15: SQLite owner/API consumer 경계, endpoint cutover, loopback cookie 전달 및 presentation failure state를 코드에서 수정함. DMG/PKG 설치 검증 대기.
