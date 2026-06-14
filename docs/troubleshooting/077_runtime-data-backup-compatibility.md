# Runtime Data Backup Compatibility Gate

## Case Metadata

| Field | Value |
|---|---|
| ID | TS-077 |
| Category | Data store / Runtime health |
| Owner | Host backup/restore |
| Status | active |

## Symptoms

VitalServer backup을 선택해 restore가 시작되지만, 해당 backup이 현재 runtime과 다른 data layout으로
생성된 경우입니다. Compatibility를 확인하기 전에 restore가 진행되면 Host config file, status document,
observability SQLite, Redis data를 덮어쓴 뒤에야 incompatibility가 드러날 수 있습니다.

관련 증상은 아래처럼 보일 수 있습니다.

- Runtime Control이 restored settings/status document를 decode하지 못함
- Recorders, Beds, activity, relationship history가 사라지거나 query에 실패함
- Redis restore는 완료됐지만 현재 VitalServer가 old Redis key를 읽지 못함
- 선택한 backup에 compatibility contract가 없는데도 restore가 성공한 것처럼 보임

## Cause

VitalServer backup은 product-level restore unit 하나로 보이지만 내부에는 여러 data schema가
들어 있습니다. Redis data, VM config, guest runtime config, guest runtime settings, proxy LaunchDaemon
plist, start-on-boot state, status/events document, observability SQLite는 서로 다른 contract가
소유합니다.

`runtimeVersion`만 기록해서는 충분하지 않습니다. Product version과 backup restore compatibility는
독립적으로 움직일 수 있습니다. Restore는 어떤 artifact도 쓰기 전에 backup manifest의 명시적인
`restoreCompatibilityVersion`을 확인해야 합니다.

## Actions

Backup manifest는 `backupKind=vitalserver-helper`와 `restoreCompatibilityVersion`을 포함해야 합니다.
이 버전부터 이전 `runtime-data` kind/path를 읽는 fallback은 지원하지 않습니다. Restore는 아래 경우
file을 쓰기 전에 backup을 거부해야 합니다.

- `restoreCompatibilityVersion`이 없음
- 선언된 compatibility version을 현재 Helper가 지원하지 않음
- manifest schema, product, artifact identity validation 실패
- required artifact size, checksum, state, relative path validation 실패

오래된 compatibility version을 지원해야 한다면 runtime destination에 쓰기 전에 명시 migration을
추가합니다. Filename, runtime version string, artifact 존재 여부, checksum 성공만으로 compatibility를
추정하면 안 됩니다.

## Prevention

- Backup compatibility를 UI copy나 product version text가 아니라 data layout contract로 취급합니다.
- Old backup을 migration 없이 안전하게 restore할 수 없으면
  `RuntimeDataBackupCompatibility.currentRestoreCompatibilityVersion`을 올립니다.
- Backup manifest schema나 restored artifact schema가 바뀌면 missing/unsupported compatibility
  version test를 추가합니다.
- 모든 artifact의 schema owner를 `docs/runtime/macos/runtime-data-backup.md`에 기록합니다.

## Related Cases

- [VitalServer Backup](../runtime/macos/runtime-data-backup.md)
