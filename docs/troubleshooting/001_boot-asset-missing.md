# 001 `make vm-start`가 boot asset 없음으로 실패

> ID: TS-001  
> Category: Local development  
> Owner: macOS runtime  
> Status: archived

증상:

```text
error: missing file: .../runtime/Image
```

원인:

`vitalserver-vm start`는 VM만 실행합니다. Linux kernel, initrd, root disk, cloud-init seed가 없으면 시작할 수 없습니다.

조치:

```sh
make vm-prepare
make vm-start
```

또는 한 번에:

```sh
make vm-up
```

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
