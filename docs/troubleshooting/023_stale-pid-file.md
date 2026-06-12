# 023 `make runtime/status`가 stale pid file을 표시

> ID: TS-023  
> Category: Local development  
> Owner: macOS runtime  
> Status: archived

증상:

```text
stale pid file: .../run/vitalserver-vm.pid
```

원인:

VM process가 이미 종료되었지만 pid file이 남아 있습니다. sandbox 안에서 실행하면 `~/.tirosh` 아래 pid file 삭제가 막혀 stale이 계속 보일 수 있습니다.

조치:

일반 shell에서 다시 실행하면 stale pid file이 정리됩니다.

```sh
make runtime/status
make runtime/status
```

첫 번째 호출에서 stale을 감지하고, 두 번째 호출에서 `stopped`가 보여야 합니다.

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
