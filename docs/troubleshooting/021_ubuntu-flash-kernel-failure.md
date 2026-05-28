# 021 Ubuntu arm64 cloud image에서 `flash-kernel`이 실패

> ID: TS-021  
> Category: Guest bootstrap  
> Owner: macOS runtime  
> Status: resolved

증상:

```text
Unsupported platform ''.
dpkg: error processing package flash-kernel (--configure)
E: Sub-process /usr/bin/dpkg returned an error code (1)
```

원인:

Ubuntu arm64 cloud image에는 `flash-kernel`이 포함될 수 있습니다. 하지만 이 VM은 Apple Virtualization launcher가 macOS에서 kernel/initrd를 직접 지정해 부팅하므로 guest 안의 `flash-kernel`이 필요하지 않습니다. 해당 hook이 실행되면 현재 VM platform을 인식하지 못하고 apt/dpkg 흐름을 막을 수 있습니다.

조치:

guest `bootstrap.sh`에서 `flash-kernel` hook을 비활성화하고 `flash-kernel` 패키지를 제거한 뒤 `dpkg --configure -a`로 package state를 복구합니다.

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
