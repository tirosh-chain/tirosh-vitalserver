# 003 bridged mode가 `Killed: 9`로 종료됨

> ID: TS-003  
> Category: Network  
> Owner: macOS runtime  
> Status: archived

증상:

```text
VITALSERVER_VM_HOME=... vitalserver-vm network bridged "en0"
make: *** [vm-network-bridged] Killed: 9
```

원인:

`com.apple.vm.networking` entitlement가 들어간 바이너리를 ad-hoc signing으로 실행하면 macOS가 프로세스를 시작 직후 종료할 수 있습니다. 이 entitlement는 shared/NAT boot smoke test용 `com.apple.security.virtualization`보다 더 제한적입니다.

확인:

```sh
security find-identity -v -p codesigning
codesign -d --entitlements - apps/vitalserver-macos-runtime/.build/release/vitalserver-vm
```

현재 개발 PC에 유효한 codesign identity가 없으면 bridged mode까지 진행할 수 없습니다.

조치:

```sh
VM_BRIDGED_CODESIGN_IDENTITY="Developer ID Application: ..." \
VM_BRIDGED_INTERFACE=en0 \
make vm-up-bridged
```

`make vm-bridged-preflight`는 이 조건을 먼저 확인합니다. codesign identity가 없는 환경에서는 `Killed: 9` 대신 설명 가능한 오류로 중단합니다.

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
