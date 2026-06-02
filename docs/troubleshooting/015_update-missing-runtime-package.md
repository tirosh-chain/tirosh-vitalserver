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

또는 clean install/bootstrap log에서 아래처럼 guest-tools venv 생성이 실패합니다.

```text
The virtual environment was not created successfully because ensurepip is not available.
Failing command: /opt/tirosh/guest-tools/venv/bin/python3
```

원인:

Product Update bundle은 `rootfs-base.raw.gz`를 포함하거나 교체하지 않고, 이미 설치되어 실행 중인 mutable disk인 `vm-disk.img`도 보존합니다. 따라서 기존 `vm-disk.img` 안에 Docker/Compose/Avahi/growpart 같은 runtime package가 빠져 있으면, guest deploy나 cloud-init seed만 갱신해도 bootstrap이 성공할 수 없습니다. VM Image/rootfs를 바꿔야 할 때는 Product Update가 아니라 `make vm-rootfs-update-bundle`로 별도 `vm-image-update` bundle을 만들지만, 이 역시 기존 `vm-disk.img`를 자동 교체하지는 않습니다.

`python3 -m venv --help`가 성공해도 실제 venv 생성에 필요한 `ensurepip`가 빠져 있을 수 있습니다. Guest bootstrap prerequisite check는 command/help 존재가 아니라 실제 임시 venv 생성 가능 여부를 확인해야 합니다.

조치:

같은 bundle을 반복 적용하지 말고, 새 package 재설치 또는 별도 VM Image replacement 흐름으로 복구합니다. 운영 데이터 보존 범위는 [Update](../macos-runtime/update.md)의 `0.1.4 update에서 다시 실패하는 경우`를 확인합니다.

## Follow-up

- 2026-06-02: `python3-venv`/ensurepip 누락 rootfs에서 clean install 후 guest-tools venv 생성이 실패하는 로그를 확인했습니다. Rootfs 준비와 bootstrap preflight가 실제 `python3 -m venv` smoke check를 수행하도록 수정했습니다.
