# Host/Guest Control Slice

> 상태: **Implemented and executable-acceptance verified**
>
> 이 문서는 `runtime-platform/`의 Host/Guest control 경계와, 아직 보장하지 않는 delivery proof를 분리한다. 제품 전체의 설계는 [vNext 설계 초안](vnext-runtime-platform-design.md), 다음 작업 순서는 [vNext 구현 계획](vnext-implementation-plan.md)을 따른다.

## 1. 이 slice가 만든 최소 경계

```text
operator / client
        |
        v
Host Agent public facade
  |-- Host SQLite: installation, GuestRuntimeControlEndpoint, Host Operation
  |-- C33 Host deployment configuration --> C32 macOS supervisor input --> Apple Virtualization effect
  '-- allowlisted HTTP --> Guest Runtime public API
                                 '-- Guest SQLite: RuntimeTopology, Guest Operation
```

- Host Agent와 Guest Runtime은 서로의 SQLite file, table, process, filesystem을 읽지 않는다.
- `/v1/platform/*`은 Host Agent가 직접 owner다.
- allowlisted `/v1/runtime/*`은 Host Agent가 Guest Runtime의 HTTP response를 decode·조립·대체하지 않고 그대로 전달한다.
- `GuestRuntimeControlEndpoint.provider`는 Platform Provider의 관측이고, `GuestRuntimeControlEndpoint.transport`는 별도 Guest Runtime Control HTTP probe의 관측이다. 하나가 다른 하나를 성공 또는 실패로 만들지 않는다.

## 2. 계약과 owner

| 계약 | owner | 의미 |
| --- | --- | --- |
| C7 `PlatformInstallation` | Host Agent | 설치 release, Host data directory라는 Host-owned resource |
| C8 `GuestRuntimeControlEndpoint` | Host Agent | configured Runtime Control HTTP target과 Platform Provider/transport 관측을 분리한 Host resource |
| C9 `GuestLifecycleCommand` | Host Agent | start/stop/reboot command와 optimistic revision guard |
| C10 `ProviderLifecycleRequest` / `ProviderLifecycleResult` | macOS provider | OS/VM effect request와 실제 관측 결과 |
| C32 `MacOSVirtualMachineConfiguration` | Host deployment configuration | Guest kernel·initrd·disk·CPU/memory·NAT MAC을 빠짐없이 선언하는 macOS virtual machine supervisor input |
| C33 `HostAgentDeploymentConfiguration` | Host deployment configuration | Host Agent listen/SQLite/data, configured Guest Runtime Control endpoint, selected provider, time/telemetry/update mode을 빠짐없이 선언하는 service input |
| C11 `FacadeForwardingFailure` | Host Agent | Guest command을 전송 시도한 뒤 delivery 존재 여부를 알 수 없는 결과 |
| C12 `CommandAdmissionFailure` | Host Agent 또는 Guest Runtime | durable command admission 자체가 불명확한 결과 |

`CommandRejection`은 command가 **admit되지 않았고 Operation이 없음**을 의미한다. 반면 C12의 `admissionState=unknown`은 operation이 생겼는지 단정할 수 없으므로, recovery 후 **같은 `requestId`**로만 재시도해야 한다.

## 3. Host lifecycle의 명시적 흐름

| 단계 | Host가 기록/관측하는 사실 | 다음 단계로 넘길 수 있는 조건 |
| --- | --- | --- |
| command validation | input, Guest Runtime Control endpoint ID, expected resource revision | input/revision이 명시적으로 유효함 |
| admission | `requested → accepted → running`으로 전이한 Host `Operation`을 SQLite에 먼저 저장 | durable `running` operation이 존재함 |
| provider effect | C10 request를 selected Platform Provider process에 전달하고 C10 result를 받음 | result가 contract-valid임 |
| outcome commit | endpoint provider observation과 terminal operation을 한 transaction으로 저장 | transaction commit 성공 |
| recovery | terminal outcome commit이 실패하면 기존 `running` operation을 반환 | success/failed로 위장하지 않음 |

따라서 provider effect 뒤 outcome commit이 실패하면 caller는 `202`와 `running` operation을 받는다. 같은 request ID를 재시도해 provider effect를 다시 실행하지 않으며, 후속 recovery workflow가 terminal result를 다시 관측·기록할 때까지 `running`은 그대로 남는다. 이 slice에는 그 recovery reconciler를 아직 넣지 않았다.

`GuestRuntimeControlEndpoint.resourceRevision`은 Platform Provider observation과 Host Runtime Control transport observation이 공유하는 Host-owned revision이다. Host Agent는 endpoint를 바꾸는 lifecycle effect, read probe, forwarded command probe를 한 process-local workflow mutex로 serialize한다. 따라서 같은 Host process에서 stale revision을 읽은 두 lifecycle command가 provider effect를 중복 실행하지 않는다. 다중 Host Agent writer profile은 지원하지 않으며, service registration/single-instance delivery proof는 cross-platform delivery work에서 추가한다.

Guest Runtime도 singleton `RuntimeTopology` command admission을 owner process 안에서 serialize한다. 이로써 simultaneous same-request retry가 새 operation을 만들거나 stale revision이 operation을 덮어쓰지 않는다. Guest SQLite transaction은 commit 직전에 topology revision을 다시 확인한다.

Provider 관측은 다음처럼 해석한다.

| provider result | Host transport에 대해 말할 수 있는 것 |
| --- | --- |
| `running`, `starting`, `stopping` | transport는 `not-checked`; 명시 probe 전에는 reachability를 주장하지 않음 |
| `stopped` | transport `unavailable`; Host는 Guest로 forward하지 않음 |
| `unavailable` | transport `unavailable`; Host는 Guest로 forward하지 않음 |
| `failed` | provider effect 실패만 기록; 기존 transport state를 실패로 추정하지 않음 |

## 4. Guest facade와 forwarding 결과

1. Host는 provider가 `stopped` 또는 `unavailable`이라고 **이미 명시적으로** 관측했으면 Guest HTTP 요청을 보내지 않고 `ReadResult.state=unavailable` 또는 pre-admission `CommandRejection`을 반환한다.
2. 그 외에는 Guest readiness endpoint를 명시적으로 probe한다. probe success만 Host transport `reachable`로 기록한다.
3. Guest read 또는 command response가 정상적으로 도착하면 body와 status를 변경하지 않고 전달한다.
4. command forwarding을 실제로 시도한 뒤 응답을 받지 못하면 `FacadeForwardingFailure`와 `deliveryDisposition=unknown`을 반환한다. Guest operation이 생겼는지 추정하지 않는다.

## 5. 현재 실행 증거

`make -C runtime-platform check`은 real Guest Runtime application composition을
`guest-runtime-control-http-acceptance-fixture`라는 명시적 test-only TCP/HTTP
entry point로 기동하고, real Host Agent HTTP facade와 각각의 temporary SQLite
database를 함께 기동한다. fixture는 public HTTP contract와 application state owner를
검증하기 위한 것이며 Linux Guest AF_VSOCK listener 또는 C32 Host-local bridge를
대체하거나 성공으로 주장하지 않는다. 그 transport proof는 production
`guest-runtime`과 macOS virtual-machine smoke의 별도 책임이다. acceptance provider는
이 test에서만 `running`/`stopped` result를 결정적으로 제공한다.

검증하는 사실은 다음과 같다.

- start 후 provider `running`과 transport `not-checked`를 분리한다.
- facade read가 Guest response를 그대로 전달하고, 그 뒤에만 transport `reachable`을 기록한다.
- Host provider가 `stopped`이면 살아 있는 test Guest process에도 forward하지 않는다.
- topology는 Guest SQLite에만 저장되고, upstream adapter 부재를 `unsupported`/`not-checked`로 보존한다.
- malformed Guest command는 operation 없이 reject된다.
- Guest topology atomic commit의 outcome이 불명확하면 direct Guest API도 typed `CommandAdmissionFailure`를 반환한다.
- Host lifecycle admission write failure는 provider effect 전에 typed `CommandAdmissionFailure`를 반환한다.
- terminal outcome write failure는 durable `running` Host operation을 남기고 provider effect를 같은 request ID로 재실행하지 않는다.

macOS provider source는 별도로 `make -C runtime-platform macos-provider-test`로 build/test한다. product Host Agent는 `--deployment-configuration`으로 C33 하나만 읽는다. C33는 C32 path를 long-lived macOS virtual machine supervisor로 전달하고, supervisor는 C32에 없는 VM asset·MAC·network mode를 추측하지 않는다. C33이 없거나 invalid이면 Host process는 시작하지 않으며, C32 path가 없으면 macOS C33 자체가 invalid이다.

## 6. 아직 증명하지 않는 것

- signed package 안의 configured `VZVirtualMachine` networking, Guest Runtime Control reachability, reboot completion
- signed PKG/DMG clean install, Host reboot, update/rollback, clean uninstall/reinstall
- PWA product UI, Recorder Gateway, upstream connection/delivery, Lab, archive, NTP, telemetry
- `running` Host operation의 crash/restart recovery reconciler

이 항목은 숨은 fallback으로 채우지 않는다. VM image/installer proof와 OS lifecycle runner는 cross-platform delivery의 release gate이며, upstream·Recorder·Lab·NTP·telemetry는 각각의 owner와 receipt contract가 생긴 뒤 구현한다.
