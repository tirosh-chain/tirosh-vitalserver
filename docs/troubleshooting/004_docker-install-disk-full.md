# 004 `docker.io` 설치 중 `No space left on device`

> ID: TS-004  
> Category: Guest bootstrap  
> Owner: macOS runtime  
> Status: resolved

증상:

```text
cannot copy extracted data ... failed to write (No space left on device)
```

원인:

Ubuntu cloud image의 기본 root disk는 Docker, Compose, nginx, guest systemd unit, VitalServer image 준비까지 수행하기에 작습니다.

조치:

`make vm-download`는 VM disk를 기본 `8G`(8 GiB)로 확장합니다. 더 크게 만들려면:

```sh
VM_ROOTFS_SIZE=32G make vm-download
```

`VM_ROOTFS_SIZE`의 `G` suffix는 build tool 입력 형식이며 GiB 기준으로 해석합니다. 예를 들어 `32G`는 32 GiB root disk target size입니다.

이미 디스크 부족으로 망가진 PoC runtime은 재생성합니다.

```sh
make vm-clean
make vm-prepare
```

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
