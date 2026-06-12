# Golden Rootfs Compile RCA 보고서

> 작성일: 2026-06-12  
> 영역: macOS runtime packaging / Apple Virtualization / Linux guest rootfs  
> 상태: `dd232365 Stabilize golden rootfs VM compile`에서 해결 확인  
> 관련 문서: `TS-069`, `TS-070`

## 문서 목적과 독자

이 문서는 `make dist/dmg/dev/compile`의 golden rootfs compile 실패를 공식적으로 기록하기 위한 RCA입니다. 단순한 troubleshooting 절차가 아니라, 왜 실패가 Docker/Guest/seccomp 문제처럼 보였는지, 어떤 증거로 root cause를 storage contract 문제로 좁혔는지, 그리고 앞으로 비슷한 증상을 어떻게 분류해야 하는지를 설명합니다.

### 이 문서를 읽어야 하는 사람

- macOS runtime packaging 또는 VM image build를 수정하는 개발자
- Guest bootstrap, Docker/Compose, rootfs smoke를 수정하는 개발자
- release artifact 검증이나 CI compile failure를 triage하는 담당자
- Apple Virtualization.framework 기반 VM runtime을 처음 보는 주니어 개발자

### 이 문서가 답하는 질문

- 왜 Docker stage에서 터졌는데 Docker가 주 원인이 아니었나?
- 왜 `Illegal instruction`, `Kernel panic`, `EXT4-fs error`가 한 이슈 안에서 같이 나왔나?
- 왜 `/dev/vda1`을 `root=LABEL=cloudimg-rootfs`로 바꿔야 했나?
- 왜 writable root disk는 VirtioBlock이 아니라 NVMe controller로 붙여야 했나?
- 왜 stale `rootfs-ready` marker나 manifest를 proof로 믿으면 안 되나?

## 요약

`make dist/dmg/dev/compile`이 golden rootfs VM 준비 중 반복적으로 실패했습니다. 겉으로 보이는 실패 지점은 대체로 Docker 설치, Docker daemon 시작, Docker image load, Docker smoke, Compose startup 근처였지만, Docker는 주 원인이 아니었습니다.

확인된 주 원인은 **쓰기 가능한 guest root filesystem을 Host VM이 불안정한 storage attachment contract로 제공한 것**입니다.

- writable root disk가 `VZVirtioBlockDeviceConfiguration`으로 attach됨
- guest kernel이 attach 순서에 의존하는 `root=/dev/vda1`로 boot됨
- golden rootfs compile이 apt install, Docker image load, Compose up, cleanup까지 한 VM run 안에서 수행되며 root disk에 큰 write pressure를 만듦

이 조합에서 guest root filesystem integrity가 깨졌고, 그 결과 Guest 내부에서는 EXT4 checksum error, read-only remount, corrupted shared library, userspace illegal instruction, kernel Oops, kernel panic이 번갈아 발생했습니다. 이 때문에 문제가 Guest script, Docker, seccomp, Ubuntu image, timeout, vCPU 문제처럼 보였습니다.

해결은 Host VM storage contract를 명시화하는 방향으로 이루어졌습니다.

- writable root disk를 `VZNVMExpressControllerDeviceConfiguration`으로 attach
- writable root disk attachment에 `cachingMode: .uncached`, `synchronizationMode: .full` 적용
- guest boot root를 `/dev/vda1` 대신 `root=LABEL=cloudimg-rootfs`로 변경
- 기존 persisted runtime config에서 old root token과 unsupported BPF guard를 제거하고 현재 contract로 normalize
- seccomp/BPF는 별도 실제 위험으로 남아 있었기 때문에 explicit compatibility guard로 유지

### 핵심 결론

이 이슈의 핵심은 아래 세 문장입니다.

- Docker와 seccomp는 visible failure surface였습니다.
- 주 원인은 writable rootfs를 제공하는 Host VM storage attachment와 Guest boot identity contract였습니다.
- compile이 성공하려면 rootfs proof가 current run에서 명시적으로 생성되어야 하며, Host가 stale marker나 Guest 내부 증상을 추정해서 성공으로 처리하면 안 됩니다.

## 배경지식

이 섹션은 문제를 처음 보는 사람이 아래 RCA를 따라오기 위해 필요한 공통 배경입니다.

### Host와 Guest

이 제품의 macOS runtime은 Host와 Guest로 나뉩니다.

- Host: macOS process, Apple Virtualization.framework, packaging tool, VM launcher, shared directory, rootfs artifact를 소유합니다.
- Guest: Linux VM 안에서 cloud-init, apt, Docker, Compose, VitalServer service stack을 실행합니다.

중요한 경계는 **Host가 runtime/process/filesystem state를 소유하고, Guest는 Host가 명시적으로 제공한 contract를 소비한다**는 점입니다. Guest가 어떤 상태인지 Host가 로그나 absence로 추정하면 안 됩니다. Guest가 성공했다고 볼 수 있으려면 Guest가 명시적인 proof를 써야 합니다.

### Golden rootfs

golden rootfs는 제품 package에 포함할 Linux VM base filesystem입니다. `make dist/dmg/dev/compile`은 이 rootfs를 그냥 다운로드해서 넣지 않습니다. 실제 VM을 부팅해 air-gapped runtime에 필요한 작업을 수행한 뒤, 성공 proof가 있는 rootfs만 압축합니다.

golden rootfs 준비 과정은 대략 아래와 같습니다.

```text
Ubuntu cloud image
  -> raw disk 변환/resize
  -> VM boot
  -> cloud-init
  -> guest package install
  -> Docker image load
  -> Docker/Compose smoke
  -> rootfs-ready + manifest proof
  -> VM stop
  -> rootfs-base.raw.gz
```

따라서 golden rootfs compile은 단순한 파일 복사가 아니라, **제품 VM image를 실제로 만들어 보는 compile 단계**입니다.

### Root filesystem과 writable disk

Linux guest의 root filesystem은 `/`, `/usr`, `/var`, `/etc`, `/var/lib/docker` 같은 주요 경로를 담습니다. Docker image bundle load와 Compose startup은 특히 `/var/lib/docker`에 많은 metadata와 layer 파일을 씁니다.

root filesystem이 손상되면 증상은 특정 한 곳에서만 보이지 않습니다. 이미 설치된 binary, shared library, Python package, Docker metadata, systemd journal 중 손상된 파일을 먼저 읽는 component가 실패합니다. 그래서 storage 문제가 Docker 문제, Python 문제, systemd 문제처럼 보일 수 있습니다.

### Apple Virtualization storage attachment

Apple Virtualization.framework에서 disk image를 Guest에 보여주려면 Host가 storage device configuration을 만들어야 합니다. 이번 이슈에서 중요한 차이는 아래입니다.

| Attachment | 의미 |
|---|---|
| `VZVirtioBlockDeviceConfiguration` | Virtio block device로 Guest에 노출 |
| `VZNVMExpressControllerDeviceConfiguration` | NVMe controller/device로 Guest에 노출 |
| `VZDiskImageStorageDeviceAttachment` | Host disk image file을 VM storage backend로 연결 |

compile workload는 많은 write를 발생시키므로 writable root disk는 단순히 "파일이 존재한다"만으로 충분하지 않습니다. 어떤 controller로 attach되는지, write caching/synchronization policy가 무엇인지가 compile correctness의 일부입니다.

### Boot identity: `/dev/vda1` vs filesystem label

`root=/dev/vda1`은 Guest 안에서 첫 번째 Virtio block disk의 첫 번째 partition을 root filesystem으로 쓰겠다는 뜻입니다. 이 값은 attach 순서와 device type에 묶입니다.

반면 `root=LABEL=cloudimg-rootfs`는 filesystem label을 기준으로 root filesystem을 찾습니다. 이 방식은 disk가 VirtioBlock에서 NVMe로 바뀌어도 root filesystem identity가 유지됩니다.

```text
old: root=/dev/vda1
new: root=LABEL=cloudimg-rootfs
```

이번 이슈에서 root disk를 NVMe로 바꾸면 Linux device name은 `vda`가 아니라 `nvme0n1` 계열로 바뀝니다. 따라서 boot contract도 device name이 아니라 filesystem label로 바뀌어야 합니다.

### Rootfs proof

Host는 "VM이 부팅된 것 같다"거나 "로그상 여기까지 온 것 같다"를 성공으로 처리하면 안 됩니다. golden rootfs compile의 성공 조건은 Guest가 current run에 대해 명시적으로 기록한 proof입니다.

필수 proof는 아래 성격을 가져야 합니다.

- current runId와 일치하는 `rootfs-ready`
- current runId와 일치하는 `rootfs-runtime-manifest.json`
- Docker/Compose/runtime smoke stage가 passed
- cleanup passed
- VM lifecycle stopped
- 남은 launcher process 없음

이 proof가 없으면 rootfs artifact를 압축하거나 release package에 넣으면 안 됩니다.

## 영향

### 개발과 배포 검증 영향

- DMG/PKG packaging compile이 반복 실패해 개발 및 배포 검증이 막혔습니다.
- 실패가 즉시 드러나지 않고 rootfs wait timeout까지 이어질 수 있었습니다.

### Artifact integrity 영향

- 이전 run의 stale marker/manifest가 남으면 실패한 rootfs를 성공 proof로 오인할 위험이 있었습니다.
- 동일 증상이 Docker, Guest, Host, Ubuntu image 문제처럼 번갈아 보여 원인 식별 시간이 길어졌습니다.
- 이 compile 이슈로 확인된 현장 데이터 손실 사례는 없습니다. 다만 unproven rootfs artifact를 산출물로 오인할 수 있는 build integrity risk가 있었습니다.

## 발생 범위

### 확인된 workflow

문제가 확인된 workflow:

```sh
make dist/dmg/dev/compile
```

### 실패가 발생한 phase

문제가 발생한 compile phase:

```text
golden rootfs VM boot
  -> cloud-init
  -> apt plan/install
  -> Docker service start
  -> Docker image bundle load
  -> Docker smoke
  -> Compose build/up
  -> rootfs-ready proof
  -> rootfs-base.raw.gz compression
```

### 주 원인이 아니었던 항목

주 원인이 아니었던 항목:

- linux/arm64 image architecture mismatch
- vCPU count가 너무 높음
- Docker image bundle 누락
- cloud-init 미실행
- rootfs marker wait 로직 단독 문제

## 관측된 증상

### Command-level failure

대표적인 command failure:

```text
error: timed out waiting for .../data/run/rootfs-ready
error: rootfs runtime manifest is missing
error: VM launcher log shows terminal guest failure while waiting for rootfs marker: pattern='Kernel panic - not syncing'
error: VM launcher log shows terminal guest failure while waiting for rootfs marker: pattern='Internal error: Oops:'
error: VM launcher log shows terminal guest failure while waiting for rootfs marker: pattern='rcu: INFO: rcu_preempt detected stalls'
error: VM launcher log shows terminal guest failure while waiting for rootfs marker: pattern='Remounting filesystem read-only'
```

이 에러들은 Host가 `rootfs-ready` proof를 기다리다가 Guest terminal failure를 감지했거나, Guest가 proof를 쓰지 못한 상태를 의미합니다. 즉 "시간이 더 필요하다"가 아니라 "현재 run이 유효한 proof를 제공하지 못했다"로 분류해야 합니다.

### Guest log pattern

중요한 guest log pattern:

```text
EXT4-fs error
checksum invalid
Aborting journal
Remounting filesystem read-only
Accessing a corrupted shared library
Illegal instruction
Internal error: Oops
Kernel panic - not syncing
seccomp_run_filters
bpf_prog_free
```

### Docker 근처에서 보인 이유

실패가 Docker 근처에서 자주 보였던 이유는 Docker가 가장 먼저 root filesystem에 큰 write pressure를 만들었기 때문입니다.

- `docker-service`
- `docker-image-load`
- `docker-smoke`
- `compose-up`

따라서 이 증상은 Docker가 원인이라기보다, rootfs integrity가 무너진 뒤 Docker가 가장 먼저 피해를 드러낸 경우로 분류해야 합니다.

## 왜 원인 파악이 어려웠나

### 첫 번째 false lead: Docker/seccomp

초기 신호는 Docker와 seccomp를 강하게 가리켰습니다.

- 실패한 이미지 조합 중 Docker 29 / containerd 2.x / runc 1.3 계열이 있었습니다.
- kernel stack에 `seccomp_run_filters`가 보였습니다.
- Docker smoke 직후 `Illegal instruction`이 발생했습니다.
- `systemd-journal`, `systemd-network`, `systemd-resolve` 같은 기본 systemd process에서 Oops가 발생했습니다.

Docker smoke 직후 `Illegal instruction`이 보이면 container image architecture mismatch나 Docker runtime bug를 먼저 의심하기 쉽습니다. 하지만 이 repository의 image bundle은 linux/arm64였고, 같은 Docker 근처 증상이 EXT4 checksum/read-only remount와 같이 나타났습니다.

### 실제로 필요했던 guardrail

이 신호들은 실제 위험 후보였기 때문에 아래 조치가 필요했습니다.

- Ubuntu cloud image와 apt snapshot을 함께 고정
- golden rootfs compile input에서 Docker 29 계열 회피
- Docker smoke와 product Compose service에 `seccomp=unconfined` 명시
- guest kernel command line에 `seccomp=0` 추가
- persisted config에서 unsupported `bpf_jit_enable=...` 제거

이 조치들은 불필요한 우회가 아니었습니다. seccomp/BPF path는 실제로 terminal guest failure 후보였기 때문에, 명시 contract로 남기는 것이 맞았습니다.

### 결정적 전환점: filesystem integrity

하지만 이 조치만으로 실패가 끝나지 않았습니다. 이후에도 다음 신호가 남았습니다.

- `EXT4-fs error`
- `checksum invalid`
- `Aborting journal`
- read-only remount
- 이미 설치된 binary 실행 시 `Accessing a corrupted shared library`

이 신호가 결정적이었습니다. 분류가 "Docker failure"에서 "mutable root disk attachment/integrity failure"로 바뀌었습니다.

## Root Cause

### 원인 문장

Host가 쓰기 가능한 guest root disk를 Virtio block device로 attach했고, guest kernel은 `/dev/vda1`이라는 암묵적인 device name으로 root filesystem을 찾았습니다.

### 왜 contract가 부족했나

이 contract는 golden rootfs compile workload에 충분히 명시적이지 않았습니다.

- `/dev/vda1`은 storage device attach 순서에 의존합니다.
- root disk와 cloud-init seed ISO가 같은 VM storage device 목록에 함께 존재합니다.
- rootfs compile VM은 boot 직후 apt, Docker, Compose 작업을 연속 수행합니다.
- Docker image bundle load와 container metadata write가 root disk에 큰 부하를 만듭니다.

여기서 중요한 점은 `/dev/vda1`이 "root filesystem 자체"를 설명하지 않는다는 것입니다. `/dev/vda1`은 특정 시점에 Linux kernel이 특정 controller와 disk attach 순서를 보고 붙인 device name입니다. Host VM storage 구성이 바뀌면 같은 root filesystem도 다른 device name으로 보일 수 있습니다.

### 실패 전파 방식

이 상태에서 root filesystem integrity가 깨지면 Host는 깨끗한 storage error를 받지 못합니다. Guest는 한동안 계속 실행되며, 손상된 파일을 처음 만지는 component가 실패합니다. 그 component가 Docker일 때는 Docker 문제처럼 보이고, systemd일 때는 kernel/systemd 문제처럼 보이며, Python이나 shell command일 때는 guest tool 문제처럼 보입니다.

아래처럼 failure surface가 달라질 수 있습니다.

| 손상 또는 불안정이 먼저 드러난 위치 | 겉으로 보이는 문제 |
|---|---|
| `/var/lib/docker` metadata | Docker daemon/image load failure |
| shared library | `Accessing a corrupted shared library` |
| systemd process | `systemd-journal`/`systemd-resolve` Oops |
| container runtime syscall path | seccomp/BPF 관련 Oops |
| filesystem journal | EXT4 abort, read-only remount |

정리하면:

> Docker와 seccomp는 눈에 보이는 failure surface였습니다. 주 원인은 writable rootfs storage attachment와 boot identity contract였습니다.

## 증거

### Storage integrity signal

해결 전 실패 run에는 storage integrity 신호가 반복적으로 포함되었습니다.

```text
EXT4-fs error ... checksum invalid
Aborting journal
Remounting filesystem read-only
Accessing a corrupted shared library
```

이 조합은 단순히 어떤 process 하나가 crash한 것이 아니라, root filesystem의 read/write integrity가 이미 깨졌다는 신호입니다. 특히 `Accessing a corrupted shared library`는 "실행하려는 binary 또는 library가 디스크에서 정상적으로 읽히지 않는다"는 의미이므로 Docker command 자체의 logic bug로 축소하면 안 됩니다.

### Device identity signal

해결 후 동일 compile workload에서 guest root disk는 NVMe device로 잡혔고 r/w mount가 유지되었습니다.

```text
nvme nvme0: pci function 0000:00:06.0
nvme0n1: p1 p15 p16
EXT4-fs (nvme0n1p1): mounted filesystem ... r/w
```

이 로그는 두 가지를 동시에 보여줍니다.

- root disk가 더 이상 `vda` 계열이 아니라 `nvme0n1` 계열로 제공됨
- `root=LABEL=cloudimg-rootfs` boot contract가 device name 변경에도 root filesystem을 정확히 찾음

### Proof signal

해결 후 rootfs manifest는 required stage를 모두 통과했습니다.

```text
docker-service: passed
runtime-version: passed
docker-image-load: passed
docker-smoke: passed
disk-space: passed
compose-build: passed
compose-up: passed
edge-ready: passed
cleanup: passed
manifestStatus=passed
```

이 proof가 중요한 이유는 "VM이 안 죽었다"보다 훨씬 강한 검증이기 때문입니다. Docker daemon이 켜졌고, runtime version을 수집했고, Docker image bundle을 실제 load했고, Docker smoke와 Compose smoke를 통과했고, cleanup까지 끝났다는 것을 current run manifest가 증명합니다.

여기서 cleanup은 단순히 `docker compose down`이 성공했다는 뜻이면 부족합니다. rootfs smoke는 Docker image bundle을 실제로 `docker load`하고 Compose build/up을 수행하므로, cleanup proof는 아래 상태까지 검증해야 합니다.

- smoke compose stack이 제거됨
- Docker build cache가 제거됨
- Docker image store에 image가 남지 않음
- Docker container와 volume이 남지 않음
- Docker/containerd runtime service가 rootfs 압축 전에 내려감

이 cleanup이 불완전하면 package 안에 Docker image가 두 번 들어갈 수 있습니다. 하나는 제품 bootstrap/update가 쓰는 `vm/data/deploy/docker-images/vitalserver-images.tar.gz`이고, 다른 하나는 rootfs 내부 `/var/lib/docker`에 남은 loaded image/layer store입니다. 이 경우 pkg 크기가 수백 MB 증가할 수 있고, smoke 시점의 container `StartedAt`이 남으면 설치 직후 UI의 service uptime이 실제 첫 실행 시간이 아니라 rootfs compile 시점 기준으로 표시될 수 있습니다.

### Artifact signal

최종 compile 산출물:

```text
dist/VitalServerHelper-0.1.13-dev.pkg
dist/VitalServerHelper-0.1.13-dev.dmg
```

이 산출물은 rootfs proof가 통과한 뒤 만들어졌습니다. 따라서 이 compile 성공은 단순히 Swift build나 packaging shell이 통과한 것이 아니라, golden rootfs VM run이 검증된 뒤 release artifact가 생성됐다는 의미입니다.

## 해결 내용

해결 commit:

```text
dd232365 Stabilize golden rootfs VM compile
```

### Host VM storage contract

writable root disk:

- `VZDiskImageStorageDeviceAttachment` 사용
- `readOnly: false`
- `cachingMode: .uncached`
- `synchronizationMode: .full`
- `VZNVMExpressControllerDeviceConfiguration`으로 attach

cloud-init seed:

- read-only 유지
- Virtio block device attach 유지 가능

이 구분은 의도적입니다. cloud-init seed는 읽기 전용 ISO이고 compile 중 대량 write를 받지 않습니다. 반면 root disk는 apt, Docker, Compose, cleanup이 모두 쓰는 mutable state입니다. 따라서 root disk에 더 강한 storage contract를 적용하고, seed ISO는 read-only block device로 유지할 수 있습니다.

### Guest boot contract

kernel command line은 filesystem label 기반 root를 사용합니다.

```text
root=LABEL=cloudimg-rootfs
```

기존 값:

```text
root=/dev/vda1
```

기존 persisted runtime config는 다음 규칙으로 normalize합니다.

- `root=...` 제거
- `bpf_jit_enable=...` 제거
- `root=LABEL=cloudimg-rootfs` 추가
- `seccomp=0` 추가

이 normalize는 compatibility fallback이 아닙니다. 기존 unreleased config가 남아 있더라도 현재 VM boot contract로 끌어올리는 migration 성격입니다. Host가 old `/dev/vda1` state를 계속 보존하면 root disk attachment 변경과 boot identity 변경이 서로 어긋납니다.

### macOS support contract

`VZNVMExpressControllerDeviceConfiguration`은 macOS 14.0 이상 API입니다. 따라서 macOS runtime package target과 app minimum system version을 macOS 14.0으로 올렸습니다.

제품 정책상 더 높은 내부 기준을 잡아도 된다면 macOS 15 / Darwin 24+ 기준도 가능합니다. 현재 수정의 기술적 최소 기준은 macOS 14.0입니다.

### Guest runtime compatibility guard

seccomp/BPF는 주 원인은 아니었지만 실제 위험 후보였습니다. 따라서 fallback으로 숨기지 않고 compatibility contract로 명시했습니다.

- guest kernel command line에 `seccomp=0` 포함
- Docker smoke는 `--security-opt seccomp=unconfined` 사용
- product Compose service는 `security_opt: seccomp=unconfined` 선언

이 guard는 root cause를 가리기 위한 workaround가 아닙니다. storage issue를 해결한 뒤에도 Apple Virtualization guest kernel과 container runtime의 seccomp/BPF path는 별도 compatibility surface입니다. 제거하려면 같은 수준의 golden rootfs compile proof와 runtime boot proof가 필요합니다.

## 검증

### 검증 명령

수행한 검증:

```sh
bash -n \
  apps/vitalserver-macos-runtime/Support/Guest/bootstrap.sh \
  apps/vitalserver-macos-runtime/Support/Guest/prepare-airgap-rootfs.sh

.venv/bin/pytest \
  packages/vitalserver-devtools/tests/unit/test_guest_image_usecases.py \
  packages/vitalserver-devtools/tests/unit/test_runtime_lifecycle_wait.py \
  packages/vitalserver-devtools/tests/unit/test_ubuntu_adapter.py \
  packages/vitalserver-devtools/tests/unit/test_rootfs_base.py \
  packages/vitalserver-guest-tools/tests/test_rootfs_smoke.py

swift test --package-path apps/vitalserver-macos-runtime \
  --filter 'GuestCommandDispatcherSupportTests|VMRuntimeConfigTests'

make dist/dmg/dev/compile
```

### 검증 결과

검증 결과:

- Python tests: 75 passed
- Swift focused tests: 29 passed
- `make dist/dmg/dev/compile`: passed
- compile 후 남은 VM launcher process 없음
- DMG/PKG 생성 성공

### 검증 기준

이번 이슈에서 compile success는 아래를 모두 만족해야 합니다.

- Host Swift/Python code가 test를 통과함
- Guest bootstrap shell이 syntax check를 통과함
- golden rootfs VM이 current runId로 `rootfs-ready`를 씀
- manifest가 required stage를 모두 `passed`로 기록함
- VM이 stopped 상태가 됨
- 남은 VM launcher process가 없음
- `rootfs-base.raw.gz`가 proof gate 이후 생성됨
- DMG/PKG가 생성됨

## 예방 규칙

### 1. VM image build는 제품 compile입니다

VM image build는 제품 compile로 취급합니다.

- golden rootfs VM 실패는 local flaky task가 아닙니다.
- CI/local compile은 rootfs proof를 만들지 못하면 명시적으로 실패해야 합니다.

### 2. Docker failure로 빨리 결론내지 않습니다

Docker stage 실패를 곧바로 Docker failure로 분류하지 않습니다.

- EXT4 checksum error, journal abort, read-only remount, corrupted shared library, repeated userspace illegal instruction이 보이면 먼저 mutable root disk integrity failure로 분류합니다.

### 3. Root filesystem은 stable identity로 boot합니다

Mutable rootfs는 attach 순서 기반 device name으로 boot하지 않습니다.

- `/dev/vda1` 같은 값은 product rootfs contract로 사용하지 않습니다.
- `root=LABEL=cloudimg-rootfs`처럼 안정적인 filesystem identity를 사용합니다.

### 4. Old VM disk contract fallback을 추가하지 않습니다

Unreleased old VM disk contract 호환 fallback을 추가하지 않습니다.

- persisted config는 현재 explicit contract로 normalize합니다.
- contract가 없거나 invalid하면 숨기지 말고 실패시킵니다.

### 5. Proof는 current run에 묶습니다

Proof는 반드시 current run에 묶습니다.

- `rootfs-ready`, manifest, apt plan, lifecycle, compressed rootfs output은 같은 runId를 가져야 합니다.
- stale proof는 성공으로 인정하지 않습니다.

### 6. Seccomp/BPF policy는 명시적으로 유지합니다

Seccomp/BPF policy는 explicit contract로 유지합니다.

- 주 원인은 storage였지만 seccomp/BPF도 실제 위험 후보였습니다.
- `seccomp=0` 또는 `seccomp=unconfined` 제거는 별도 compatibility review가 필요합니다.

## 향후 장애 분류 기준

### Evidence table

| Evidence | 우선 분류 |
|---|---|
| `EXT4-fs error`, `checksum invalid`, `Aborting journal` | mutable root disk integrity failure |
| EXT4 error 이후 `Remounting filesystem read-only` | mutable root disk integrity failure |
| `Accessing a corrupted shared library` | rootfs corruption symptom |
| Docker image load/smoke 이후 `Illegal instruction` | Docker image보다 kernel/seccomp/rootfs corruption 먼저 확인 |
| `seccomp_run_filters`, `bpf_prog_free` | guest kernel seccomp/BPF compatibility risk |
| `rootfs-ready`는 있으나 manifest missing/stale | invalid proof; rootfs 압축 금지 |
| 실패 후 VM launcher process 잔존 | mutable runtime files 재사용 금지 |
| pkg 크기가 약 600MB 증가 | `/var/lib/docker`에 smoke image/layer/cache가 남았는지 확인 |
| 설치 직후 service uptime이 수백 일로 표시 | rootfs smoke container/runtime state가 제품 rootfs에 남았는지 확인 |

### Triage order

비슷한 compile 실패가 재발하면 아래 순서로 봅니다.

1. `rootfs-runtime-manifest.json`의 current runId와 stage status를 확인합니다.
2. `launcher.log`에서 EXT4/read-only/corrupted library 신호를 먼저 찾습니다.
3. Docker stage failure가 있어도 storage integrity 신호가 있으면 Docker root cause로 분류하지 않습니다.
4. seccomp/BPF stack이 있으면 compatibility guard가 유지됐는지 확인합니다.
5. VM launcher process가 남아 있으면 mutable runtime files를 재사용하지 않습니다.
6. cleanup proof에서 Docker container/image/volume이 비어 있는지 확인합니다.
7. proof가 current run과 일치하지 않으면 rootfs artifact를 압축하거나 배포하지 않습니다.

## 후속 작업

- `TS-069`는 stale proof, manifest validation, terminal guest failure check의 operational troubleshooting 문서로 유지합니다.
- `TS-070`은 golden disk build와 실제 runtime boot proof 사이의 남은 proof gap을 추적합니다.
- 내부 배포 정책상 가능하면 macOS 15 / Darwin 24+를 제품 baseline으로 올릴지 결정합니다.
- package target이 macOS 14.0+로 올라가면서 발생한 SwiftUI `onChange(of:perform:)` deprecation warning은 zero/two-parameter `onChange` API로 정리했습니다.
