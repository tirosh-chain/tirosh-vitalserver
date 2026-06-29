# 005 golden rootfs 준비 중 `apt-get update`가 Release file 시간 오류로 실패

> ID: TS-005  
> Category: Guest bootstrap  
> Owner: macOS runtime  
> Status: implemented

증상:

```text
Release file ... is not valid yet
```

원인:

golden rootfs 준비용 VM의 첫 부팅 직후 guest 시간이 실제 시간보다 과거일 수 있습니다. cloud-init final 단계가 package install을 먼저 시작하면 apt repository metadata 시간이 미래처럼 보입니다.

특히 snapshot apt source를 사용할 때 guest 시간이 snapshot repository metadata보다 과거이면 아래처럼 `noble-updates` 또는 `noble-security` Release file이 아직 유효하지 않다고 판단합니다. 이 상태는 apt mirror 문제가 아니라 compile VM clock 입력이 명시되지 않았다는 신호입니다.

조치:

`Support/Guest/prepare-airgap-rootfs.sh`는 build-machine에서만 apt를 실행합니다. target Mac의 `bootstrap.sh`는 air-gapped 계약 때문에 apt를 실행하지 않습니다.

golden rootfs compile은 NTP 동기화 성공을 fallback으로 쓰지 않습니다. Host/devtools가 `deploy/build-metadata/rootfs-input.json`에 `guestClockUtc`를 기록하고, guest bootstrap은 `apt-get update` 전에 `guest-clock` stage에서 그 값을 시스템 시각으로 설정해야 합니다.

확인:

```sh
sed -n '1,120p' .tmp/vitalserver-vm-golden/data/deploy/build-metadata/rootfs-input.json
rg -n "guest-clock|Release file .* is not valid yet" .tmp/vitalserver-vm-golden/logs/launcher.log
```

## Follow-up

- 2026-06-12: golden rootfs input metadata에 `guestClockUtc`를 추가하고, guest bootstrap이 apt 전에 명시 시각을 적용하도록 변경했습니다. 누락/invalid clock은 fallback 없이 `guest-clock` 실패로 처리합니다.
