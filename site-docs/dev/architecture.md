# Architecture

Vital Server Helper는 VitalServer를 더 쉽게 운영하고 지원하기 위한 프로그램입니다.

이 문서는 코드 구조를 설명하지만, 먼저 제품 관점에서 읽을 수 있게 정리합니다. 핵심은
간단합니다. 사용자가 보는 화면, Mac/PC가 맡는 일, VM 안에서 돌아가는 service를 나누고,
각자가 알고 있는 상태만 말하게 합니다.

## 1. 목표

Vital Server Helper는 병원 내부망 가까이에 놓인 작은 운영 장비를 전제로 합니다. 이 장비는
오래 켜져 있어야 하고, 문제가 생겼을 때 상태와 로그를 빠르게 확인할 수 있어야 합니다.

### 1-1. 풀려는 문제

| 필요한 일 | 구조에서의 대응 |
|---|---|
| 병원 내부망 가까이에서 실행 | Mac/PC 같은 host 장비에서 runtime을 관리 |
| Recorder 접속 상태 확인 | observer가 recorder activity를 모아 상태로 제공 |
| 장애 조사 자료 수집 | status, event, log, support bundle을 분리해서 보관 |
| 네트워크가 제한된 환경 지원 | offline update bundle과 검증 절차 제공 |
| OS마다 화면을 새로 만들지 않기 | PWA와 Runtime Control API를 공통 화면/계약으로 사용 |

### 1-2. 실행 방식

현재 사전 검증용 release는 Helper-managed runtime을 중심으로 다룹니다. 이 방식에서는
Helper가 VM, proxy, service, update, recovery를 함께 관리합니다.

이미 운영 중인 VitalServer에 연결하는 `External VitalServer mode`는 지원 예정 범위입니다.
이 방식은 기존 VitalServer를 대체하지 않고, 상태 확인, recorder/bed 관측, 로그/지원 자료
수집을 제공하는 방향입니다.

두 방식은 같은 화면을 사용할 수 있어도 확인할 수 있는 정보가 다릅니다. Helper가 직접
관리하는 VM은 lifecycle까지 볼 수 있지만, 기존 VitalServer에 연결하는 경우에는 연결 대상이
제공한 상태만 믿어야 합니다.

## 2. 전체 그림

Vital Server Helper는 역할을 크게 네 부분으로 나눕니다.

1. 사용자가 보는 화면
2. Mac/PC 같은 host에서 실행되는 관리 기능
3. VM을 실행하고 연결하는 기능
4. VM 안에서 동작하는 VitalServer 주변 service

이렇게 나누는 이유는 단순합니다. 화면은 상태를 보여주고 명령을 요청합니다. Host는 VM과
파일, 권한, proxy 같은 host 일을 처리합니다. VM 안의 service는 VitalServer 주변에서 실제
관측과 저장을 담당합니다.

### 2-1. 용어

| 용어 | 이 문서에서의 뜻 |
|---|---|
| Host | Helper가 설치된 Mac/PC |
| Guest | Host 안에서 실행되는 Linux VM |
| Runtime Control API | 화면과 Helper runtime 사이의 약속된 API |
| PWA | browser에서 열 수 있는 Runtime Control UI |
| Observer | recorder/bed 상태를 읽어 runtime 상태로 정리하는 service |
| 조회용 상태 | UI가 읽기 좋게 정리된 상태 문서나 저장소 |

### 2-2. 구성 요소

```text
PWA / Helper app
  -> Runtime Control API
      -> Host runtime
          -> VM
              -> Linux guest services
                  -> Vital Server wrapper
                  -> Redis
                  -> Audit Proxy
                  -> Recorder Observer
                  -> Testkit API
```

### 2-3. 누가 무엇을 하나

| 구성 요소 | 하는 일 |
|---|---|
| PWA / Helper app | 운영자가 보는 화면을 제공 |
| Runtime Control API | 화면이 runtime 상태와 명령을 같은 방식으로 다루게 함 |
| Host runtime | VM, proxy, 파일, 권한, update, recovery를 관리 |
| VM | VitalServer 주변 service가 같은 Linux 환경에서 실행되게 함 |
| Linux guest services | Redis, observer, audit proxy, testkit, Vital Server wrapper 실행 |

각 구성 요소는 자기 일이 아닌 상태를 추측하지 않습니다. 예를 들어 화면은 recorder 상태를
직접 만들지 않고, API가 제공한 상태를 표시합니다. Host도 Guest 내부 상태를 로그나 파일명으로
짐작하지 않고, Guest가 제공한 상태 문서를 읽습니다.

### 2-4. 명령이 내려갈 때

운영자가 시작, 중지, update, repair 같은 명령을 누르면 흐름은 아래처럼 내려갑니다.

```text
화면
  -> Runtime Control API
      -> Host runtime
          -> VM / launchd / filesystem / proxy
```

화면은 명령을 요청하고 결과를 보여줍니다. 실제로 process를 실행하거나 파일을 바꾸거나 VM을
조작하는 일은 Host 쪽에서 처리합니다.

### 2-5. 상태가 올라올 때

상태는 한 줄로 이어지지 않습니다. Runtime 상태 변화와 실패는 status와 event로 남고,
recorder/bed 관측은 별도 activity로 정리됩니다. Runtime Control API는 이 자료를 모아서
화면에 전달합니다.

```text
runtime status + runtime events
recorder/bed activity
  -> Runtime Control API
  -> 화면
```

상태가 없다는 것과, 읽기에 실패했다는 것과, 값이 오래되었다는 것은 다른 의미입니다.
그래서 Helper는 missing, failed, stale, empty 같은 상태를 서로 바꾸지 않습니다.

### 2-6. 이렇게 나누는 이유

| 나눈 것 | 얻는 점 |
|---|---|
| 화면과 runtime | PWA, Helper app, remote console이 같은 API를 쓸 수 있음 |
| Host와 Guest | macOS/Linux/Windows 차이가 VM 안 service로 새지 않음 |
| VM 실행과 service 실행 | Apple Virtualization, KVM/QEMU, Hyper-V 차이를 host 쪽에 가둘 수 있음 |
| 상태 생산과 표시 | UI가 상태를 임의로 만들지 않음 |
| 판단과 실행 | update, recovery, repair를 테스트 가능한 판단과 실제 실행으로 나눌 수 있음 |

## 3. Guest

Guest는 VM 안에서 실행되는 Linux 환경입니다. Linux VM은 host OS를 Linux로 한정하기 위한 선택이
아닙니다. macOS, Linux, Windows host 위에서도 같은 service 묶음을 실행하기 위한 기준점입니다.

### 3-1. Linux VM을 쓰는 이유

| 이유 | 설명 |
|---|---|
| 같은 실행 환경 | host OS가 달라도 같은 service 묶음을 실행할 수 있음 |
| service 운영에 적합 | Docker/Compose, nginx, Redis, Node service를 같은 기준으로 묶기 쉬움 |
| headless 운영 | systemd, journald, permission, network 설정이 service 운영에 익숙함 |
| update 재현성 | rootfs, cloud-init, Docker image bundle, offline update bundle과 잘 맞음 |
| 입력 명시화 | storage path, Redis host, CPU count, credential 같은 값을 명시적으로 넘김 |

### 3-2. VitalServer 연결 입력

Vital Server Helper는 VitalServer가 제공하는 연구와 데이터 수집 기능을 전제로 합니다.
Helper는 그 주변 운영에 필요한 입력을 명시적으로 연결합니다.

| 입력 | 의미 |
|---|---|
| 시작 방식 | service를 어떤 명령으로 시작할지 정함 |
| 실행에 필요한 구성 | Node, Redis, proxy, 보조 service 같은 실행 의존성 |
| 저장 위치 | `.vital` 파일이 저장되는 위치 |
| 컨테이너 실행 묶음 | guest 안에서 VitalServer를 일관된 방식으로 실행 |
| 실행 전 입력 | Redis host/port, CPU count, admin password 같은 실행 입력 |

Linux VM은 VitalServer 자체의 목적을 바꾸기 위한 선택이 아닙니다. 현장에서 같은 운영 표면을
제공하기 위한 실행 경계입니다.

### 3-3. Guest 경계

Guest는 Host가 제공한 설정과 약속된 입력을 사용합니다. Host는 Guest 내부를 추측하지 않고,
Guest가 만든 상태 문서와 API 응답만 읽습니다.

## 4. Host

Host는 Helper가 설치된 Mac/PC입니다. Host는 VM 실행, 설치, 권한, proxy, update entrypoint를
담당합니다.

### 4-1. Host별 맡는 일

| Host | 강점 | 맡는 일 |
|---|---|---|
| macOS | Mac 장비, DMG/PKG, launchd, Apple Virtualization, Helper app | VM 시작/중지/복구, host proxy, 권한, file picker, update/recovery |
| Linux | KVM/QEMU/libvirt, systemd, server-friendly network | VM 시작/중지/복구, network bridge/NAT, service manager, filesystem sharing |
| Windows | AD/GPO/Intune/SCCM, Windows Service, Hyper-V, firewall 정책 | VM 시작/중지/복구, Windows Service, firewall/NAT, 기업 관리 도구 연동 |

### 4-2. Mac부터 보는 이유

현재 macOS runtime package는 Mac mini/Mac Studio 계열을 1차 검토 대상으로 둡니다. Mac이 모든
서버 요구에 더 적합하다는 뜻은 아닙니다. 초기 검토와 검증 범위를 줄이기 위한 선택입니다.

| 이유 | 설명 |
|---|---|
| 장비 종류가 제한적 | CPU, storage, network, thermal profile 조합을 줄일 수 있음 |
| 반복 검증이 쉬움 | 같은 하드웨어 계열에서 설치, update, 장애 대응 절차를 반복 확인하기 쉬움 |
| 작은 장비 | 별도 rack 없이 배치 가능한 소형 장비 |
| host 기능 통합 | Helper app, local proxy, packaging, permission, VM 시작/중지/복구를 같은 host 기준으로 다룸 |

### 4-3. Host 선택의 경계

중앙 인프라, 대규모 HA, redundant PSU, ECC memory, hot-swap storage, IPMI/iDRAC class 원격
관리, rack mounting, server vendor SLA가 핵심 요구라면 전통적인 server 또는 industrial PC가
더 적합할 수 있습니다.

macOS 자체는 주된 선택 이유가 아닙니다. macOS는 Mac 하드웨어 위에서 Helper app과 host
runtime을 구동하기 위한 운영 환경입니다.

## 5. UI

UI는 운영자가 상태를 보고 명령을 실행하는 표면입니다. Vital Server Helper는 PWA를 사용해
host OS마다 같은 화면을 제공하려고 합니다.

### 5-1. PWA를 쓰는 이유

| 이유 | 설명 |
|---|---|
| 같은 화면 | macOS/Linux/Windows마다 화면을 새로 만들지 않아도 됨 |
| local/remote 확장 | local runtime control과 remote console을 같은 API 뒤에 둘 수 있음 |
| 현장 접근성 | Mac 앞이 아니라 병원 내부 PC, tablet, phone browser에서도 상태 확인 가능 |
| native app 책임 축소 | Helper app은 설치, 권한, file picker, recovery 같은 host 기능에 집중 |

### 5-2. Runtime Control API 역할

Runtime Control API는 UI와 runtime 사이의 약속입니다. UI는 observer container나 Guest 내부를
직접 읽지 않고, Runtime Control API가 제공한 상태를 표시합니다.

## 6. 코드 경계

코드도 같은 원칙을 따릅니다. 상태를 만드는 곳, 판단하는 곳, 실제 실행하는 곳을 나눕니다.

### 6-1. Layer 책임

| 코드 영역 | 쉬운 설명 |
|---|---|
| Contracts | 주고받는 문서와 상태의 모양을 정함 |
| Domain/Core | 완전한 입력을 받아 판단 규칙을 계산 |
| Application/Usecase | 어떤 명령과 결과가 필요한지 결정 |
| Workflow | update, recovery 같은 긴 작업의 순서와 진행 상태를 관리 |
| Adapters | API, 파일, process, network 같은 바깥 세계와 연결 |
| Bootstrap | 앱이 시작될 때 필요한 설정, 경로, 구현 연결을 묶음 |
| Hosts | process 시작, signal, host 파일 같은 실행 경계를 연결 |

### 6-2. 경계 규칙

상태는 임의로 판단하지 않습니다. 상태 소유자가 제공한 state, event, document, command result만
사용합니다. missing, invalid, failed, stale, empty는 서로 다른 의미로 유지합니다.

Domain/Core는 파일, process, network, log를 직접 읽지 않습니다. 실제 실행은 Adapter나
Host 경계에서 수행합니다. UI는 domain state를 만들지 않고, 받은 상태를 사람에게 읽기 좋게
보여줍니다.
