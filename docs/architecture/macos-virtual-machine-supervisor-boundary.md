# macOS Virtual Machine Supervisor Boundary

## 발견한 문제

Apple `VZVirtualMachine`은 그것을 생성한 macOS process가 살아 있는 동안에만
Guest VM을 소유한다. 현재 `macos-virtual-machine-command-cli`는 C21 하나를 stdin으로 받아
C10 하나를 stdout으로 반환하는 **일회성 invocation CLI**다. 이 CLI가 `start`의
completion을 받더라도 process가 종료되면 `VZVirtualMachine`의 owner도 사라진다.

따라서 일회성 CLI는 macOS Virtualization API mapping unit test에는 유효하지만,
실제 설치 제품에서 Guest VM lifecycle provider가 될 수 없다. Windows Hyper-V와
Linux libvirt는 native hypervisor/service가 caller process 밖에서 VM을 유지하므로
같은 one-shot bridge 모양을 쓸 수 있지만, macOS `VZVirtualMachine`에는 적용되지
않는다.

## 올바른 owner와 전달 방향

macOS에는 long-lived `MacOSVirtualMachineSupervisor` process가 필요하다.

```text
C33 HostAgentDeploymentConfiguration
  → Host Agent (Host SQLite: C2/C7/C8/C29 owner)
  → retained Supervisor process client (C21 invocation)
  → MacOSVirtualMachineSupervisor (VZVirtualMachine owner)
  → C10 ProviderLifecycleResult

C33 provider deployment
  → MacOSVirtualMachineSupervisor executable + C32 path
  → VZVirtualMachine resource realization
```

`MacOSVirtualMachineSupervisor`는 다음을 소유한다.

- C32를 한번 검증하여 만든 `VZVirtualMachine`의 process-lifetime reference
- local-only lifecycle listener와 C21/C10 codec
- VZ start/stop/reboot effect와 native observed state
- C32 `GuestBootConsoleCapture`가 명시한 append-only Host diagnostic file handle과
  `hvc0` serial output attachment
- C32 `GuestRuntimeDiskProvisioning`이 선언한 immutable
  `GuestRootStorageReleaseArtifact`를 검증한 뒤, Host-owned
  `GuestRuntimeDiskWorkspace`에 최초 writable disk를 provision하는 effect

`GuestRuntimeDiskProvisioner`는 VM factory보다 먼저 실행되는 Supervisor의 명시적
effect adapter다. C34 digest와 artifact-set identity가 맞는 release artifact만
읽고, release artifact digest를 포함한 provisioning receipt와 함께 runtime disk를
atomic publish한다. 이후 receipt가 같은 release artifact를 가리킬 때만 existing
runtime disk를 retain한다. 따라서 C32의 `storageDevices[guest-root].diskImagePath`는
VM이 실제로 write할 workspace path이며, package payload의 `release/guest-root.raw`는
attach 대상도, mutable state도 아니다.
- C32 `LinuxBootResources.guestRootDevicePath`와 matching `root=` kernel argument가
  C43의 Guest-visible MBR root partition을 명시적으로 전달하는지 검증
- C32 `GuestRuntimeControlHostLocalHTTPBridge`의 Host-loopback listener와
  VZ virtio-socket byte relay. 이 adapter는 Host local TCP accept와 Guest
  `AF_VSOCK` port 연결만 수행하며, HTTP request/response를 해석하거나 Guest
  readiness를 판단하지 않는다.

`VZVirtualMachine`이 만든 Apple Virtualization object에는 **하나의 명시적
serial operation queue**를 사용한다. `connect(toPort:)`도 그 queue에서만
호출하고, completion으로 받은 `VZVirtioSocketConnection`은 별도의 bridge
queue에 전달해 byte relay만 한다. Host listener queue에서 VZ API를 직접
호출하면 Apple framework queue assertion으로 process가 종료될 수 있다.

VZ socket file descriptor와 accepted Host socket은 nonblocking일 수 있다.
따라서 `GuestRuntimeControlHostLocalHTTPBridgeByteRelaySocketResultPolicy`는
`EAGAIN`/`EWOULDBLOCK`/`EINTR`를 established connection의 **waiting** 결과로
분류한다. 이 결과는 relay를 닫거나 lifecycle/readiness state를 변경하지 않는다.
EOF 또는 terminal socket error만 해당 accepted connection을 닫는다.

Host Agent는 다음을 계속 소유한다.

- request ID/endpoint revision idempotency와 C2 operation
- C8 endpoint observation, Guest transport probe, public Host API
- C33 deployment input과 lifecycle command admission

Supervisor는 Host operation SQLite, Guest Runtime state, Lab/Recorder state를 소유하지
않는다. Host Agent도 VZ object를 직접 만들거나 supervisor가 살아 있는지 process
목록으로 추측하지 않는다. local supervisor endpoint가 없으면 C10 `unavailable`이
명시적으로 반환되어야 한다.

`GuestBootConsoleCapture`는 Guest state와 구별된다. C32가 capture path와
`writeMode=append`를 명시하고, package postinstall은 C33 `dataDirectory` 아래의 그
파일과 필요한 Host directory만 생성한다. postinstall은 `GuestRuntimeDiskWorkspace`나
receipt를 생성·복사·overwrite하지 않는다. Supervisor는 start failure가 발생해도 console이 비어 있다는 사실을
boot success, Guest failure, 또는 cloud-init failure로 해석하지 않는다. native start
failure의 domain/code와 console bytes는 다음 diagnostic owner에게 전달할 evidence다.

## 필요한 deployment contracts

현재 C33의 macOS provider 부분은 supervisor executable path와 C32 path를 명시한다.
Host Agent는 그 child process를 한 번 시작한 뒤 retained standard-input/standard-output
transport로 C21/C10을 교환한다. 이 transport는 Host Agent process lifetime에 묶이며,
별도 endpoint나 hidden launchd service를 추측하지 않는다.

macOS PKG composer는 C33/C32/C34와 두 executable(Host Agent, supervisor)을
같은 Host Agent launchd payload로 materialize해야 한다. Host Agent service를 bootstrap했다고
Guest VM이 start됐다는 뜻은 아니다. Guest start는 여전히 C9 command → Host admission
→ C21 supervisor invocation의 별도 effect다.

PKG의 postinstall은 Host Agent service registration의 owner다. 기존 service가 있는
update/reinstall에서는 먼저 정확한 `system/<launchd label>`만 bootout한 뒤 새 plist를
bootstrap한다. launchd가 명시적으로 반환하는 exit `3` (`No such process`)만 clean
install의 *등록되지 않음* 상태로 허용한다. 다른 bootout 실패는 bootstrap으로 숨기지
않고 installer failure로 남긴다. 이 규칙은 Guest lifecycle state를 추측하거나 C9
start command를 packaging layer가 만들도록 허용하지 않는다.

## 현재 상태와 전환 기준

현재 구현된 `macos-virtual-machine-command-cli`는 C32 decoding과 VZ API mapping을 검증하는
**invocation test adapter**로만 취급한다. Host Agent macOS composition은
`macos-virtual-machine-supervisor` child process를 한 번 시작하고 retained C21/C10
transport로 사용하며, PKG composer/verifier도 그 executable path를 검증한다. 그래도
실제 release PKG의 C24 install/boot evidence는 아직 없다.

전환이 완료되려면 다음이 모두 필요하다.

1. long-lived supervisor executable와 retained lifecycle transport가 실제 C21/C10을
   처리한다. ✓
2. Host Agent macOS adapter가 one-shot subprocess runner가 아니라 retained supervisor client를 사용한다. ✓
3. C33가 supervisor executable과 C32 path를 explicit deployment input으로 제공한다. ✓
4. PKG composer/verifier가 supervisor binary와 C33/C32/C34 payload correspondence를 검증한다. ✓
5. clean Host에서 C9 start 후 supervisor가 계속 살아 있고 Guest transport가 reachable인
   evidence를 C24에 기록한다.

그 전까지 macOS package composer는 payload correspondence를 검증하는 build adapter일
뿐, bootable installed product의 proof가 아니다.
