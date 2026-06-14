# Swift UI Parity Matrix

## Purpose

이 문서는 macOS Helper Swift UI와 Runtime Control PWA 사이의 기능 parity를 추적합니다. PWA는 Swift UI와 같은 정보를 제공하는 것이 목표지만, 브라우저 권한 모델 때문에 일부 기능은 Runtime Control API capability 또는 host affordance로 제공해야 합니다.

## Status Vocabulary

| 상태 | 의미 |
|---|---|
| `Implemented` | PWA에서 기능과 주요 표시 정보가 제공됩니다. |
| `Capability gated` | API capability가 허용될 때만 표시/실행됩니다. |
| `Host affordance` | 브라우저가 직접 수행하지 않고 API/native shell 지원이 필요합니다. |
| `Deferred` | 의도적으로 별도 이슈로 분리했습니다. |
| `Needs review` | 기능은 있으나 Swift UI와 의미/UX parity 재검토가 필요합니다. |

## Screen Parity

| Swift UI 화면 | PWA route | 상태 | 메모 |
|---|---|---|---|
| Status | `/` | `Implemented` | runtime summary, VitalServer URL, data directory stats, recorder summary, resource usage 제공 |
| Settings | `/settings` | `Implemented` | VM resources, network exposure, storage/Redis, sleep prevention, validation 제공 |
| Update | `/update` | `Needs review` | bundle selection/apply flow는 UI가 있으나 file picker/download affordance는 browser 제약 검토 필요 |
| Observability | `/observability` | `Implemented` | observation pipeline, runtime events period/type/limit filtering 제공 |
| Recorders | `/recorders` | `Implemented` | VRecorder list/detail/activity chart/relationship history 제공 |
| Beds | `/beds` | `Implemented` | bed list/detail/relationship history 제공 |
| Logs | `/logs` | `Implemented` | source/line/live stream/read/export controls 제공 |
| Advanced | `/advanced` | `Capability gated` | Swift Advanced 구조에 맞춰 diagnostics, VM health, service health, recovery operations, advanced network, admin operations 제공 |
| Danger Zone | `/danger-zone` | `Capability gated` | Swift Danger Zone 구조에 맞춰 update backup 삭제, VitalServer backup 삭제, destructive operations 제공 |
| Test | `/test` | `Capability gated` | TestKit capability가 있을 때만 virtual recorder controls 제공 |

## Function Parity

| 기능 | PWA 상태 | SoT/API | 비고 |
|---|---|---|---|
| Runtime overview | `Implemented` | `/runtime/overview` | Status 첫 화면의 primary read model |
| Runtime status stream | `Implemented` | `/runtime/overview/stream`, `/runtime/status/stream` | polling fallback은 query layer 책임 |
| Runtime events | `Implemented` | `/runtime/events` | 최신순, period/type/limit filter |
| Runtime settings read/apply | `Implemented` | `/runtime/settings` | domain policy로 validation |
| Runtime service start/stop | `Capability gated` | `/runtime/services/start`, `/runtime/services/stop` | confirmation 필요 |
| Runtime repair | `Capability gated` | `/runtime/services/repair-*` | Advanced에서 제공 |
| Rollback backup list/delete | `Capability gated` | `/host/backups`, `DELETE /host/backups/update` | update backup 삭제는 Danger Zone에서 명시 action으로 제공 |
| VitalServer backup list/create/restore/delete | `Capability gated` | `/runtime/data/backups`, `/host/backups/runtime-data` | create/restore는 Advanced, delete는 Danger Zone에서 제공 |
| Redis backup create/restore | `Capability gated` | `/runtime/redis/backups`, `/host/backups/redis` | restore는 command availability 확인 필요 |
| Logs read/stream | `Implemented` | `/host/logs/read`, `/host/logs/stream` | host log path는 직접 열지 않음 |
| Logs export | `Host affordance` | host log export endpoint | browser download endpoint가 없으면 native와 동일 UX 불가 |
| VRecorder history | `Implemented` | `/vitaldb/recorders` | identity는 `vrcode` |
| VRecorder activity chart | `Needs migration` | `/vitaldb/recorders/{vrcode}/activity` | lazy 12-hour window query로 이동 필요 |
| Bed history | `Implemented` | `/vitaldb/beds` | bed identity는 `bedID` |
| Relationship history | `Implemented` | `/vitaldb/relationships` | recorder/bed detail에 assignments/events 최대 8개씩 표시 |
| TestKit virtual recorder | `Capability gated` | `/dev/testkit/*` | test-enabled build only |
| Authentication/session | `Deferred` | planned runtime auth/session contract | 별도 이슈에서 독립 진행 |
| Online update | `Deferred` | planned update source contract | 인증/session 이후 재검토 |

## Recorder Display Rule

PWA Recorders 화면은 Runtime Control API가 제공한 `RuntimeVitalRecorderRecord.status`를 그대로 표시합니다.
`lastSeenAt`, anomaly, activity timestamp, audit activity 유무로 online/stale 상태를 다시 계산하지 않습니다.
Host read model은 observer가 제공한 explicit `stale` state를 `online`보다 우선해야 하며, UI는 그 결과를 렌더링만 합니다.

Recorder activity rolling window는 화면의 현재 시각을 오른쪽 경계로 사용합니다. 마지막 activity timestamp는
별도 metadata로 표시하고, rolling chart의 오른쪽 축을 마지막 data timestamp에 고정하지 않습니다. 데이터가 멈추면
현재 시각까지의 bucket은 0으로 표시되어야 합니다. All/history 탐색은 예외적으로 data 범위를 기준으로 페이지를 나눕니다.

Recorder activity summary는 운영자가 바로 판단할 수 있는 `Packets`, `Total packets`, `Data rate`만
기본 표시합니다. `roomCount`는 observation/API contract에는 남지만, 고유 room 수나 현재 연결 room 수가
아니므로 Swift/PWA 기본 UI에서 `Room entries`로 노출하지 않습니다.

## Host Affordance Gaps

PWA에서 Swift UI와 다르게 처리해야 하는 대표 기능입니다.

- Finder로 logs/backups 폴더 열기
- local update bundle file picker
- host-local file path 직접 접근
- privileged installer/uninstaller UX
- native alert/sheet 대체

이 기능은 PWA 내부에서 임시로 흉내 내지 않고 Runtime Control API 또는 native shell capability로 명시해야 합니다.

## Advanced / Danger Zone Parity Rule

PWA Advanced와 Danger Zone은 Swift UI를 1:1 parity 기준으로 추적합니다. route별 책임은 다음처럼 유지합니다.

- Advanced: diagnostics, VM health, service health, recovery operations, advanced network, admin operations.
- Recovery operations: update recovery, VitalServer backup, runtime repair, advanced repair tools, Redis-only recovery.
- Admin operations: reset admin password, runtime service controls.
- Danger Zone: Delete Update Backup, Delete VitalServer Backup, Destructive operations.

PWA는 Swift에 없는 fallback state를 만들지 않습니다. Runtime settings apply는 `/runtime/settings`가 제공한 명시 settings document를 기준으로만 활성화하고, advertised URL은 absolute `http`/`https` URL validation을 통과해야 합니다.

## Review Checklist

- Swift UI에 보이는 runtime 정보가 PWA route에서도 같은 의미로 제공되는가?
- unavailable 기능이 조용히 사라지지 않고 capability/host affordance로 설명되는가?
- command는 confirmation과 result display를 갖는가?
- TestKit 기능이 product route나 runtime status 의미를 오염시키지 않는가?
- PWA-only UX가 Runtime Control API 계약 밖의 임시 state에 의존하지 않는가?
