# 022 설치된 runtime binary에 virtualization entitlement가 없음

> ID: TS-022  
> Category: Packaging  
> Owner: macOS runtime  
> Status: resolved

증상:

```text
Runtime state: critical
VM IP: Waiting
Guest HTTP: missing-vm-ip
Host proxy: failed
```

launchd log에는 아래 오류가 남습니다.

```text
The process doesn't have the "com.apple.security.virtualization" entitlement.
Invalid virtual machine configuration.
```

원인:

패키징 중 `vm-golden-rootfs` 준비 과정이 Swift binary를 다시 빌드하면, 앞에서 signing했던 `vitalserver-vm`이 unsigned binary로 덮일 수 있습니다. 이 상태로 `.pkg`에 들어가면 설치된 `/usr/local/bin/vitalserver-vm`이 VM을 띄우지 못하고, guest가 부팅되지 않으므로 runtime state에 VM IP가 기록되지 않습니다.

확인:

```sh
codesign -d --entitlements :- /usr/local/bin/vitalserver-vm 2>&1 | grep com.apple.security.virtualization
sudo launchctl print system/com.tirosh.vitalserver-vm
cat "/Library/Application Support/TiroshVitalServer/vm/logs/launcher.err.log"
```

조치:

`make dist/pkg/dev`는 package root에 binary를 복사하기 직전에 다시 signing하고 entitlement를 검증합니다. 기존에 설치된 잘못된 package는 다시 빌드한 package로 재설치해야 합니다.

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
