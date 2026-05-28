# 015 update 후 bootstrap이 `missing runtime package`로 실패

> ID: TS-015  
> Category: Update  
> Owner: macOS runtime  
> Status: active

증상:

```text
error: missing runtime package in air-gapped rootfs
Required commands/services: curl, docker, docker compose, avahi-daemon, growpart.
```

원인:

Product Update bundle은 `rootfs-base.raw.gz`를 포함하거나 교체하지 않고, 이미 설치되어 실행 중인 mutable disk인 `vm-disk.img`도 보존합니다. 따라서 기존 `vm-disk.img` 안에 Docker/Compose/Avahi/growpart 같은 runtime package가 빠져 있으면, guest deploy나 cloud-init seed만 갱신해도 bootstrap이 성공할 수 없습니다. VM Image/rootfs를 바꿔야 할 때는 Product Update가 아니라 `make vm-rootfs-update-bundle`로 별도 `vm-image-update` bundle을 만들지만, 이 역시 기존 `vm-disk.img`를 자동 교체하지는 않습니다.

조치:

같은 bundle을 반복 적용하지 말고, 새 package 재설치 또는 별도 VM Image replacement 흐름으로 복구합니다. 운영 데이터 보존 범위는 [Update](../macos-runtime/update.md)의 `0.1.4 update에서 다시 실패하는 경우`를 확인합니다.

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
