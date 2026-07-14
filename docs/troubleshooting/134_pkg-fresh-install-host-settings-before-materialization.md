# PKG fresh install이 `vm-config.json` 부재로 즉시 실패함

> ID: TS-134
> Category: Packaging / Host state persistence
> Owner: macOS runtime
> Status: resolved in code; package install verification pending

## Symptoms

- macOS Installer가 `Running package scripts...` 단계에서 수 초 안에 실패합니다.
- `/var/log/install.log`에는 `preinstall` 통과 직후 다음 패턴이 기록됩니다.

```text
VitalServer Helper postinstall started
The file “vm-config.json” couldn’t be opened because there is no such file.
postinstall failed status=1 command=... runtime install-provision
PKInstallErrorDomain Code=112
```

- 실패 cleanup 이후 Helper app, runtime home, launchd plist, package receipt는 남지 않습니다.

## Cause

Host settings의 authoritative owner를 SQLite로 전환하면서 install composition이 workflow 시작 전에
Host state store를 준비하도록 변경됐습니다. 그런데 이 준비 함수는 database schema 초기화뿐 아니라,
SQLite settings row가 없으면 `vm-config.json`, `runtime-config.json`, `runtime-settings.json`을 읽어
settings row로 import했습니다.

Fresh package payload에는 이 세 파일이 의도적으로 포함되지 않습니다. 이 파일은 설치 설정으로부터
생성하는 boot materialization이므로, `install-provision` workflow가 생성해야 합니다. 그 결과
fresh install은 boot 문서를 생성하기 전에 첫 파일을 읽으면서 실패했습니다.

기존 composition 테스트는 state-store 준비 함수를 파일을 읽지 않는 stub으로 대체했습니다.
따라서 잘못된 호출 순서는 테스트에 고정됐지만 빈 runtime home에서 발생하는 dependency failure는
compile 검증에 노출되지 않았습니다.

## Fix

설치 경계를 다음 순서로 분리했습니다.

1. package payload absence/presence contract를 읽습니다.
2. SQLite schema와 workflow operation repository만 초기화합니다.
3. 명시적인 install settings로 complete Host settings payload를 생성합니다.
4. SQLite에 desired revision 1을 저장합니다. 이 시점에는 materialized revision이 없습니다.
5. SQLite payload의 Guest boot documents를 atomic write합니다.
6. SQLite payload의 VM boot document를 atomic write합니다.
7. 세 문서를 모두 read back하고 exact payload equality를 증명합니다.
8. 증명된 revision만 materialized로 기록합니다.

기존 JSON import는 명시적인 legacy migration 경계에만 남깁니다. Fresh install은 파일 부재에서
settings state를 만들거나 기존 파일을 owner로 사용하지 않습니다.

## Verification

빈 temporary product root를 사용하는 `RuntimeFreshInstallHostSettingsTests`가 다음 상태를 검증합니다.

- schema 초기화 후 세 boot document는 모두 absent이고 Host settings read는 `missing`입니다.
- settings 준비 후 desired revision은 1이며 materialized revision은 없습니다.
- Guest materialization 후 VM config는 아직 absent입니다.
- VM materialization과 세 문서 exact readback 이후에만 materialized revision이 1입니다.

Repository와 Domain tests는 initial desired revision, already-existing guard, explicit materialization
transition을 별도로 검증합니다.

## Prevention

- Database readiness와 aggregate initialization을 하나의 함수에서 암묵적으로 결합하지 않습니다.
- Fresh install은 generated boot documents를 설정 owner로 import하지 않습니다.
- Compile verification에는 stub-only composition test뿐 아니라 빈 실제 filesystem과 SQLite repository를
  사용하는 fresh-install contract test를 포함합니다.
- Artifact readback과 golden runtime smoke는 target Mac의 `postinstall`을 실행하지 않습니다. 정적 artifact
  검증 통과를 설치 성공으로 해석하지 않으며, 전달 전에는 verified install workflow도 실행합니다.
- Missing, decode failed, permission failed, materialization mismatch는 각각 명시적인 설치 실패로 유지합니다.

## Checks

```sh
grep -n "vm-config.json.*no such file\|postinstall failed\|PKInstallErrorDomain Code=112" /var/log/install.log
pkgutil --pkg-info ai.tirosh.vitalserver.helper
```

설치 실패 cleanup 후 마지막 명령은 `No receipt`를 반환해야 합니다. Package-owned 파일이나 서비스가
남았다면 새 설치를 반복하기 전에 cleanup 실패를 별도 원인으로 조사합니다.

## Related Cases

- TS-024
- TS-042
- TS-132
