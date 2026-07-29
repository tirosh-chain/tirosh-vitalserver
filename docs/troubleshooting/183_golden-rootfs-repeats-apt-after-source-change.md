# TS-183 Golden rootfs가 소스 변경마다 APT를 다시 실행함

## Symptom

`make dist/dmg/dev/compile`을 반복하면 Ubuntu cloud image는 로컬에 있어도
`apt-get update`와 `apt-get install`이 다시 실행된다. snapshot 서버가 느리면
제품 소스만 변경한 빌드도 APT timeout의 영향을 받는다.

또는 branch를 전환한 뒤 `apt-prepared-rootfs.raw.gz`와 유효한 SHA-256이
존재하는데도 preflight가 `apt_source=network`를 선택하고 Ubuntu snapshot
500/502/503으로 실패한다. 이때 기존 cache stamp가 다른 branch의 package
contract와 일치할 수 있다.

## Cause

기존 `rootfs-base.raw.gz` 캐시 계약에는 APT/OS 입력과 Guest deploy, Docker
image, 제품 소스가 함께 들어 있었다. 따라서 제품 소스가 바뀌면 최종
rootfs 캐시 전체가 stale이 되었고, fresh Ubuntu disk에서 APT 설치부터 다시
수행했다.

APT-prepared cache를 처음 분리한 구현도 artifact를 고정 파일 하나에만
보관했다. 서로 다른 package contract를 가진 branch가 같은 cache slot을
차례로 publish하면 마지막 branch의 artifact와 stamp만 남았다. checksum이
정상이어도 현재 contract와 stamp가 다르면 cache hit이 아니므로 network
APT가 필요했다.

## Fix direction

빌드는 `.tmp/vitalserver-vm-pkg/apt-prepared-rootfs/<contract-fingerprint>/`
아래에 별도 immutable 중간 artifact를 유지한다. 이 artifact는 다음 명시적
입력으로 식별된다.

- `config/vm-build.toml`의 Ubuntu/snapshot 및 VM build 계약
- rootfs 크기
- `rootfs-apt-cache-contract.txt`의 APT 준비 의미
- `rootfs-apt-packages.txt`의 정확한 package 목록

artifact에는 SHA-256 sidecar와 contract stamp가 모두 있어야 한다. 최종
golden-rootfs compile은 두 증명이 현재 입력과 일치할 때만 중간 artifact를
새 disk seed로 복원한다.

Guest는 `/var/lib/vitalserver/rootfs-apt-base.json`을 읽어 snapshot, 필수
package 목록, 실제 설치 version, `dpkg --audit` 결과를 검증한다. 검증에
통과한 경우에만 네트워크 APT 단계를 생략하고, 현재 runId의 APT plan 및
installed proof를 새로 기록한다. proof가 없거나 invalid한 상태를 cache hit로
간주하지 않는다.

Host preflight도 APT source를 `network` 또는 `verified-cache`로 명시적으로
받는다. checksum과 contract를 통과한 seed가 제공된 경우에는
`verified-cache`를 사용하므로 snapshot endpoint probe도 수행하지 않는다.
다른 preflight 검사는 그대로 수행되며, Guest가 cache 내부 proof를 다시
검증한다.

중간 artifact가 없거나 stale이면 기존대로 Ubuntu base에서 APT를 실행한다.
성공한 최종 compile 결과에서 새 중간 artifact, SHA-256, contract stamp를
atomic publish한다.

고정 경로를 사용하던 이전 cache는 checksum과 contract stamp를 먼저 검증한 뒤
stamp가 가리키는 fingerprint 디렉터리로 atomic import한다. 현재 branch의
fingerprint와 다르더라도 해당 cache를 보존하므로 branch를 다시 전환했을 때
재사용할 수 있다. 기존 파일은 자동 삭제하지 않는다.

## Prevention

APT/OS 상태와 제품 배치 상태의 cache identity를 다시 합치지 않는다.
cache 존재 여부만으로 상태를 추정하지 않으며, contract와 checksum, Guest
내부 설치 proof를 모두 검증한다.

서로 다른 contract가 단일 mutable cache slot을 공유하게 하지 않는다. cache
경로는 contract fingerprint로 결정하고, 다른 fingerprint의 artifact를 stale
파일로 덮어쓰거나 현재 compile의 seed로 사용하지 않는다.

APT package 추가·삭제는 반드시 `rootfs-apt-packages.txt`에서 수행한다.
그 변경은 의도적으로 APT-prepared cache를 invalidate한다.

APT source suite, install mode, upgrade guard, package proof 의미를 바꾸는
`prepare-airgap-rootfs.sh` 수정은 `rootfs-apt-cache-contract.txt`도 같은
변경에서 갱신해야 한다. 반면 Guest Tools 설치나 제품 smoke 변경은 이
계약을 바꾸지 않으므로 APT-prepared cache를 invalidate하지 않는다.
