# Release Delivery Proof Attachment Boundary

> 상태: **C74 contract, immutable proof-set publication tool, unit/integration proof 구현 완료 / 실제 OS clean-host evidence는 여전히 release operator의 별도 사실**

## 1. 왜 별도 경계가 필요한가

C24 `ReleaseDeliveryProofSet`은 “어느 C23 release plan이 어느 clean-host
사실로 검증되었는가”를 표현한다. 하지만 runner가 생성한 local evidence와 source tree의
기본 C24 template은 owner와 수명주기가 다르다.

| 사실 | owner | durable form | 성공으로 오해하면 안 되는 것 |
| --- | --- | --- | --- |
| 어느 installer/service/proof stage가 release에 필요했는가 | Release process | C23 `ReleaseDeliveryPlan` | installer가 build되었음 |
| OS command가 관측한 설치·service·reboot 사실 | matching OS clean-host runner | runner SQLite + evidence document + C24 fragment | source C24 template 변경 |
| 검토자가 어떤 fragment/evidence bytes를 검토했는가 | Release process | C74 `ReleaseDeliveryProofAttachmentReview` | Host 설치 effect |
| 검토 결과로 생긴 proof-set candidate | Release process | 새 `release-delivery-proofs.v1.json` | checked-in C24 template 수정 |

`tooling/release_delivery_proof_attachment.py`는 세 번째와 네 번째 행만
소유한다. Host Agent, Guest Runtime, installer, launchd/SCM/systemd, VM, updater의
state를 읽거나 쓰지 않는다.

## 2. 명시적 입력과 산출물

```text
C23 plan document ───────────────┐
C24 source proof set (pending) ──┼─> C74 review attachment ─> new immutable C24 candidate
runner proof fragment ───────────┤                 └───────> C74 review record
reviewed evidence material ──────┘
```

모든 input은 absolute regular file로 caller가 지정한다. `reviewed evidence
material`은 fragment에 적힌 URI와 SHA-256을 신뢰하기 위한 별도 bytes input이다.
tool은 URI에서 파일을 추론하거나 내려받지 않는다. 검토자가 제시한 bytes가 fragment의
SHA-256과 다르면 output directory를 만들지 않는다.

성공하면 **기존에 없던** output directory에 다음 두 파일만 원자적으로 발행한다.

- `release-delivery-proofs.v1.json` — source C24 set의 사본에서 검토된 stage만 terminal fact로 교체한 candidate
- `release-delivery-proof-attachment-review.v1.json` — source, fragment, evidence, output SHA-256을 묶은 C74 review record

checked-in `product/delivery/release-delivery-proofs.v1.json`나 runner journal은
수정하지 않는다. 이것이 local observation과 reviewed release declaration을 섞지 않는
이유다.

## 3. 전이와 guard

| guard | 이유 |
| --- | --- |
| source C24 stage가 정확히 `pending` | verified/failed/unsupported 과거 사실을 새 fragment로 바꾸지 않는다 |
| fragment의 `(planId, stage)`가 C23 required stage와 정확히 일치 | 계획에 없는 stage나 다른 release의 evidence를 attach하지 않는다 |
| fragment의 platform/provider가 C23와 일치 | 다른 OS runner의 사실을 재사용하지 않는다 |
| fragment status는 `verified`, `failed`, `unsupported` 중 하나 | pending을 다시 attach하여 검토 성공처럼 보이게 하지 않는다 |
| `verified`에는 URI가 일치하는 evidence material과 SHA-256 일치가 필요 | URI 문자열, filename, runner id만으로 OS 사실을 만들지 않는다 |
| fragment/evidence material은 중복 없이 모두 소비 | 하나의 evidence를 여러 proof에 암묵적으로 재사용하거나, 검토하지 않은 input을 숨기지 않는다 |
| output directory는 사전에 없어야 함 | 과거 review output을 덮어써 audit 사실을 바꾸지 않는다 |

`failed` 또는 `unsupported` fragment는 C24 contract가 요구하는 issue를 이미 보존한다.
C74가 이를 `verified`로 승격하지 않으며, 다음 release attempt는 새 source proof set과 새
review output으로 시작해야 한다.

## 4. 운영 절차

다음은 runner가 이미 evidence file과 fragment file을 만든 뒤의 review 단계다. matching
OS runner의 `write-stage-proof-fragment` command는 caller가 고른 새 absolute file에
`{"schemaVersion":"v1","proofs":[...]}` fragment를 한 번만 발행한다. attachment
tool은 그 fragment를 다시 생성하지 않는다.

```sh
python3 -m tooling.release_delivery_proof_attachment \
  --runtime-platform-root /absolute/source/runtime-platform \
  --release-delivery-plans-document /absolute/release-input/release-delivery-plans.v1.json \
  --source-proof-set /absolute/source/runtime-platform/product/delivery/release-delivery-proofs.v1.json \
  --proof-fragment /absolute/evidence/macos/clean-install-proof.json \
  --reviewed-evidence-material file:///absolute/evidence/macos/clean-install.json=/absolute/evidence/macos/clean-install.json \
  --output-directory /absolute/release-evidence/macos-020-reviewed \
  --review-id macos-020-review \
  --reviewer-id release-operator-01 \
  --reviewed-at 2026-07-20T08:00:00Z
```

candidate는 source tree로 복사하지 않고 명시적 path로 검증한다.

```sh
make -C runtime-platform release-ready \
  RELEASE_DELIVERY_PLANS_DOCUMENT=/absolute/release-input/release-delivery-plans.v1.json \
  RELEASE_DELIVERY_PROOF_SET_DOCUMENT=/absolute/release-evidence/macos-020-reviewed/release-delivery-proofs.v1.json \
  RELEASE_DELIVERY_PROOF_ATTACHMENT_REVIEW_DOCUMENT=/absolute/release-evidence/macos-020-reviewed/release-delivery-proof-attachment-review.v1.json
```

다른 required C24 stage가 아직 pending이면 이 gate는 계속 실패한다. 이는 attachment
tool의 오류가 아니라 아직 release-ready가 아니라는 정확한 결과다.

`release-ready`는 C74의 source URI/SHA-256, candidate filename/SHA-256, 그리고
review가 열거한 source `pending` → candidate terminal stage 변화를 모두 다시
검증한다. 따라서 schema만 맞는 C24 file을 임의로 편집하거나, 다른 source/output bytes의
review를 붙이는 방식은 최종 gate를 통과하지 못한다.

최종 gate는 checked-in canonical C24 template을 source로 한 **한 번의** C74
attachment만 받는다. 중간 candidate를 다음 attachment의 source로 사용해 review chain을
만들면, 마지막 C74만으로 이전 review들의 completeness를 추론해야 하기 때문이다. 여러
OS/stage fragment는 final review 때 같은 canonical source에 함께 전달한다. 중간 candidate는
release-ready assertion이 아니라 review 작업의 명시적 결과일 뿐이다.

## 5. 보관과 한계

이 tool은 evidence를 upload, notarize, sign, 또는 장기 보관하지 않는다. `file://` URI가
가리키는 local file도 review 시점의 bytes는 검증할 수 있지만, 장기 release evidence로
삼을 위치는 release process가 별도로 운영하는 durable artifact store여야 한다. C74는 그
store의 존재나 접근 권한을 추정하지 않는다.

Apple Developer ID/notarization, actual root installer effect, reboot, update,
rollback, uninstall/reinstall은 각 OS runner의 C24 stage가 계속 owner다. C74 review
성공은 “검토된 bytes를 candidate에 반영했다”는 뜻일 뿐, product installation success가
아니다.
