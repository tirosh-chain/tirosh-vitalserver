# Standard uninstall retained data blocks fresh package install

> ID: TS-187
> Category: Uninstall / Packaging
> Owner: macOS runtime Application / HostCLI / Packaging
> Status: implemented; package verification pending

## Symptoms

- Standard Uninstall은 완료되고 package receipt도 없어졌지만 다음 PKG 설치가 fresh preflight에서 실패합니다.
- `/Library/Application Support/VitalServerHelper`가 다시 존재하고 그 아래에는 `logs`, `backups`, 또는 `vm/data/backups/redis`만 남아 있습니다.
- 다른 경우에는 product root와 receipt는 없지만 `/usr/local/bin/tirosh-vitalserver-uninstall`만 남아 fresh install을 차단합니다.

정상 상태는 standard uninstall 완료 후 product root, Helper app, runtime tools, uninstaller, LaunchDaemon plist, service, package receipt가 모두 absent이고, 보존 자료만 별도 retained root에 있는 것입니다.

## Impact

- 데이터 보존을 선택한 사용자가 fresh package reinstall을 할 수 없습니다.
- operator가 설치를 통과시키려고 product root를 수동 삭제하면 보존하려던 logs/backups를 잃을 수 있습니다.
- wrapper가 남은 uninstaller를 별도 `rm`으로 숨기면 CLIHost terminal cleanup proof와 실제 Host state가 달라집니다.

## Cause

Standard uninstall은 product root 안의 보존 후보를 임시 directory로 옮긴 뒤 파일 제거가 성공하면 원래 product root 아래로 복원했습니다. Fresh preflight는 product root 존재를 올바르게 stale install artifact로 분류하므로 두 계약이 서로 모순되었습니다.

실행 중 uninstaller는 CLIHost cleanup artifact 목록에 있었지만 shell wrapper도 뒤에서 `rm -f`를 수행했습니다. 이 중복 owner는 CLIHost가 self-removal을 완료하지 못해도 wrapper가 증상을 숨길 수 있고, wrapper cleanup까지 실행되지 않은 현장에서는 lone uninstaller가 남을 수 있습니다.

## Checks

```sh
sudo tail -n 250 /private/tmp/tirosh-vitalserver-uninstall.log
sudo ls -la "/Library/Application Support/VitalServerHelper"
sudo ls -la "/Library/Application Support/VitalServerHelper-retained-uninstall-data"
ls -l /usr/local/bin/tirosh-vitalserver-uninstall
pkgutil --pkg-info ai.tirosh.vitalserver.helper
```

성공한 standard uninstall에는 다음 형태가 기록됩니다.

```text
retained standard uninstall data path=/Library/Application Support/VitalServerHelper-retained-uninstall-data/tirosh-vitalserver-uninstall-<run-id> owner=uninstall-retained-data
terminal cleanup verified uninstaller=/usr/local/bin/tirosh-vitalserver-uninstall
```

## Actions

1. 이전 버전에서 product root 또는 lone uninstaller가 남았다면 보존할 logs/backups를 먼저 별도 위치에 복사합니다.
2. Troubleshooting Tools의 explicit reset-for-reinstall command로 product-owned stale artifacts를 정리합니다. configured external Vital files directory는 직접 삭제하지 않습니다.
3. TS-187 수정이 포함된 package를 설치합니다.
4. 이후 standard uninstall 보존 자료는 `/Library/Application Support/VitalServerHelper-retained-uninstall-data`에서 확인합니다.
5. 모든 product-owned retained run을 삭제하려면 configured external Vital files 경로를 확인한 뒤 Clean Uninstall을 사용합니다.

## Prevention

- Standard uninstall은 product root 안의 `logs`, `backups`, `vm/data/backups/redis`만 sibling retained root의 run별 directory로 이동합니다.
- Vital files ownership은 materialized JSON 파일이 아니라 operation lease 획득 후 읽은 SQLite Host settings record가 제공합니다. Desired와 applied payload가 다르면 두 `VMRuntimeConfig`의 경로를 모두 보존 판단에 사용하고 revision을 log에 남깁니다.
- Known legacy managed default `/Library/Application Support/VitalServerHelper/vm/data/vital-files`는 현재 desired/applied 경로인지와 관계없이 standard uninstall retained run의 `legacy-vital-files`로 이동합니다.
- Shared managed default `/Users/Shared/VitalServerHelper/vital-files`와 안전한 configured external Vital files directory는 standard uninstall에서 기존 위치에 둡니다.
- Run directory는 unique ID를 사용하고 이미 존재하는 path를 덮어쓰지 않습니다. 여러 standard uninstall 결과는 누적됩니다.
- SQLite missing/read failure, desired/applied VM config decode failure, path missing, empty/relative path는 default path로 바꾸지 않습니다. Standard/Clean 모두 effect command 전에 `vital-files-ownership-unavailable`로 중단합니다.
- Exact legacy/shared managed default 외 configured path가 product root, managed defaults, retained root와 ancestor/descendant로 겹치면 silent external 분류 없이 같은 blocker로 중단합니다.
- `--force-clean-uninstaller`만 unavailable ownership을 명시적 destructive recovery로 받아들입니다. 진단에는 원래 unavailable reason과 configured path 보존을 증명할 수 없다는 한계가 남습니다.
- Standard cleanup verifier는 product root를 clean/standard 모두에서 absent로 요구합니다.
- Retained root는 fresh-install artifact 목록에 넣지 않습니다.
- Clean uninstall만 legacy/shared 두 managed default와 product-owned retained root를 제거하며 안전하게 분류된 configured external Vital files는 제거하지 않습니다.
- CLIHost가 uninstaller path까지 제거하고 absent를 관측한 뒤 receipt 단계로 전이합니다. Shell wrapper는 추가 삭제 fallback을 하지 않고 잔존을 failure로 보고합니다.

## Operational Notes

- Retained root는 package payload가 아니라 `uninstall-retained-data` owner가 관리하는 운영 보존 영역입니다.
- 보존 directory의 run ID와 실제 path는 uninstall log에서 확인합니다.
- 실패 중 원위치 복원은 성공 fallback이 아닙니다. Workflow는 `files-removal-blocked`를 기록하고 receipt 제거/완료로 진행하지 않습니다.
- Clean uninstall은 retained root 전체를 삭제하므로 필요한 archive를 먼저 외부 backup으로 복사해야 합니다.
- Ownership이 available이고 안전한 external로 분류된 configured Vital files directory는 standard/clean 모두 보존됩니다. Force-clean unavailable recovery에서는 configured path를 알 수 없어 보존 여부를 증명할 수 없습니다.
- 현재 ownership 비교는 `standardizedFileURL` lexical normalization이며 symlink target을 resolve하지 않습니다. Symlink-aware proof는 filesystem read 결과를 명시하는 별도 Host 계약 없이는 pure classifier에 추가하지 않습니다.

## Related Cases

- [TS-042](042_host-install-uninstall-state-contract-gap.md)
- [TS-065](065_clean-uninstall-reset-installer-boundary.md)
- [TS-184](184_clean-uninstall-external-vital-files-directory-deletion.md)

## Follow-up

- 2026-07-27: retained-data owner를 product root sibling으로 분리하고 SQLite desired/applied ownership, legacy/shared defaults, overlap block, force-clean recovery, standard/clean/fresh preflight 및 self-removing uninstaller 계약 테스트를 추가했습니다. 실제 PKG uninstall/reinstall 검증은 아직 필요합니다.
