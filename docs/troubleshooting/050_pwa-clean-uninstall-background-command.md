# 050 PWA clean uninstall이 background uninstaller를 시작하지 못함

> ID: TS-050  
> Category: macOS runtime / uninstall  
> Owner: macOS runtime  
> Status: active

증상:

```text
PWA Danger Zone에서 Clean Uninstall을 눌렀지만 runtime files가 남아 있다.
Operation result 또는 command stderr에 다음과 같은 shell syntax error가 표시된다.

/bin/bash: -c: line 0: syntax error near unexpected token `;'
/bin/bash: -c: line 0: `... nohup ... < /dev/null &; echo "Background uninstaller started."'
```

또는 command result가 `Background uninstaller started.`를 보고하지만 실제 product root, LaunchDaemon, package
receipt가 남아 있고 `/private/tmp/tirosh-vitalserver-uninstall.log`에는 다음만 추가된다.

```text
nohup: can't detach from console: Inappropriate ioctl for device
```

원인:

- PWA uninstall API는 privileged shell command로 `/usr/local/bin/tirosh-vitalserver-uninstall --clean`을
  background 실행합니다.
- command builder가 shell fragments를 `; `로 join하면서 background operator 뒤에 `&;`를 만들었습니다.
- `/bin/bash`는 `&;`를 syntax error로 처리하므로 uninstaller가 시작되지 않습니다.
- `osascript do shell script ... with administrator privileges`가 실행하는 root shell에서는 `nohup` detach가
  실패할 수 있습니다. `nohup` 실패는 background job 내부에서 발생하므로 parent shell이 `echo "Background
  uninstaller started."`를 먼저 출력하면 UI/API가 실제 시작 실패를 성공처럼 표시할 수 있습니다.
- PWA API 경로는 native Swift UI uninstall 경로와 달리 Helper app 종료를 예약하지 않았습니다. background
  uninstaller가 시작되더라도 Helper app이 계속 실행 중이면 script의 `wait_for_helper_app_exit` guard에서
  abort될 수 있습니다.

진단:

```sh
tail -n 120 /private/tmp/tirosh-vitalserver-uninstall.log
python3 - <<'PY'
import json
from pathlib import Path
for path in Path("/Library/Application Support/VitalServerHelper/status").glob("runtime-events.jsonl*"):
    for line in path.read_text(errors="replace").splitlines():
        try:
            event = json.loads(line)
        except Exception:
            continue
        if "uninstall" in (event.get("operation") or "") or "uninstall" in (event.get("message") or ""):
            print(path.name, event.get("timestamp"), event.get("eventType"), event.get("message"))
PY
```

수정 방향:

- background uninstaller command must not emit `&;` and must not depend on `nohup`. Use an explicit shell block that
  starts the uninstaller in the background, records `$!`, briefly verifies that the process did not immediately exit,
  and only then reports `Background uninstaller started.`
- The uninstaller owns `/private/tmp/tirosh-vitalserver-uninstall.log`; the background handoff should not redirect the
  same process back into that log because the wrapper already uses `tee -a`.
- PWA Local API uninstall success must schedule Helper termination after the response is returned, matching the native
  uninstall path.
- The PWA operation result must surface non-zero exit code and stderr so a failed privileged command is not mistaken for
  an uninstall workflow failure.

Prevention:

- Keep command construction tests checking for invalid control operator sequences such as `&;` and for `nohup` absence.
- Treat "background command started" as an explicit host command result, not as uninstall completion. Verify artifacts
  or the HostCLI uninstall state before reporting cleanup as completed.
