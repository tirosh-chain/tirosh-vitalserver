# Host installation transaction이 payload 실패 뒤 서비스를 멈춘 채 남는 경우

> ID: TS-155
> Category: Packaging / Host state persistence
> Owner: Host Installation Manager
> Status: implemented for C50; Helper 0.2.1 contained as fresh-only; clean-Host C24 evidence pending

## Symptoms

PKG preinstall은 성공했지만 Installer payload 또는 postinstall이 실패한 뒤, 기존
Host Agent/Host Edge Proxy가 다시 올라오지 않거나 다음 설치가 아래처럼 막힐 수 있다.

```text
unfinished-installation-transaction
```

또는 `current` link는 새 slot을 가리키지만 서비스 registration이 없는 `activated`
상태가 남을 수 있다. 이 상태를 data directory가 비어 있거나 package receipt가
존재한다는 사실만으로 clean/reinstall success로 분류하면 안 된다.

Legacy VitalServer Helper 0.2.1 direct PKG에서는 receipt가 이미 있는 target이
`same-version-repair`, `upgrade`, `downgrade` 중 하나로 분류되고 preinstall에서
차단된다. 따라서 이 문서의 C50 service-quiescence transaction을 구현하지 않은
Helper package가 receipt-present target에서 payload overwrite를 시작해서는 안 된다.

## Cause

초기 C50 sequence는 preinstall에서 services를 quiesce한 뒤 Installer가 immutable
payload를 쓰도록 했다. Payload write가 실패하면 postinstall은 실행되지 않으므로,
중지 효과를 보상할 installed manager/C48 slot도 없었다. 또한 stop effect 전에
durable intent가 없어서 process interruption 중 partial stop과 side-effect 없는
preflight를 구분할 수 없었다.

preflight-only 방식으로 바꾼 뒤에도 preflight가 C50 journal을 쓰기 위해
`data/installation-manager`와 그 parent를 만든다는 사실을 clean install residue로
취급하면, payload가 전혀 전달되지 않은 재시도를 스스로 차단하게 된다. 반대로
그 directory나 symbolic-link ancestor를 일반 data로 추측하면 Host boundary 밖에
transaction state를 쓰는 문제가 생긴다.

별도로 package `Scripts/`에 복사한 manager/manifest가 immutable payload와 다른
byte일 수 있고, expected slot이 아직 없는 direct upgrade observation이 unreadable로
변환될 수 있었다. 이 경우 update 차단이나 recovery 판단이 정확한 fact가 아니라
script copy/path observation에 의존하게 된다.

## Checks

새 package source에서는 다음을 확인한다.

```sh
make -C runtime-platform host-installation-manager-test
make -C runtime-platform macos-host-package-composer-test
make -C runtime-platform macos-release-package-assembly-test
```

설치 실패 현장에서는 C50 journal과 receipt를 먼저 보며, `services-quiescing`,
`activation-pending`, `activated`, `failed`는 recovery-required state로 취급한다.
`preflight-verified`는 side effect가 없는 상태이므로 retry 가능한 상태와 구분한다.

## Fix

현재 C50 package flow는 다음 순서다.

1. preinstall은 C50 `preflight`만 실행한다. 성공 journal은
   `preflight-verified`이며 service effect가 없다. 이 단계가 만들 수 있는 것은
   C48-declared, Host Installation Manager-owned journal directory뿐이다.
2. Installer가 immutable payload를 쓴 뒤 postinstall이 C32/C33가 선언한 directory와
   boot-console file만 준비한다.
3. `quiesce-services`는 launchctl 전에 `services-quiescing`을 영속화하고,
   성공하면 `activation-pending`으로 전이한다.
4. `activate-release` 뒤 `finalize-services`가 C48-declared services만
   reconcile하고 `completed`를 기록한다.
5. postinstall의 실패 trap은 `recover-installation`을 호출한다. Recovery는 C49로
   exact immutable slot을 다시 증명한 뒤에만 current link/service를 reconcile하며,
   old release나 mutable data를 추측하거나 삭제하지 않는다.

Package verifier는 `Scripts/host-installation-manager`와
`Scripts/installation-manifest.json`이 immutable payload 복사본과 byte-identical인지,
C48 inventory/hash/executable mode가 exact인지 검증한다.

C49 observer와 C50 journal writer는 final path뿐 아니라 모든 existing parent
component도 non-symbolic-link인지 검증한다. 따라서 data root 또는 journal parent가
symbolic link이면 `unreadable`로 남고, preflight retry나 write로 바뀌지 않는다.

VitalServer Helper 0.2.1 direct PKG는 C50 transaction과 별개로 다음 containment를
사용한다.

1. 성공한 `pkgutil --pkgs` exact membership과 present일 때의
   `pkgutil --pkg-info-plist` strict decode로 installed version을 읽는다.
2. receipt absence만 `fresh`로 admit한다. same-version repair, upgrade, downgrade는
   SQLite, proxy, service, contract effect 전에 차단한다.
3. admitted fresh intent만 `targetVersion`과 `intent=fresh`가 있는 schema v2 contract로
   postinstall에 전달한다.
4. postinstall은 target mismatch와 non-fresh intent를 provisioning 전에 거절한다.
5. repository install workflow도 이 preflight 뒤에만 optional install-settings를
   쓴다.

이 containment는 transactional repair/update를 구현한 것이 아니다. Candidate
payload, durable activation intent, compensation, rollback proof가 제공될 때까지
receipt-present Helper package를 열지 않는다.

## Prevention

- Preflight와 service/process effect를 같은 상태로 취급하지 않는다.
- 외부 side effect 전에 crash-recoverable intent state를 먼저 영속화한다.
- Package script는 C50 command를 transport할 뿐 launchd policy를 직접 실행하지
  않는다.
- C48 mutable store는 owner/retention뿐 아니라 expected kind를 선언하고, regular
  file/symlink/unknown을 compatible directory로 바꾸지 않는다.
- Direct version-changing PKG install은 staged Host Updater execution boundary가
  제공되기 전까지 explicit blocked state다.
- Helper direct same-version repair도 candidate activation/rollback proof가
  제공되기 전까지 explicit blocked state다.
- `preflight-verified` retry는 package receipt/release/service가 모두 없고,
  manager가 선언된 journal path 아래에 만든 directory만 compatible일 때만
  `clean-install-retry`로 허용한다. Host Agent/VM data가 하나라도 있으면 explicit
  cleanup이 필요하다.

## Follow-up

- C24 clean-Host install/reboot/uninstall evidence를 실제 signed/unsigned delivery
  target별로 수집한다.
- Version-changing Host platform update executor가 C25–C30/C28/C27 chain에 추가되기
  전에는 direct PKG overwrite를 update path로 열지 않는다.
- Same-release online repair를 in-use final slot overwrite 없이 보장하려면 candidate
  slot/promotion/rollback C50 transition을 별도로 설계·증명한다. 현재 transaction은
  payload failure 뒤 service quiescence 문제를 해결하지만 candidate promotion을
  대체하지 않는다.
