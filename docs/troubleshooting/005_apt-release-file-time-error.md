# 005 golden rootfs 준비 중 `apt-get update`가 Release file 시간 오류로 실패

> ID: TS-005  
> Category: Guest bootstrap  
> Owner: macOS runtime  
> Status: archived

증상:

```text
Release file ... is not valid yet
```

원인:

golden rootfs 준비용 VM의 첫 부팅 직후 guest 시간이 실제 시간보다 과거일 수 있습니다. cloud-init final 단계가 package install을 먼저 시작하면 apt repository metadata 시간이 미래처럼 보입니다.

조치:

`Support/Guest/prepare-airgap-rootfs.sh`는 build-machine에서만 apt를 실행합니다. target Mac의 `bootstrap.sh`는 air-gapped 계약 때문에 apt를 실행하지 않습니다. 이 오류가 나면 golden rootfs 준비 VM의 시간 동기화 상태를 먼저 확인합니다.

수동 확인:

```sh
timedatectl
timedatectl show -p NTPSynchronized --value
```

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
