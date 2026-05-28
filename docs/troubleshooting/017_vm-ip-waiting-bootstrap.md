# 017 VM은 부팅됐지만 VM IP가 계속 Waiting

> ID: TS-017  
> Category: Runtime health  
> Owner: macOS runtime  
> Status: active

증상:

Helper Status에서 VM service와 watchdog은 running인데 VM IP, VitalServer, Redis가 계속 Waiting으로 표시됩니다.

확인:

```sh
tail -n 200 "/Library/Application Support/TiroshVitalServer/vm/logs/launchd.out.log"
tail -n 200 "/Library/Application Support/TiroshVitalServer/vm/logs/launchd.err.log"
cat "/Library/Application Support/TiroshVitalServer/vm/data/run/bootstrap.log"
cat "/Library/Application Support/TiroshVitalServer/vm/data/run/runtime-state.json"
```

원인:

VM 자체는 부팅됐지만 guest bootstrap이 실패하면 `runtime-state.json`이 생성되지 않습니다. 이 경우 UI는 VM IP를 알 수 없어 Waiting으로 남습니다. 한 사례에서는 bootstrap preflight가 arm64 VM에서 `qemu-x86_64-static`을 필수로 요구해 실패했습니다. 현재 container image는 `linux/arm64`로 제공하므로 qemu-user-static은 runtime 필수 조건이 아닙니다.

조치:

수정된 `bootstrap.sh`가 들어간 update bundle을 다시 만들고 적용합니다. 해당 변경은 `guest-deploy.tar.gz`에 포함되며, 기본 migration과 guest activation 경로를 통해 현장 runtime에 반영됩니다.

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
