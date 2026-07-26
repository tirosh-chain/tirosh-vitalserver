# 148 macOS Virtual Machine start가 Guest boot console 이전에 실패함

> 상태: resolved by C42 boot-loader artifact contract correction; package-install and Guest Runtime readiness proof remain separate

## 증상

entitlement를 포함한 `macos-virtual-machine-supervisor`가 C32 validation과 RAW storage
attachment 생성을 통과한 뒤, C21 `start`에 다음 C10을 반환했다.

```text
observedState=failed
issue.code=macos-vm-start-failed
issue.message=VZVirtualMachine start returned failure: Internal Virtualization error.
The virtual machine failed to start. (domain=VZErrorDomain, code=1)
```

동시에 C32 `GuestBootConsoleCapture` file의 bytes가 0이었으므로 Linux kernel,
cloud-init, Guest Product systemd, Guest Runtime이 시작됐다는 증거도 없었다.

## 확인한 경계

1. standalone ISO bootstrap attachment 오류는 C35/C34/C32의 Host RAW storage image와
   Guest ISO9660 filesystem 분리로 해소됐다.
2. `com.apple.security.virtualization=true`를 가진 ad-hoc supervisor는
   `VZVirtualMachineConfiguration.validate()`를 통과했다.
3. 기존 provider는 main thread를 semaphore로 막아 start completion을 30초 timeout으로
   만들 수 있었다. 현재 supervisor는 main run loop를 service하며 completion을 관측한다.
4. native start failure의 localized text만 남기지 않고 `NSError` domain/code도 C10 issue에
   보존한다.
5. `GuestBootConsoleCapture`는 C32의 required Host-owned append-only output이다. package
   postinstall은 C33 `installation.dataDirectory` 아래의 명시된 file만 생성한다.
6. C42가 Guest source의 gzip `/boot/vmlinuz` bytes를 그대로 boot-loader input으로
   publish했다. `VZLinuxBootLoader`가 직접 소비하는 것은 압축 download representation이
   아니라 uncompressed ARM64 Linux `Image`다. configuration validation은 이 representation
   error를 거부하지 않았고 native start에서만 `VZErrorDomain/code=1`로 실패했다.

따라서 당시 zero-byte capture와 `VZErrorDomain/code=1`은 **Guest boot 이전 native start
failure**라는 관측이었다. 이 사실만으로 image corruption, cloud-init failure,
entitlement success, 혹은 Guest readiness를 주장할 수 없었다.

## 조치 방향

2026-07-17에 C42 declaration을 `sourceCompression=gzip`,
`outputRelativePath=boot/Image`,
`outputFormat=uncompressed-linux-arm64-image`로 명시하고 extractor가 gzip을 해제하도록
교정했다. 동일한 C43 raw root, C40 bootstrap volume, C32 command line
(`console=hvc0 root=/dev/vda1`)을 사용한 ad-hoc entitlement supervisor가 C21 `running`을
반환했다. 유지된 supervisor의 Host-owned capture에는 Ubuntu `multi-user.target`,
`cloud-init.target`, `serial-getty@hvc0`, 그리고 `vitalserver-guest login:`이 기록됐다.

이는 **C42→C32 artifact compatibility와 Guest OS boot**의 local diagnostic proof다.
Apple-signed package install, Guest Runtime process readiness, Guest Runtime Control transport
reachability, C24 clean-host proof는 각각 별도의 owner와 acceptance evidence가 필요하며,
이 결과로 success로 바꾸지 않는다.

## 예방 원칙

native provider callback을 block해 synthetic timeout을 만들지 않는다. native error의
domain/code를 generic failure text로 버리지 않는다. Boot console path를 implicit log
filename으로 추정하거나 empty output을 successful boot로 변환하지 않는다. 또한 Guest
source distribution의 `/boot/vmlinuz`라는 filename을 Host boot-loader artifact role로
재사용하지 않는다. C42 declaration에는 source representation과 target consumer format을
각각 명시하고, output path는 `boot/Image`처럼 VZ가 소비하는 artifact role을 나타낸다.
