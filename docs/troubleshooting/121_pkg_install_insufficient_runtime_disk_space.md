# pkg 설치가 runtime disk 공간 부족으로 실패함

> ID: TS-121
> Category: Packaging / Install
> Owner: macOS runtime install provisioning
> Status: active

## Symptoms

macOS Installer가 `Running package scripts...` 뒤 다음과 같이 실패합니다.

```text
An error occurred during installation.
The installation failed.
PKInstallErrorDomain Code=112
```

`/var/log/install.log` 또는
`/private/tmp/tirosh-vitalserver-postinstall-failure.log`에는 다음과 같은
명시 실패가 남습니다.

```text
error: insufficient free space for provision-runtime-data-disk:
required 20.0 GiB, available 5.9 GiB
```

## Impact

fresh install의 `postinstall`이 실패합니다. 이 경로는 이번 package attempt가
만든 product payload와 runtime state를 정리하고 failure log를 `/private/tmp`에
보존하므로, 설치 성공이나 정상 runtime 상태로 해석하면 안 됩니다.

## Cause

기본 fresh install은 immutable `rootfs-base.raw.gz`에서 VM disk를 만들고,
별도로 16 GiB runtime data disk를 준비합니다. 두 파일이 모두 없을 때는
VM rootfs 확장 여유 공간과 runtime data disk 16 GiB, 각각의 4 GiB safety
margin이 모두 필요합니다.

이전 구현은 VM disk의 약 8 GiB 요구량만 확인한 뒤 rootfs를 풀고, 그 다음에
runtime data disk의 20 GiB를 따로 확인했습니다. 따라서 total capacity가
부족한 Mac에서 rootfs를 푼 뒤에야 실패했습니다. 현장 실패 당시에는 첫 검사가
14.0 GiB에서 통과했지만 rootfs 확장 뒤 5.9 GiB만 남아 두 번째 검사에서
실패했습니다.

현재 구현은 두 disk가 모두 새로 필요하면 약 28 GiB를 하나의
`provision-vm-and-runtime-data-disks` preflight로 rootfs 확장 전에 확인합니다.
정확한 요구량은 package에 포함된 compressed rootfs 크기에 따라 달라집니다.

## Checks

설치 대상 Data volume의 실제 여유 공간과 Installer failure evidence를 확인합니다.

```sh
df -h /System/Volumes/Data
grep -n "insufficient free space\|postinstall\|PKInstallErrorDomain Code=112" /var/log/install.log
tail -n 200 /private/tmp/tirosh-vitalserver-postinstall-failure.log
```

새 package에서는 failure log의 `required`와 `available` 값을 그대로 사용합니다.
`required`는 해당 install state의 계약값이며, `available`이 더 작으면 retry해도
성공으로 전환되지 않습니다.

## Actions

1. Installer를 종료하고 `/System/Volumes/Data`에 공간을 확보합니다. product의
   default fresh install은 **Installer 실행 전 최소 32 GiB 이상의 여유 공간**을
   권장합니다. package payload 복사 뒤 provisioning은 대략 28 GiB를 요구합니다.
2. product와 무관한 cache, download, 또는 이전 build artifact를 지울 때는 소유자와
   보존 필요성을 확인합니다. backup, 기존 VitalServer runtime data, `.vital` 파일을
   공간 확보 목적으로 임의 삭제하지 않습니다.
3. previous failed attempt가 정리되지 않아 product artifact가 남아 있으면 fresh-install
   preinstall failure를 확인하고 uninstall/clean uninstall 정책에 따라 먼저 정리합니다.
4. 위 checks에서 `available >= required`를 확인한 뒤 package를 다시 설치합니다.

## Prevention

- `RuntimeInstallVMDiskProvisioner`는 VM disk와 runtime data disk의 존재 상태를
  먼저 읽고, 둘 다 missing이면 필요한 용량을 합산해 side effect 전에 한 번만
  검증합니다.
- combined preflight가 실패하면 rootfs temporary file 삭제, gunzip, file move,
  `truncate`가 실행되지 않는 회귀 테스트를 유지합니다.
- 설치 대상의 free-space 부족은 Host filesystem contract failure로 남기며,
  smaller data disk나 empty/default runtime 상태로 fallback하지 않습니다.

## Operational Notes

- 이 문제의 `PKInstallErrorDomain Code=112`는 package 서명이나 payload decode 오류를
  뜻하지 않습니다. `postinstall`의 명시 free-space error가 원인입니다.
- 현재 package가 실패 cleanup을 완료했다면 package receipt와 product root가 남지
  않아야 합니다. 남아 있다면 retry 전에 fresh-install preflight가 명시적으로
  차단합니다.
- rootfs artifact 크기 또는 configured runtime data disk size가 바뀌면 필요한 공간도
  함께 바뀝니다. 고정 숫자 대신 install log의 `required` 값을 우선합니다.

## Related Cases

- TS-024: pkg `postinstall` failure의 일반 진단과 cleanup 경계
- TS-072: build-time package preflight와 install-time runtime provisioning은 서로 다른 경계

## Follow-up

- 2026-07-13: macOS field install에서 rootfs expansion 뒤
  `provision-runtime-data-disk` free-space failure를 확인했습니다.
- 2026-07-13: VM disk와 runtime data disk가 모두 missing일 때 합산 free-space
  preflight를 rootfs expansion 앞으로 이동했습니다.
