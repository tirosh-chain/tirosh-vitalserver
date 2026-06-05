# <case title>

> ID: TS-XXX  
> Category: <Update | Runtime health | Guest bootstrap | Guest containers | Data store | Host proxy | Network | Packaging | Uninstall | Local development>  
> Owner: <owner boundary>  
> Status: <active | resolved | superseded | archived>

## Case Metadata

- `ID`: `docs/troubleshooting.md` 색인에서 다음 번호를 사용합니다. 한 번 부여한 ID는 파일명이 바뀌어도 유지합니다.
- `Category`: 증상이 가장 먼저 분류될 운영 영역입니다. 여러 영역에 걸치면, 사용자가 처음 확인해야 하는 영역을 선택합니다.
- `Owner`: 원인 분석과 최종 조치 책임을 갖는 코드/운영 경계입니다. 예: `macOS runtime`, `guest bootstrap`, `host proxy`, `VitalServer app`, `testkit`.
- `Status`: 이 문서의 현재 유효성입니다. 제품 runtime 상태가 아닙니다.
  - `active`: 현재 버전이나 현장 설치본에서 여전히 참고해야 합니다.
  - `resolved`: 원인은 수정됐지만, 이전 설치본이나 과거 분석을 위해 보존합니다.
  - `superseded`: 더 정확한 새 문서가 생겼고, 이 문서는 링크/맥락 보존용입니다.
  - `archived`: 더 이상 재현 가능성이 낮고 운영 판단에 거의 쓰지 않는 기록입니다.

## Symptoms

- 사용자가 보는 증상을 먼저 씁니다.
- UI 문구, command output, log line처럼 검색 가능한 문자열을 포함합니다.
- 증상이 발생한 화면/단계/update version이 있으면 함께 적습니다.
- “어떤 상태가 정상이고, 어떤 상태가 비정상인지”를 분명히 적습니다.
- 동일 증상으로 보일 수 있는 다른 케이스가 있으면 `Related cases`에 연결합니다.

## Impact

- 사용자나 운영 환경에 미치는 영향을 씁니다.
- 데이터 손실 가능성, update/rollback 중단 가능성, VM 재설치 필요 여부를 구분합니다.
- 영향이 낮은 UI 표시 문제인지, 서비스 중단/데이터 보존 판단이 필요한 문제인지 적습니다.

## Cause

- 확인된 원인을 씁니다.
- 아직 추정이면 `추정:`으로 시작하고, 어떤 로그나 재현 조건에서 추론했는지 남깁니다.
- 제품 버그, 운영 환경, user action, external dependency 중 어디에 가까운지 구분합니다.

## Checks

먼저 확인할 로그와 명령을 적습니다. 실행 권한이 필요한 명령은 `sudo` 여부를 명시합니다.

```sh
# 문제를 확인할 때 먼저 볼 명령이나 log path를 둡니다.
# 예:
# tail -n 200 "/Library/Application Support/TiroshVitalServer/logs/runtime/launchd.out.log"
```

## Actions

- 현장에서 수행할 조치를 순서대로 씁니다.
- destructive action이나 data loss 가능성이 있으면 먼저 backup/확인 절차를 둡니다.
- 최신 버전에서 해결된 경우, 어떤 migration/update/package 이후부터 해결되는지 적습니다.

## Prevention

- 같은 문제가 다시 발생하지 않도록 제품 코드, packaging, migration, 운영 절차 중 어디를 바꿨는지 씁니다.
- 아직 예방책이 없으면 `TBD`로 두고 Follow-up에 연결합니다.

## Operational Notes

- rollback, uninstall, Redis backup, VM disk 보존처럼 운영 판단에 필요한 주의점을 씁니다.
- 같은 증상이 재발했을 때 추가로 수집해야 할 로그가 있으면 여기에 둡니다.

## Related Cases

- 관련 troubleshooting ID가 있으면 연결합니다. 예: `TS-012`, `TS-013`.

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
- 예: `2026-05-28: #35에서 재현. 0.1.8-dev update bundle에 migration 추가.`
