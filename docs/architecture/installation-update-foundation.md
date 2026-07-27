# Installation and update foundation

> 상태: **서명된 bootstrap, durable handoff, next-updater 실행, 세 Product
> layer의 effect executor 및 complete-bundle composition acceptance 완료.**
> macOS PKG composition은 실제 Guest bootstrap artifact, Host Agent, Edge
> Proxy, Update Handoff Supervisor를 하나의 PKG에 조립·검증한다. 실제
> clean-host 설치, layer activation, rollback, uninstall delivery proof는
> 계속 `pending`이다.

Installation and update foundation은 update를 “새 파일을 덮어쓴다”가 아니라 서로 다른 호환성 언어를
가진 두 updater의 명시적 handoff로 만든다. 첫 delivery 목표는 macOS arm64
clean install이지만, Windows amd64와 Linux amd64도 같은 C25–C31 계약을
사용한다. `product/delivery/support-matrix.v1.json`은 이 선택을 선언한다.
선언의 `planned`는 package 존재나 설치 성공이 아니다.

## 1. 해결하려는 문제

제품 update spec은 시간이 지나며 layer, rollback, artifact, activation
규칙이 늘어난다. 이전 updater가 미래의 모든 spec을 이해하게 만들면
`minimumUpdaterVersion` 같은 gate와 bridge release가 계속 생긴다. 반대로
이전 updater가 모르는 spec을 “대충” 처리하면 trust/rollback 경계가 사라진다.

이 경계의 선택은 다음과 같다.

- **C25**만 오래 유지되는 작은 bootstrap 언어로 고정한다.
- 현재 Host updater는 C25 signature, next-updater artifact와 spec digest를
  검증·stage할 책임만 가진다. C26 내용을 parse하지 않는다.
- stage 전/후의 durable operation은 Host SQLite의 **C29**가 소유한다.
- stage된 **next updater**만 C26을 parse해 명시적인 layer plan을 만들고,
  declared executor의 C55 receipt를 검증해 C28 evidence를 만든 뒤 C52
  OS-local transport로 C27 completion을 Host에 보낸다.
- C25가 없거나 invalid하거나 trust evidence가 없으면 failed/unavailable
  receipt이며, legacy parser, 다른 layer, 성공 상태로 fallback하지 않는다.

따라서 “모든 release를 현재 updater가 해석한다”는 뜻이 아니다. 모든 release는
**현재 updater가 이해하는 C25**와 signed next updater를 포함해야 한다는
뜻이다. 미래에 C25 자체를 바꿔야 하면 이전 bootstrapper는 explicit
`unsupported`/`failed`가 되어야 하며, 이를 숨기는 migration branch를
추가하지 않는다.

## 2. Owner와 구성 경계

| 대상 | owner | 가진 상태/책임 | 가지지 않는 책임 |
| --- | --- | --- | --- |
| Release process | release tooling | C25, C26, artifact digests, signature 생성 | Host journal 또는 installed release 변경 |
| Host Agent | Host OS + Host SQLite | C27 admission, C29 journal, current installation revision, bootstrap receipt 검증, handoff/recovery | C26 parse, Guest/container 내부 상태 추측 |
| Native bootstrap adapter | macOS/Windows/Linux Host adapter | signature/trust 확인, next updater staging, idempotent handoff effect | update success 판정 |
| `host-updater` | staged next updater process | C26 plan parse, 순서/의존성 검증, declared executor byte 재검증, C55→C28, C52→C27 completion | Host SQLite 직접 변경 |
| layer effect executor | release-owned container/Guest/Host platform boundary | one declared artifact의 apply/rollback과 C55 typed receipt | 다른 layer로 fallback, Host operation 소유 |

`host-updater`는 별도 Go module이다. Host Agent가 그 source를 import하지
않으므로 C26을 추가·확장해도 현재 Host Agent의 domain policy가 변하지 않는다.
Host와 next updater가 공유하는 것은 source package가 아니라 C25/C27/C28/C29/C30
JSON 계약이다. Host bootstrapper와 deployment supervisor는 C31로 durable queue
handoff를 분리한다.

## 3. 세 layer와 ordering

업데이트 layer는 이름과 위험이 다르다.

| layer | 범위 | 기본 난이도 | 안전 규칙 |
| --- | --- | --- | --- |
| `container` | Guest 안 runtime container artifact | 가장 낮음 | 명시된 artifact/rollback evidence만 사용 |
| `guest-runtime` | Guest runtime/image/service | 중간 | Guest activation result를 C28로 보고 |
| `host-platform` | Host Agent/service/provider/bootstrapper | 가장 높음 | **항상 마지막** layer |

“container가 쉽다”는 default ordering이 아니다. C25 `layerOrder`가 release마다
실행 순서를 소유한다. C26은 그 순서를 바꾸거나 숨은 sort를 할 수 없고,
각 `dependsOn`은 앞에서 이미 실행된 layer만 가리킬 수 있다. Host platform을
먼저 바꾸면 handoff를 실행한 runner 자체를 잃을 수 있으므로 C25/C26 policy가
마지막만 허용한다.

## 4. 상태 전이와 handoff

```text
Host C27 admission
  -> C29 requested
  -> C25 verified + next updater staged
  -> C29 bootstrap-staged
  -> C29 handoff-pending  --(idempotent native handoff)--> staged next updater
  -> C29 applying         --(C28 from next updater)-----> succeeded | failed
                                                    \----> Host release revision advances only on succeeded
```

Host는 `handoff-pending`을 **effect 전에** durable commit한다. 같은 `requestId`
와 같은 command digest를 다시 받으면 기존 operation/journal을 반환하며 stage나
handoff를 다시 실행하지 않는다. C28의 exact report digest 재전송도 terminal
journal을 바꾸지 않는다.

재시작 recovery는 매우 좁다.

- `bootstrap-staged`: durable receipt는 있지만 handoff commit 전 crash였으므로
  Host가 `handoff-pending`으로 commit한 뒤 handoff를 요청한다.
- `handoff-pending`: 같은 journal ID로 idempotent handoff effect만 다시 요청한다.
- `applying`: Host는 next updater가 살아 있는지 추측하지 않는다. journal은
  `applying`으로 남고, 같은 updater의 C28 completion 또는 별도 운영 recovery
  policy가 필요하다.
- terminal journal: effect를 재실행하지 않는다.

Host persistence read/write가 실패해 admission/result 존재를 알 수 없으면 HTTP는
`CommandAdmissionFailure(admissionState=unknown)`을 돌려준다. 성공처럼 보이는
stale object나 empty state를 반환하지 않는다.

## 5. 계약과 API

| 계약 | 주요 내용 |
| --- | --- |
| C25 `UpdateBootstrapEnvelope` | target, ordered layer list, signed next updater artifact, opaque C26 artifact digest, Ed25519 trust evidence |
| C26 `ProductUpdateSpecification` | next updater만 해석하는 per-layer artifact/dependency/rollback plan과 digest·size·media type으로 고정된 `effectExecutor` |
| C27 | Host update admission command, bootstrap receipt, Host-local completion command |
| C28 `UpdateExecutionReport` | layer별 `succeeded/failed/unavailable/unsupported`, rollback, typed issue/evidence |
| C29 `HostUpdateJournal` | Host SQLite durable operation, C25 recovery input/digests, journal revision, receipt/report/failure |
| C30 `StagedUpdateInvocation` | C29가 `handoff-pending`으로 durable commit된 뒤 Host가 발행하는 next-updater input. `requestId`와 `expectedHandoffJournalRevision`은 C27 completion이 제시해야 할 정확한 Host journal version을 고정한다. Host가 해당 version을 원자적으로 검증한 뒤 `applying` 전이와 C28 정산을 수행하며, C30은 C26 path의 기준 디렉터리도 보존 |
| C31 `StagedUpdateHandoff` | Host staging queue 안에서 C30의 상대 위치를 가리키는 durable handoff item |
| C52 `HostLocalAdministrationEndpointDescriptor` | Host Agent가 공개한 OS-local Unix socket/Windows named pipe 주소. next updater는 이 descriptor 이외의 completion target을 선택하지 않음 |
| C55 `StagedUpdateLayerEffectReceipt` | C26-declared executor가 고정 protocol apply/rollback 뒤 기록하는 typed layer outcome. process exit/log은 C55를 대체하지 못함 |
| Host Update Operation Ownership (C80) | 현재 installation identity/revision에 대해 active Update Journal이 없다는 `idle` 또는 유일한 active owner를 Host Agent가 명시적으로 제공하는 Host-local coordination read |

## Active update ownership

Host Agent는 `requested`, `bootstrap-staged`, `handoff-pending`, `applying`
Update Journal 전체를 active owner로 취급한다. Host SQLite의 partial unique
index가 이 상태의 journal을 최대 하나로 제한하고, application admission
policy도 기존 owner를 읽고 검증한 뒤 두 번째 update command를 거부한다.

`GET /v1/platform/update-operation-ownership`은 이 상태를 다른 Host
lifecycle workflow에 제공한다. `available` read 안의 `state=idle`만 update
owner가 없다는 의미다. endpoint 부재, state-store read 실패, decode 실패,
installation identity/revision 불일치는 install/remove 허가로 변환하지
않는다.

이 계약은 coordination read의 첫 단계다. Host Installation Manager가
실제 preflight/remove 전에 이 read를 소비하고, 이후 cancel/wait/interrupt
명령과 child updater process ownership을 연결하는 작업은 별도 application
workflow로 이어진다.

Host-local routes는 `contracts/openapi/control.v1.json`에 `x-network-scope:
host-local`로 명시했다.

- `POST /v1/platform/updates` — C27 admission → `{ operation, journal }`
- `GET /v1/platform/updates/{updateId}` — C29 `ReadResult`
- `POST /v1/platform/updates/{updateId}:complete` — staged next updater의 C27
  completion + C28 report → `{ operation, journal }`

이 route들은 browser/public maintenance API가 아니다. operator
authentication/authorization과 public maintenance surface를 설계하기 전에는
Host-local transport로만 배치해야 한다.

## 6. 자동 증명과 남은 증명

`make -C runtime-platform host-updater-test`은 C26의 order, dependency,
Host-platform-final policy를 순수 next-updater 모듈에서 검증한다.

`make -C runtime-platform installation-update-acceptance`은 실제 Host Agent composition과
별도 `host-updater` binary를 실행해 다음을 검증한다. updater는 C30/C26을 읽고,
C26에 선언된 digest-verified fixture executor만 고정 argument protocol로 실행해 C55를
읽고 C28을 원자적으로 기록한다. 이어 C52 Unix socket을 통해 C27 completion을
제출한다. 따라서 harness의 HTTP 직접 호출이 next-updater completion을 대신하지 않는다.

1. C25 envelope → C29 handoff-pending을 durable하게 만들고 request-id replay가
   stage/handoff를 중복하지 않는다.
2. next updater가 matching C26 plan과 C55 receipt만 받아들이고 C28 success
   report로 release revision을 한 번만 전진시킨다.
3. restart가 durable `handoff-pending` journal만 다시 handoff한다.
4. bootstrap `unavailable`과 out-of-order C28 evidence가 release를 바꾸지 않고
   typed terminal failure가 된다.

Acceptance bootstrapper는 명확히 test-only이다. signed bundle의 native
signature verification·filesystem staging과 next-updater execution protocol은
증명하지만, acceptance fixture의 C55 executor는 실제 Guest/container/Host
artifact를 교체하지 않는다. macOS PKG install, concrete replacement executor,
release rollback, C24 clean-host runner가 이를 package/reboot/update/rollback
evidence로 바꾼다.

## 7. 구현 중 발견한 운영 규칙

| 증상 | 원인 | 수정 방향 | 예방 원칙 |
| --- | --- | --- | --- |
| update write가 실패했는데 HTTP 202처럼 보임 | durable state write failure를 stale outcome으로 반환 | `CommandAdmissionFailure(unknown)`으로 노출 | persistence ambiguity를 success/fallback으로 변환하지 않는다 |
| SQLite JSON은 decode되지만 bootstrap digest/receipt/report가 서로 맞지 않음 | JSON decode만으로 Host-owned state를 신뢰함 | C29 cross-field validation 후 `invalid`/admission failure로 노출 | decode 성공과 유효한 owned state를 같은 의미로 취급하지 않는다 |
| 재시작 후 updater가 무엇을 하던 중인지 알 수 없음 | Host가 process/layer internal state를 소유하지 않음 | `applying`은 유지하고 C28 또는 별도 운영 policy를 요구 | Host는 Guest/next-updater internals를 추측하지 않는다 |
| future spec을 old updater가 parse하려 함 | C25와 C26 경계가 섞임 | next updater module만 C26 parser를 import | evolution은 stable bootstrap handoff로 처리한다 |
