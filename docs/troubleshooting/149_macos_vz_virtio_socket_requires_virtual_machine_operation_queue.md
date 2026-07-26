# 149 macOS VZ virtio socket connection이 Virtual Machine operation queue 밖에서 실패함

> 상태: resolved by explicit `guestRuntimeVirtualMachineOperationQueue`

## 증상

Guest가 정상 boot한 뒤 Host loopback C32 bridge가 첫 HTTP connection을 Guest
virtio socket으로 연결하려 할 때 supervisor process가 종료되고 다음 crash evidence가
남았다.

```text
dispatch_assert_queue
VZVirtioSocketDevice connectToPort
```

이 실패는 Guest Runtime HTTP, Guest SQLite, Lab 또는 Recorder 상태가 아니다. Host
macOS Virtualization adapter가 Apple framework operation을 잘못된 queue에서 호출한
provider boundary failure다.

## 원인

`VZVirtualMachine`은 그것을 생성할 때 지정한 serial queue에서만 Virtualization API를
호출해야 한다. C32 bridge의 Host-loopback accept queue가
`VZVirtioSocketDevice.connect(toPort:)`를 직접 호출하면서 framework queue assertion을
위반했다.

## 조치 방향

`MacOSVirtualMachineFactory`는 named serial
`guestRuntimeVirtualMachineOperationQueue`로 VM을 생성한다.
`GuestRuntimeControlHostLocalHTTPBridge`는 Host TCP accept를 자신의 queue에서
처리하되, VZ connection creation만 그 VM operation queue로 dispatch한다. completion으로
받은 connection은 byte-forwarding queue에 전달한다.

## 예방 원칙

Host socket accept queue와 VZ operation queue는 다른 책임이다. VZ resource가 필요한
effect는 VM operation queue에서만 실행하고, bridge queue는 VZ lifecycle/readiness를
판단하지 않는다. crash가 발생해도 bridge가 Guest boot, Guest process, 또는 HTTP
readiness 상태를 추측하지 않는다.

## 관련 경계

- `GuestRuntimeControlHostLocalHTTPBridge`
- `MacOSVirtualMachineFactory`
- C32 `MacOSVirtualMachineConfiguration`
- [macOS Virtual Machine Supervisor Boundary](../architecture/macos-virtual-machine-supervisor-boundary.md)
