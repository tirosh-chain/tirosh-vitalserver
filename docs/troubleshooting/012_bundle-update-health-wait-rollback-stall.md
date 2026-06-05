# 012 bundle update가 health wait 또는 rollback에서 오래 멈춤

> ID: TS-012  
> Category: Update  
> Owner: macOS runtime  
> Status: active

증상:

Helper app에서 `Apply Bundle`을 실행한 뒤 화면상으로 업데이트가 5분 이상 진행되지 않는 것처럼 보입니다. Logs 탭에도 최신 진행 상태가 바로 보이지 않거나, command log가 마지막 줄에서 끊긴 것처럼 보일 수 있습니다.

원인:

bundle apply는 아래 순서로 동작합니다.

```text
verify bundle
stage bundle
create managed backup
stop runtime services
replace bundle artifacts
start runtime services
wait for runtime health
rollback if health does not recover
wait for rollback health
```

runtime health wait는 의도적으로 길게 잡혀 있습니다. VM 부팅, Docker compose 재시작, VitalServer app worker 준비가 모두 끝나야 하기 때문입니다. 다만 health wait 중 내부 서비스가 계속 실패하면, 사용자는 멈춘 것으로 느낄 수 있습니다.

확인:

```sh
tail -f /private/tmp/tirosh-vitalserver-manager-command.log
cat "/Library/Application Support/TiroshVitalServer/status/runtime-status.json"
tail -n 200 "/Library/Application Support/TiroshVitalServer/vm/data/run/container-logs.log"
```

최신 Helper app은 command log를 Logs 탭에서 실시간 갱신하고, runtime health wait 중에도 `waiting for runtime health reasons=...` 형태의 진행 로그를 남깁니다. 이전 버전에서 시작한 update/rollback 작업에는 이 개선이 적용되지 않습니다.

Update 탭에서는 적용 중인 현재 step과 Command log tail을 함께 표시합니다. 화면이 `Applying update bundle...` 한 줄에서 오래 멈춰 보이면 먼저 `Command log` source를 확인합니다.

조치:

먼저 command log와 container log에서 실제 실패 원인을 확인합니다. update가 이미 rollback 단계에 들어간 경우에는 중간에 강제 종료하면 runtime이 반쯤 교체된 상태로 남을 수 있으므로, 가능한 한 rollback timeout이 끝날 때까지 기다립니다. 반복적으로 health가 회복되지 않으면 새 bundle 또는 재설치로 복구합니다.

Helper app의 Advanced > Recovery operations에는 `Repair Data Store`가 있습니다. 이 작업은 VM 내부에 복구 요청 파일을 만들고, guest systemd path unit이 Redis AOF 검사/복구와 container 재시작을 수행하게 합니다. update 실패 후 Redis 또는 VitalServer health가 회복되지 않을 때 먼저 시도합니다.

Update 과정의 전체 계약, 보존/변경 범위, 0.1.3 실패 분석은 [Update](../runtime/macos/update.md)를 봅니다.

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
