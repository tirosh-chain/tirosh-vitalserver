# Usage

이 문서는 Vital Server Helper를 설치한 뒤 운영자가 어떤 순서로 확인하면 되는지 설명합니다.
build machine에서 결과물을 만드는 절차는 사용자 흐름이 아니므로 Dev 문서에서 다룹니다.

## 1. 설치 흐름

Helper package는 fresh install을 기준으로 합니다. 기존 설치물, launchd service, package receipt,
또는 Host proxy port 충돌이 있으면 설치 전 검사가 설치를 막습니다.

### 1-1. 새 설치

Mac 사용자에게는 서명 및 공증된 Helper installer를 전달합니다.

```text
VitalServerHelper-<version>.dmg
```

DMG 안에는 `Install VitalServer Helper.pkg`와 문제 해결용 `Troubleshooting Tools` 폴더가 함께
들어 있습니다. 새 설치는 `Install VitalServer Helper.pkg`를 실행합니다.

설치 후 Helper app을 열고 Status 화면에서 runtime 상태를 확인합니다.

처음 설치한 직후에는 VM과 runtime service가 순서대로 준비되기 때문에 완료까지 보통 4~5분 정도
걸릴 수 있습니다. 이 동안 Status나 Advanced 화면에 `Installing` 또는 `Initializing`이 보이면
정상적인 설치/초기 기동 진행 상태로 보고 기다립니다.

`Installing` 또는 `Initializing`이 오래 유지되거나 `Critical`로 바뀌면 installer 화면 메시지,
Status의 failure reason, Logs 화면을 함께 확인합니다.

### 1-2. 설치가 막히는 경우

아래와 같은 메시지가 보이면 기존 host 상태가 남아 있어 fresh install이 차단된 것입니다.

```text
VitalServer Helper pkg install supports fresh installs only.
An existing VitalServer Helper install, launchd service, package receipt,
or Host proxy port conflict blocks this install.
```

이 경우 installer를 반복 실행하지 않습니다.
[Reset for Reinstall command](reset-installer.md)로 정리한 뒤 다시 설치합니다.

내부 Clean uninstall과 reset command는 목적이 다릅니다. Clean uninstall은 정상 제거 흐름이고,
reset command는 재설치 blocker를 제거하는 recovery tool입니다. 차이는
[Clean Uninstall and Reset for Reinstall](clean-uninstall.md)를 봅니다.

## 2. Helper app에서 확인할 것

설치 후에는 Helper app을 열고 Status 화면부터 확인합니다. Status는 전체 요약이고, 세부 원인은
다른 화면에서 나눠 봅니다.

### 2-1. 화면별 확인 포인트

처음에는 Status 화면에서 전체 상태를 보고, 문제가 보이는 영역에 따라 Recorders, Beds,
Advanced, Observability, Logs 화면으로 이동합니다.

| 화면 | 언제 보는가 | 확인할 것 |
|---|---|---|
| Status | 설치 직후, 평소 상태 확인, 장애 첫 확인 | overall health, VitalServer 연결, PWA 연결, data directory, recorder summary |
| Recorders | recorder가 보이지 않거나 stale/offline일 때 | VRecorder status, IP, 연결 bed, last seen, anomaly count |
| Beds | bed와 recorder 연결 상태를 볼 때 | bed status, 연결 VRecorder, patient 연결 여부 |
| Advanced | runtime service나 VM 상태를 볼 때 | VM/service 상태, active operation, runtime version, failure reasons |
| Observability | 상태 변화의 시간 순서를 볼 때 | event timeline, recorder anomaly, relationship history |
| Logs | 지원 자료를 모으거나 상세 로그를 볼 때 | command, update activation, VM, container, watchdog logs |

설치 직후 Advanced에서 일부 service나 HTTP endpoint가 아직 준비되지 않아도, active operation이
`Installing`이면 설치 작업 중으로, `Initializing`이면 runtime service와 guest가 사용 가능 상태로
올라오는 중으로 봅니다. 설치와 초기 기동이 끝난 뒤에도 `Stopped`, `Unavailable`, `Read failed`가
남아 있을 때 세부 점검을 시작합니다.

### 2-2. 상태를 읽을 때 주의할 점

상태는 임의로 판단하지 않습니다. 예를 들어 recorder가 화면에 없다고 해서 항상 “장비가 없다”는
뜻은 아닙니다. 관측 자료를 읽지 못했거나, 관측 자료가 오래되었거나, 실제로 최신 관측에 없는
상황이 서로 다를 수 있습니다.

| 보이는 상태 | 먼저 확인할 곳 |
|---|---|
| `Critical` | Status의 failure reason, Advanced, Logs |
| `Needs attention` | Status 요약 이후 Recorders/Beds 또는 Advanced |
| recorder `Stale` | Recorders의 last seen, Observability anomaly |
| bed `Offline` | Beds의 연결 VRecorder, relationship history |
| read issue | Logs와 Observability store failure 여부 |

자세한 상태값 의미는 [Runtime Status](runtime-status.md)를 봅니다.

### 2-3. Backup과 restore

일반 backup/restore는 Advanced -> Recovery operations의 `VitalServer backup`을 사용합니다.
이 backup은 Helper가 관리하는 runtime 설정, Host runtime 상태, observability history, Redis data를
하나의 복구 단위로 묶습니다. 따라서 일반 사용자는 runtime data와 Redis를 따로 backup하거나 따로
restore하지 않습니다.

선택한 backup이 현재 Helper와 호환되지 않으면 restore는 파일을 덮어쓰기 전에 실패합니다.
호환성 기준과 backup 내부 artifact 구성은 Dev 문서의
[Backup/Restore 계약](../dev/backup-restore-contracts.md)을 봅니다.

Backup 삭제는 Danger Zone에서 분리되어 있습니다. `Delete VitalServer Backup`은 선택한
VitalServer backup만 삭제하고, `Delete Update Backup`은 update/rollback용 backup만 삭제합니다.
두 작업 모두 현재 runtime data를 직접 삭제하지 않습니다.

삭제 전에 별도로 보관한 VitalServer backup을 다시 사용하려면 Finder로 임의 위치에 복사하지 말고
Advanced -> Recovery operations의 `Import Backups`를 사용합니다. Import는 선택한 backup 폴더를
Helper가 보고한 `backups/runtime-data` 관리 폴더의 직접 자식으로 복사하며, 같은 이름의 backup이
이미 있으면 덮어쓰지 않습니다. `Open Backups`는 해당 VitalServer backup 관리 폴더를 엽니다.

`Redis-only recovery`는 Repair 성격의 고급 조치입니다. VM disk repair, uninstall, 장애 분석처럼
Redis data만 별도로 보존하거나 복원해야 하는 상황에서 지원 담당자가 사용합니다. 정상 운영에서
전체 상태를 되돌릴 때는 Redis-only backup 대신 VitalServer backup을 선택합니다.
Redis-only backup을 외부에서 다시 가져올 때도 `Import Backups`를 사용합니다. Import는 `redis-*.tar.gz`
archive만 Redis backup 관리 폴더의 직접 자식으로 복사하며, 같은 이름의 archive가 있으면 덮어쓰지
않습니다. `Restore Redis-only Backup`은 선택한 Redis archive만 복원합니다.

Upstream VitalServer에서 Helper로 1회 migration을 할 때는 DMG의 `Troubleshooting Tools` 폴더에 있는
`Create Upstream Redis Backup.command`를 사용합니다. 생성한 archive는 Advanced -> Recovery operations
-> Redis-only recovery의 `Import Backups`로 가져온 뒤 `Restore Redis-only Backup`으로 복원합니다.
upstream Redis archive 생성 방식과 command log 위치는 Dev 문서의
[Backup/Restore 계약](../dev/backup-restore-contracts.md)을 봅니다.

## 3. Settings 적용

Settings 화면의 `Restart VM runtime when required`는 저장 후 항상 runtime service를 재시작한다는
뜻이 아닙니다. 변경된 설정이 VM runtime restart를 요구할 때, 그 restart를 즉시 수행할지 선택하는
옵션입니다.

VM runtime restart가 필요한 설정은 VM 실행 조건을 바꾸는 값입니다.

| 설정 | 적용 방식 |
|---|---|
| CPU, memory | VM runtime restart 필요 |
| disk 증가 | VM disk resize 후 VM runtime restart 필요 |
| network mode, bridged interface | VM network device 재구성이 필요하므로 VM runtime restart 필요 |
| Vital files directory | VM shared directory mount 재구성이 필요하므로 VM runtime restart 필요 |
| VitalServer URL, Remote Console URL, public host/port | runtime config 문서 갱신, VM runtime restart requirement 없음 |
| admin password, Redis backup retention | guest runtime settings 갱신, VM runtime restart requirement 없음 |
| start on boot, auto recovery, sleep prevention | Host launchd/config 정책 갱신, VM runtime restart requirement 없음 |

따라서 URL이나 Redis backup retention 같은 설정만 바꿨는데 `Restart VM runtime when required`가
켜져 있어도 VM을 내리지 않습니다. 반대로 CPU, memory, disk 증가, network, Vital files directory를
바꾸고 이 옵션을 끄면 설정은 저장되지만 현재 실행 중인 VM에는 다음 VM runtime restart 때 반영됩니다.

Settings 화면은 restart requirement를 각 설정 row에 흩어진 badge로 표시하지 않고, `VM runtime restart`
영역에 모아서 표시합니다. 저장된 설정이 아직 실행 중인 VM에 반영되지 않은 경우 이 영역에서
`Requires VM restart` badge/action을 눌러 pending VM 설정 적용을 확인합니다.

Settings 탭은 저장된 설정을 보여주고, Status/Info 탭은 현재 VM runtime에 적용된 설정을 보여줍니다.
예를 들어 Vital files directory를 바꾸고 VM runtime restart를 하지 않았다면 Settings 탭에는 새 경로가
보이지만 Status의 data directory는 이전 적용 경로를 유지해야 합니다. 이 차이가 있으면 Settings 탭의
restart 안내가 아직 반영되지 않은 VM runtime 변경을 표시합니다.
`Requires VM restart` badge는 해당 설정이 VM runtime restart 후에 적용되는 값이라는 뜻입니다. 설정을
저장한 뒤 아직 VM runtime에 적용되지 않은 변경이 있으면 badge를 눌러 VM runtime restart 확인을 열 수
있습니다.

Settings apply는 update bundle 적용이 아닙니다. 진행 상태가 보이면 operation은 `configure`로
해석하고, update bundle 검증/적용 상태와 섞어 판단하지 않습니다.

## 4. Update 적용

Product Update는 Helper app의 Update 탭에서 적용합니다. 현장 Mac에서 update bundle을 만드는
것이 아니라, release 담당자가 만든 `update-bundle-...tar.gz` 파일을 전달받아 적용하는 흐름입니다.

### 4-1. Update 탭에서 진행

| 단계 | 화면에서 할 일 |
|---|---|
| Update source | `Choose Bundle`로 전달받은 offline update bundle을 선택 |
| Bundle verification | `Verify Bundle`로 checksum과 bundle 구성을 먼저 확인 |
| Apply update | 검증이 성공한 뒤 `Apply Bundle`로 update 적용 |
| Update progress | 진행 메시지와 command log를 보며 완료 또는 실패 여부 확인 |

현재 build에서는 online update가 아니라 offline bundle 적용을 기준으로 합니다. Update 탭에
`Online update is planned for connected sites` 안내가 보이면, 전달받은 offline bundle을 사용합니다.

### 4-2. 적용 전 확인

- update bundle 파일명이 전달받은 release 안내와 맞는지 확인합니다.
- `Verify Bundle`이 실패하면 `Apply Bundle`을 진행하지 않습니다.
- update 중에는 VitalServer service가 재시작될 수 있습니다.
- 실패하면 같은 bundle을 반복 적용하기보다 Update progress, Logs, Observability event를 먼저 확인합니다.

Update 중 rollback이 실행될 수 있습니다. Rollback health wait가 최종적으로 `hostProxyHTTP=200` 같은
정상 health를 확인하면 runtime은 이전 backup으로 돌아온 것입니다. 이 상태는 “update 성공”이 아니라
“update 실패 후 rollback 성공”입니다. Update progress와 Observability event에서 실패 단계,
rollback 단계, rollback 결과를 함께 확인합니다.

`prepare-update-shutdown` 단계에서 실패하면 Logs의 update shutdown result와 guest log를 확인합니다.
Guest가 실패 service, 남은 service 목록, snapshot path를 남긴 경우 그 details가 1차 원인입니다.
Host proxy 연결 실패나 container exited reason은 restart/rollback 중 나타나는 후속 증상일 수 있습니다.

### 4-3. 지원 담당자 CLI

지원 담당자가 직접 update bundle을 검증하거나 적용해야 할 때만 runtime CLI를 사용합니다.

```sh
/usr/local/bin/vitalserver-vm runtime verify-bundle /path/to/update-bundle.tar.gz
sudo /usr/local/bin/vitalserver-vm runtime apply-bundle /path/to/update-bundle.tar.gz
```

CLI와 Helper app의 Update 탭은 같은 update backend를 사용합니다. 일반 사용자 절차는 Update 탭을
기준으로 합니다.

## 5. 로그와 지원 자료

문제가 생기면 화면에 보이는 상태만 전달하지 않습니다. 같은 `Critical`이라도 설치 실패,
update 실패, recorder 관측 실패, service 실행 실패는 확인해야 하는 자료가 다릅니다.

지원 담당자가 같은 상황을 다시 따라갈 수 있도록, 상태 화면, logs, event 기간을 함께 모읍니다.

### 5-1. 먼저 기록할 것

지원 요청을 만들기 전에 아래 정보를 먼저 적어 둡니다.

| 항목 | 예시 |
|---|---|
| 발생 시각 | `2026-06-08 14:30 KST` |
| 사용한 화면 | Status, Update, Recorders, Beds, Observability, Logs |
| 보이는 상태 | Healthy, Needs attention, Critical, Updating, Recovering 등 |
| 직전에 한 작업 | install, update 적용, reset command 실행, runtime start/stop |
| 선택한 파일 | update bundle, reset command, installer package |

가능하면 화면 screenshot도 함께 보관합니다. 다만 환자 정보, 병원 내부 IP, 인증 정보, token이
보이면 공개 issue에 올리지 않습니다.

### 5-2. Helper app에서 모을 자료

Helper app이 열리는 상태라면 아래 순서로 확인합니다.

1. Status 화면에서 overall health와 failure reason을 확인합니다.
2. 문제가 recorder 또는 bed와 관련되어 있으면 Recorders/Beds 화면의 status와 last seen을 확인합니다.
3. Update 중 실패했다면 Update 탭의 Update progress 메시지를 확인합니다.
4. Observability 화면에서 문제가 발생한 시간대와 event filter를 확인합니다.
5. Logs 화면에서 `Export Logs`를 실행해 log zip을 만듭니다.

`Open Logs`는 Mac 안의 로그 폴더를 여는 기능이고, `Export Logs`는 지원 담당자에게 전달할 수
있는 zip 파일을 만드는 기능입니다.

### 5-3. 상황별로 필요한 자료

| 상황 | 함께 전달할 자료 |
|---|---|
| 설치 실패 | Installer 화면 메시지, `/var/log/install.log`, 사용한 installer package 이름 |
| Update 실패 | Update progress, 선택한 update bundle 이름, Logs 화면의 export zip, Observability event 시간대 |
| runtime이 Critical | Status/Advanced 상태, failure reasons, Logs 화면의 export zip |
| recorder/bed가 stale 또는 offline | Recorders/Beds 화면 상태, last seen, Observability anomaly, event 시간대 |
| Reset command 실패 | 사용자 temp의 `tirosh-vitalserver-reset-for-reinstall.log`, `/private/tmp/tirosh-vitalserver-uninstall.log`, `/var/log/install.log` |
| 상태 화면을 읽지 못함 | read issue 메시지, Logs 화면의 export zip, Observability store failure 여부 |

### 5-4. 직접 확인할 수 있는 로그

Helper app에서 export가 되지 않거나 설치/정리 단계에서 app을 열 수 없다면 아래 로그를 확인합니다.

```sh
tail -n 300 /var/log/install.log
tail -n 300 /private/tmp/tirosh-vitalserver-uninstall.log
```

Troubleshooting Tools의 double-click command는 권한 상승 전 wrapper 로그를 현재 사용자 temp
directory에 남깁니다. Reset command는 `tirosh-vitalserver-reset-for-reinstall.log`, upstream Redis
backup command는 `tirosh-vitalserver-upstream-redis-backup.log`를 확인합니다.

runtime이 설치된 뒤의 상세 로그는 기본적으로 아래 위치에 있습니다.

```text
/Library/Application Support/VitalServerHelper/logs/
```

### 5-5. 공개 issue에 올리지 않을 것

공개 GitHub issue에는 아래 정보를 올리지 않습니다.

- 환자 정보
- 병원 내부 IP 또는 네트워크 구성
- 인증 정보, 비밀번호, token
- 원본 로그 전체
- 병원 내부 승인이나 의료 판단이 필요한 내용

공개 issue에는 재현 절차, 기대 결과, 실제 결과, 상태 이름, 필요한 경우 마스킹한 로그 일부만
작성합니다.

## 6. 설치 경로

아래 경로는 지원 담당자가 설치 상태를 확인하거나 로그를 모을 때 자주 봅니다. 일반 운영자는
대부분 Helper app 화면과 `Export Logs`만 사용하면 됩니다.

### 6-1. 주요 경로

| 항목 | 위치 |
|---|---|
| Helper app | `/Applications/VitalServer Helper.app` |
| runtime CLI | `/usr/local/bin/vitalserver-vm` |
| host proxy runner | `/usr/local/bin/vitalserver-proxy-run` |
| uninstaller | `/usr/local/bin/tirosh-vitalserver-uninstall` |
| runtime home | `/Library/Application Support/VitalServerHelper/` |
| status file | `/Library/Application Support/VitalServerHelper/status/runtime-status.json` |
| logs | `/Library/Application Support/VitalServerHelper/logs/` |
| LaunchDaemons | `/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.*.plist` |

### 6-2. 언제 확인하나

| 경로 | 언제 보는가 |
|---|---|
| Helper app | 설치 후 앱을 열거나 app bundle 존재 여부를 확인할 때 |
| runtime CLI | 지원 담당자가 health, update, service command를 직접 실행할 때 |
| runtime home | VM/runtime 상태, logs, backups, status 문서 위치를 확인할 때 |
| status file | Helper app이 읽는 runtime 상태 문서를 확인할 때 |
| logs | `Export Logs`가 어렵거나 특정 log source를 직접 확인할 때 |
| LaunchDaemons | service가 load되어 있는지, disabled override가 남았는지 확인할 때 |

### 6-3. 직접 수정하지 않을 것

아래 파일과 directory는 Helper가 소유합니다. 지원 담당자의 안내 없이 직접 삭제하거나 수정하지
않습니다.

- `/Library/Application Support/VitalServerHelper/`
- `/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.*.plist`
- `/usr/local/bin/vitalserver-vm`
- `/usr/local/bin/vitalserver-proxy-run`
- `/usr/local/bin/tirosh-vitalserver-uninstall`

재설치가 막혀 정리가 필요하면 파일을 수동으로 지우기보다
[Reset for Reinstall command](reset-installer.md)를 사용합니다.

## 7. 지원 담당자 참고

사전 검증용 package를 repository에서 직접 만들 때는 Dev 문서의
[Delivery & Validation](../dev/delivery-validation.md)을 기준으로 합니다.

문서 site는 아래 명령으로 확인할 수 있습니다.

```sh
make docs/serve
```
