# Architecture

Vital Server Helper는 VitalServer를 더 쉽게 운영하고 지원하기 위한 프로그램입니다.

이 문서는 코드 구조를 설명하지만, 먼저 제품 관점에서 읽을 수 있게 정리합니다. 핵심은
간단합니다. 사용자가 보는 화면, Mac/PC가 맡는 일, VM 안에서 돌아가는 service를 나누고, 각자가 알고 있는 상태만 말하게 합니다.

## 1. 목표

Vital Server Helper는 병원 내부망 가까이에 놓인 작은 운영 장비를 전제로 합니다. 이 장비는
오래 켜져 있어야 하고, 문제가 생겼을 때 상태와 로그를 빠르게 확인할 수 있어야 합니다.

### 1-1. 풀려는 문제

| 필요한 일                      | 구조에서의 대응                                     |
| ------------------------------ | --------------------------------------------------- |
| 병원 내부망 가까이에서 실행    | Mac/PC 같은 host 장비에서 runtime을 관리            |
| Recorder 접속 상태 확인        | observer가 recorder activity를 모아 상태로 제공     |
| 장애 조사 자료 수집            | status, event, log, support bundle을 분리해서 보관  |
| 네트워크가 제한된 환경 지원    | offline update bundle과 검증 절차 제공              |
| OS마다 화면을 새로 만들지 않기 | PWA와 Runtime Control API를 공통 화면/계약으로 사용 |

### 1-2. 실행 방식

현재 사전 검증용 release는 Helper-managed runtime을 중심으로 다룹니다. 이 방식에서는 Helper가 VM, proxy, service, update, recovery를 함께 관리합니다.

이미 운영 중인 VitalServer에 연결하는 `External VitalServer mode`는 지원 예정 범위입니다.
이 방식은 기존 VitalServer를 대체하지 않고, 상태 확인, recorder/bed 관측, 로그/지원 자료 수집을 제공하는 방향입니다.

두 방식은 같은 화면을 사용할 수 있어도 확인할 수 있는 정보가 다릅니다. Helper가 직접
관리하는 VM은 lifecycle까지 볼 수 있지만, 기존 VitalServer에 연결하는 경우에는 연결 대상이 제공한 상태만 믿어야 합니다.

## 2. 전체 그림

Vital Server Helper는 역할을 크게 네 부분으로 나눕니다.

1. 사용자가 보는 화면
2. Mac/PC 같은 host에서 실행되는 관리 기능
3. VM을 실행하고 연결하는 기능
4. VM 안에서 동작하는 VitalServer 주변 service

이렇게 나누는 이유는 단순합니다. 화면은 상태를 보여주고 명령을 요청합니다. Host는 VM과
파일, 권한, proxy 같은 host 일을 처리합니다. VM 안의 service는 VitalServer 주변에서 실제 관측과 저장을 담당합니다.

현장에서 문제가 생기면 “화면이 잘못 보이는지”, “Host가 VM을 다루지 못하는지”, “VM 안 service가 상태를 만들지 못하는지”를 빠르게 나눠 봐야 합니다. 역할을 나누면 장애 위치를 더 빨리 좁힐 수 있고, update나 repair도 필요한 범위만 조심스럽게 다룰 수 있습니다.

### 2-1. 용어

| 용어                | 이 문서에서의 뜻                                         |
| ------------------- | -------------------------------------------------------- |
| Host                | Helper가 설치된 Mac/PC                                   |
| Guest               | Host 안에서 실행되는 Linux VM                            |
| Runtime Control API | 화면과 Helper runtime 사이의 약속된 API                  |
| PWA                 | browser에서 열 수 있는 Runtime Control UI                |
| Observer            | recorder/bed 상태를 읽어 runtime 상태로 정리하는 service |
| 조회용 상태         | UI가 읽기 좋게 정리된 상태 문서나 저장소                 |

### 2-2. 구성 요소

```text
PWA / Helper app
  -> Runtime Control API
      -> Host runtime
          -> VM
              -> Linux guest services
                  -> Vital Server wrapper
                  -> Redis
                  -> Recorder Ingress
                  -> Recorder Observer
                  -> Product Lab API
```

### 2-3. 아키텍처 분류

Vital Server Helper는 전형적인 단일 application도, service마다 독립 배포와 수평 확장을
전제로 하는 순수 microservices system도 아닙니다.

제품 전체는 아래처럼 정의합니다.

> Vital Server Helper는 Host platform control plane과 Linux Guest product plane을
> 하나의 설치·배포 단위로 제공하는 single-node service appliance입니다. Host 내부는
> Clean Architecture 기반 modular application이고, Guest 내부는 독립 process와
> container로 구성된 service-oriented stack입니다.

| 관점 | 현재 분류 | 의미 |
|---|---|---|
| 제품 형태 | Single-node service appliance | 한 대의 Mac/PC에 설치되는 현장 운영 제품 |
| 배포 구조 | Single-release distributed modular system | Host와 Guest가 분리되지만 하나의 Helper release로 전달 |
| Host runtime | Modular application | Platform Agent와 operation workflow를 module/layer로 분리 |
| Host 코드 | Clean Architecture / Ports and Adapters | Domain 판단과 Host side effect를 분리 |
| Guest runtime | Service-oriented container stack | 역할별 process/container와 API를 사용 |
| 운영 제어 | Platform control plane + Runtime control plane + Data plane | Host 관리, Guest service 관리, Recorder traffic을 분리 |
| 상태 관리 | Explicit state ownership | 상태마다 authoritative provider를 지정 |
| 가용성 | Single-node self-healing | 자동 재시작과 rollback은 제공하지만 HA cluster는 아님 |

Guest의 Recorder Ingress, VitalDB Observer, Product Lab, Recorder Recovery, Redis Relay는
각각 process/container, API, health check와 책임 경계를 가지므로 microservice-style
component라고 부를 수 있습니다. 하지만 현재 제품은 다음 이유로 전체를 순수
microservices architecture라고 부르지 않습니다.

- Guest service가 하나의 VM과 Compose stack에 배치됩니다.
- 하나의 Helper release와 VM appliance로 함께 전달됩니다.
- Guest stack lifecycle을 Runtime Controller와 Compose가 함께 관리합니다.
- Redis와 PostgreSQL 같은 기반 저장소를 여러 product component가 사용합니다.
- service별 독립 배포와 autoscaling이 기본 운영 모델이 아닙니다.
- Host 또는 VM 한 대의 장애가 전체 제품 가용성에 영향을 줍니다.

따라서 문서에서는 아래 표현을 기준으로 사용합니다.

> Guest는 service-oriented architecture이고 각 component는 microservice-style boundary를
> 가집니다. 제품 전체는 single-node appliance로 패키징된 distributed modular system입니다.

Repository root `compose.yaml`은 개발과 검증을 위한 sandbox입니다. 설치 제품의 기준
service stack은 Linux Guest의 Compose와 Guest Runtime Controller이며, root Compose를
설치 제품 topology로 해석하지 않습니다.

### 2-4. Control plane과 data plane

```text
Operator / Browser
  -> Helper UI / Runtime Control PWA
      -> Platform Agent API
          +-- /platform/* -> Host state and Host workflows
          +-- /runtime/*  -> Runtime gateway
                                -> Guest Runtime Controller
                                    -> Guest service and operation owners

VRecorder
  -> Mac host nginx
      -> Guest edge nginx
          -> Recorder Ingress
              +-- raw archive
              +-- Redis spool / controlled replay
              +-- VitalServer
```

Platform control plane은 Host의 VM, process, filesystem, package, endpoint와 operation을
관리합니다. Runtime product control plane은 Guest service와 Product Lab operation을
관리합니다. Data plane은 Recorder packet을 받아 archive, spool, replay와 VitalServer
처리로 전달합니다.

세 plane의 성공과 실패는 서로 대신하지 않습니다. Platform Agent가 정상이어도 Recorder
packet 처리가 성공했다는 뜻은 아니며, Recorder packet이 들어왔다고 Guest service control이나
Host operation이 정상이라고 판단하지 않습니다.

### 2-5. 누가 무엇을 하나

| 구성 요소            | 하는 일                                                          |
| -------------------- | ---------------------------------------------------------------- |
| PWA / Helper app     | 운영자가 보는 화면을 제공                                        |
| Runtime Control API  | 화면이 runtime 상태와 명령을 같은 방식으로 다루게 함             |
| Host runtime         | VM, proxy, 파일, 권한, update, recovery를 관리                   |
| VM                   | VitalServer 주변 service가 같은 Linux 환경에서 실행되게 함       |
| Linux guest services | Redis, observer, recorder ingress, Product Lab, Vital Server wrapper 실행 |

각 구성 요소는 자기 일이 아닌 상태를 추측하지 않습니다. 예를 들어 화면은 recorder 상태를 직접 만들지 않고, API가 제공한 상태를 표시합니다. Host도 Guest 내부 상태를 로그나 파일명으로 짐작하지 않고, Guest가 제공한 상태 문서를 읽습니다.

### 2-6. 명령이 내려갈 때

운영자가 시작, 중지, update, repair 같은 명령을 누르면 흐름은 아래처럼 내려갑니다.

```text
화면
  -> Runtime Control API
      +-- Platform command
      |     -> Host workflow
      |         -> VM / launchd / filesystem / proxy
      |
      +-- Runtime product command
            -> Guest Runtime Controller
                -> Guest service / Product Lab adapter
```

화면은 명령을 요청하고 owner가 제공한 operation 결과를 보여줍니다. VM, launchd, Host
filesystem 같은 platform effect는 Host workflow가 수행합니다. Guest service start/stop,
stack reconcile과 Product Lab operation은 Guest Runtime Controller가 수행합니다.

### 2-7. 상태가 올라올 때

상태는 하나의 통합 snapshot에서 만들어지지 않습니다. 각 owner resource가 자기 상태를
제공하고 Runtime Control API가 owner 경계를 유지한 채 화면에 전달합니다.

```text
Host live providers + Host SQLite
  -> Platform Agent /platform/*

Guest control ledger + Guest service adapters
  -> Guest Runtime Controller /runtime/*

VitalDB observer
  -> Guest PostgreSQL read model
      -> Guest Runtime Controller /runtime/vitaldb/*

Platform and Runtime resources
  -> Runtime Control UI
```

상태가 없다는 것과, 읽기에 실패했다는 것과, 값이 오래되었다는 것은 다른 의미입니다.
그래서 Helper는 missing, failed, stale, empty 같은 상태를 서로 바꾸지 않습니다.

### 2-8. 이렇게 나누는 이유

| 나눈 것                | 얻는 점                                                                    |
| ---------------------- | -------------------------------------------------------------------------- |
| 화면과 runtime         | PWA, Helper app, remote console이 같은 API를 쓸 수 있음                    |
| Host와 Guest           | macOS/Linux/Windows 차이가 VM 안 service로 새지 않음                       |
| VM 실행과 service 실행 | Apple Virtualization, KVM/QEMU, Hyper-V 차이를 host 쪽에 가둘 수 있음      |
| 상태 생산과 표시       | UI가 상태를 임의로 만들지 않음                                             |
| 판단과 실행            | update, recovery, repair를 테스트 가능한 판단과 실제 실행으로 나눌 수 있음 |

예를 들어 화면에서 recorder가 stale로 보일 때 UI가 직접 ping을 날려 상태를 바꾸면 원인을 추적하기 어려워집니다. 대신 observer가 관측한 activity와 runtime 상태 자료를 API가 전달하고, 화면은 그 결과를 그대로 보여줍니다. 이렇게 하면 “관측이 없어서 stale인지”, “관측 자료를 읽지 못해서 failed인지”를 분리해서 볼 수 있습니다.

## 3. Guest

Guest는 VM 안에서 실행되는 Linux 환경입니다. Linux VM은 host OS를 Linux로 한정하기 위한 선택이 아닙니다. macOS, Linux, Windows host 위에서도 같은 service 묶음을 실행하기 위한 기준점입니다.

### 3-1. Linux VM을 쓰는 이유

| 이유                | 설명                                                                      |
| ------------------- | ------------------------------------------------------------------------- |
| 같은 실행 환경      | host OS가 달라도 같은 service 묶음을 실행할 수 있음                       |
| service 운영에 적합 | Docker/Compose, nginx, Redis, Node service를 같은 기준으로 묶기 쉬움      |
| headless 운영       | systemd, journald, permission, network 설정이 service 운영에 익숙함       |
| update 재현성       | rootfs, cloud-init, Docker image bundle, offline update bundle과 잘 맞음  |
| 입력 명시화         | storage path, Redis host, CPU count, credential 같은 값을 명시적으로 넘김 |

VM을 쓰면 구조가 조금 무거워지지만, 현장마다 다른 host OS 차이를 줄일 수 있습니다. VitalServer 주변 service를 같은 Linux 환경에서 실행하면 Redis, proxy, observer, log 수집 방식을 더 일정하게 가져갈 수 있습니다. host가 macOS인지 Windows인지는 VM을 실행하고 연결하는 쪽의 문제로 남기고, guest 안의 service 묶음은 최대한 같은 방식으로 유지합니다.

### 3-2. VitalServer 연결 입력

Vital Server Helper는 VitalServer가 제공하는 데이터 수집 기능을 전제로 합니다.
Helper는 그 주변 운영에 필요한 입력을 명시적으로 연결합니다.

| 입력               | 의미                                                      |
| ------------------ | --------------------------------------------------------- |
| 시작 방식          | service를 어떤 명령으로 시작할지 정함                     |
| 실행에 필요한 구성 | Node, Redis, proxy, 보조 service 같은 실행 의존성         |
| 저장 위치          | `.vital` 파일이 저장되는 위치                             |
| 컨테이너 실행 묶음 | guest 안에서 VitalServer를 일관된 방식으로 실행           |
| 실행 전 입력       | Redis host/port, CPU count, admin password 같은 실행 입력 |

Linux VM은 VitalServer 자체의 목적을 바꾸기 위한 선택이 아닙니다. 현장에서 같은 운영 표면을 제공하기 위한 실행 경계입니다.

### 3-3. Guest 경계

Guest는 Host가 제공한 설정과 약속된 입력을 사용합니다. Host는 Guest 내부를 추측하지 않고, Guest가 만든 상태 문서와 API 응답만 읽습니다.

## 4. Host

Host는 Helper가 설치된 Mac/PC입니다. Host는 VM 실행, 설치, 권한, proxy, update entrypoint를 담당합니다.

### 4-1. Host별 맡는 일

| Host    | 강점                                                         | 맡는 일                                                                    |
| ------- | ------------------------------------------------------------ | -------------------------------------------------------------------------- |
| macOS   | Mac 장비, DMG/PKG, launchd, Apple Virtualization, Helper app | VM 시작/중지/복구, host proxy, 권한, file picker, update/recovery          |
| Linux   | KVM/QEMU/libvirt, systemd, server-friendly network           | VM 시작/중지/복구, network bridge/NAT, service manager, filesystem sharing |
| Windows | AD/GPO/Intune/SCCM, Windows Service, Hyper-V, firewall 정책  | VM 시작/중지/복구, Windows Service, firewall/NAT, 기업 관리 도구 연동      |

### 4-2. Mac부터 보는 이유

현재 macOS runtime package는 Mac mini/Mac Studio 계열을 1차 검토 대상으로 둡니다. Mac이 모든 서버 요구에 더 적합하다는 뜻은 아닙니다. 초기 검토와 검증 범위를 줄이기 위한 선택입니다.

| 이유               | 설명                                                                                        |
| ------------------ | ------------------------------------------------------------------------------------------- |
| 장비 종류가 제한적 | CPU, storage, network, thermal profile 조합을 줄일 수 있음                                  |
| 반복 검증이 쉬움   | 같은 하드웨어 계열에서 설치, update, 장애 대응 절차를 반복 확인하기 쉬움                    |
| 작은 장비          | 별도 rack 없이 배치 가능한 소형 장비                                                        |
| host 기능 통합     | Helper app, local proxy, packaging, permission, VM 시작/중지/복구를 같은 host 기준으로 다룸 |

Mac을 먼저 본다는 것은 최종 platform을 Mac으로만 제한한다는 뜻이 아닙니다. 초기에는 장비 종류와 OS 조합을 줄여 설치, update, sleep prevention, 권한, VM 실행 문제를 반복해서 검증하는 것이 더 중요합니다. 이 범위가 안정되면 같은 구조를 Linux나 Windows host로 옮길 때 어느 부분이 host별 차이인지 더 명확히 볼 수 있습니다.

### 4-3. Host 선택의 경계

중앙 인프라, 대규모 HA, redundant PSU, ECC memory, hot-swap storage, IPMI/iDRAC class 원격 관리, rack mounting, server vendor SLA가 핵심 요구라면 전통적인 server 또는 industrial PC가 더 적합할 수 있습니다.

macOS 자체는 주된 선택 이유가 아닙니다. macOS는 Mac 하드웨어 위에서 Helper app과 host runtime을 구동하기 위한 운영 환경입니다.

## 5. UI

UI는 운영자가 상태를 보고 명령을 실행하는 표면입니다. Vital Server Helper는 PWA를 사용해 host OS마다 같은 화면을 제공하려고 합니다.

### 5-1. PWA를 쓰는 이유

| 이유                 | 설명                                                                     |
| -------------------- | ------------------------------------------------------------------------ |
| 같은 화면            | macOS/Linux/Windows마다 화면을 새로 만들지 않아도 됨                     |
| local/remote 확장    | local runtime control과 remote console을 같은 API 뒤에 둘 수 있음        |
| 현장 접근성          | Mac 앞이 아니라 병원 내부 PC, tablet, phone browser에서도 상태 확인 가능 |
| native app 책임 축소 | Helper app은 설치, 권한, file picker, recovery 같은 host 기능에 집중     |

PWA를 선택하면 화면과 host 기능을 분리할 수 있습니다. 화면은 Runtime Control API를 통해 상태와 명령을 다루고, Helper app은 Mac에서만 필요한 설치, 권한, 파일 선택, 복구 기능에 집중합니다.
이렇게 해야 나중에 remote console이나 다른 host UI가 필요해져도 같은 API 뒤에서 확장할 수 있습니다.

### 5-2. Runtime Control API 역할

Runtime Control API는 UI와 runtime 사이의 약속입니다. UI는 observer container나 Guest 내부를 직접 읽지 않고, Runtime Control API가 제공한 상태를 표시합니다.

## 6. 코드 경계

코드도 같은 원칙을 따릅니다. 상태를 만드는 곳, 판단하는 곳, 실제 실행하는 곳을 나눕니다.

### 6-1. Layer 책임

| 코드 영역           | 쉬운 설명                                               |
| ------------------- | ------------------------------------------------------- |
| Contracts           | 주고받는 문서와 상태의 모양을 정함                      |
| Domain/Core         | 완전한 입력을 받아 판단 규칙을 계산                     |
| Application/Usecase | 어떤 명령과 결과가 필요한지 결정                        |
| Workflow            | update, recovery 같은 긴 작업의 순서와 진행 상태를 관리 |
| Adapters            | API, 파일, process, network 같은 바깥 세계와 연결       |
| Bootstrap           | 앱이 시작될 때 필요한 설정, 경로, 구현 연결을 묶음      |
| Hosts               | process 시작, signal, host 파일 같은 실행 경계를 연결   |

### 6-2. 경계 규칙

상태는 임의로 판단하지 않습니다. 상태 소유자가 제공한 state, event, document, command result만 사용합니다. missing, invalid, failed, stale, empty는 서로 다른 의미로 유지합니다.

Domain/Core는 파일, process, network, log를 직접 읽지 않습니다. 실제 실행은 Adapter나 Host 경계에서 수행합니다. UI는 domain state를 만들지 않고, 받은 상태를 사람에게 읽기 좋게 보여줍니다.

## 7. 관리 데이터와 lifecycle

Vital Server Helper가 다루는 데이터는 모두 같은 종류가 아닙니다. Command guard와 recovery에
사용하는 authoritative state, 조회를 위한 read model, 장애 분석용 diagnostics, Guest boot를
위한 generated contract, 사용자가 보존하려는 `.vital` 파일을 분리해야 합니다.

파일이 같은 directory에 있거나 같은 database engine을 사용한다는 이유만으로 같은 owner가
되는 것은 아닙니다. 예를 들어 Guest `control.sqlite`는 Host shared mount에 물리적으로
있지만 Guest Runtime Controller가 소유합니다. Host는 그 DB를 열어 operation state를 만들지
않고 Guest Control API를 소비합니다.

### 7-1. 데이터 지도

| 데이터 | 상태 소유자와 저장소 | 생성·갱신 | 보존·삭제 | Backup 범위 |
|---|---|---|---|---|
| Host authoritative runtime state | Platform Agent와 Host `runtime-state.sqlite` | install/schema migration에서 생성하고 VM lifecycle, runtime endpoint, operation lease, workflow, Host settings를 owner transaction으로 갱신 | Helper/Platform Agent 재시작과 VM 재부팅을 넘어 유지. Clean/force-clean uninstall의 managed runtime 제거 대상 | 전체 DB 파일을 복원 state로 추정하지 않음. VitalServer backup은 명시된 Host config artifact만 복구 |
| Live Host resource state | launchd, process table, filesystem, package receipt, network listener 같은 실제 provider | 해당 resource 생성·시작·종료 시 바뀜 | stop/uninstall workflow가 resource별 완료를 검증. DB row만으로 존재를 만들거나 삭제를 증명하지 않음 | 물리 resource 자체는 backup 대상이 아님. 필요한 설정만 artifact로 보존 |
| Generated boot contracts | Host settings owner에서 생성한 VM/Guest config, runtime settings, host time, deploy input | install, configure, boot materialization에서 encode/decode와 revision을 검증한 뒤 생성 | 다음 materialization에서 명시적으로 다시 생성. current settings/status fallback으로 사용하지 않음 | VM config, Guest config/settings 등 manifest가 지정한 required artifact를 보존 |
| Host diagnostics와 logs | Host status/event/log writer, JSON/JSONL, diagnostics SQLite index | install/update/watchdog/command/log collection 과정에서 append 또는 projection | event는 size rotation, managed log archive는 설정한 기간·용량으로 prune. Current health owner가 아님 | 일부 status/event/observability artifact는 optional diagnostics context |
| Guest operation ledger | Guest Runtime Controller와 Guest `control.sqlite` | command accept 시 operation/event/lease를 transaction으로 기록하고 terminal transition에서 event와 lease release를 함께 기록 | Controller/VM restart를 넘어 유지. Restart 중 accepted/running operation은 `interrupted`로 전이. Managed runtime 제거 시 함께 제거 | 현재 VitalServer backup artifact 목록에 포함되지 않음 |
| Guest VitalDB read model | Guest observation writer와 PostgreSQL | VitalDB observation snapshot, Recorder/Bed activity, relationship history를 explicit observation에서 projection | Hide는 visibility만 바꿈. Permanent delete는 tombstone과 public read-model exclusion을 적용 | 현재 VitalServer backup artifact 목록에 PostgreSQL data는 없음 |
| Product Lab aggregate | Product Lab service와 PostgreSQL | Scenario session 생성 시 session, recorder, bed를 하나의 owner aggregate로 저장하고 start/stop으로 상태 갱신 | Session delete가 execution을 멈춘 뒤 owned recorder/bed와 함께 atomically 삭제. VitalDB delete는 Lab ownership이 명시된 경우 이 cleanup을 먼저 수행 | 현재 VitalServer backup artifact 목록에 Lab/PostgreSQL data는 없음 |
| VitalServer/Recorder Redis data | VitalServer, Recorder Ingress와 Guest Redis | VitalServer key/value, ingress spool, replay/dead-letter/audit data를 각 owner contract로 기록 | Replay/trim/repair policy에 따라 갱신. Empty queue와 Redis read failure를 구분 | VitalServer backup과 Redis-only recovery가 명시적으로 포함 |
| Recorder raw archive와 recovery state | Recorder Ingress bind-mounted append-only JSONL과 recovery job/checkpoint | `send_data` 원본 append가 성공한 뒤 hot-path sampling과 별개로 보존 | 기본 active file 512 MiB, 최대 24개 rotation. Export/upload 실패나 shutdown backlog가 있으면 다음 recovery를 위해 보존 | 현재 VitalServer backup artifact 목록에 포함되지 않음 |
| `.vital` library | 설정된 Host directory를 Guest에 mount하고 VitalServer upload/library contract가 관리 | Upload는 batch 전체를 검증한 뒤 commit. Raw archive recovery는 `.vital`을 만들고 VitalServer upload API로 등록 | 사용자가 삭제하거나 uninstall data policy가 적용될 때까지 유지. Lab은 mount 밖 path를 읽지 않음 | 현재 VitalServer backup artifact 목록에 포함되지 않음 |
| Managed backup artifact | Host backup workflow와 managed backup directory | Manifest, compatibility, required artifact, checksum을 검증한 뒤 성공 artifact로 게시 | Automatic backup은 설정된 보관 개수로 오래된 VitalServer backup을 prune. 수동 delete는 선택된 managed path만 허용 | 그 자체가 restore unit이며 Redis-only archive와 의미가 다름 |
| Secrets | Platform/Runtime credential owner와 root-only 또는 Guest secret store | install 또는 명시적인 secret replace/clear command에서 생성·변경 | API에는 secret 존재 여부만 노출하고 값은 노출하지 않음. Clean uninstall은 Helper-managed secret을 제거 | Backup 포함을 추정하지 않으며 manifest가 명시하지 않은 secret은 restore하지 않음 |
| Build/release artifact | Build/packaging tool과 release manifest | Host compile이 rootfs, container image bundle, PKG/DMG/update bundle과 proof를 생성 | 설치 대상은 검증된 immutable artifact를 소비하며 Guest가 누락 artifact를 pull/build하지 않음 | Runtime user backup과 별개인 delivery artifact |

현재 VitalServer backup이 모든 persistent data를 보존하는 것은 아닙니다. 명시된 restore unit은
Guest Redis data와 VM/Guest/proxy/start-on-boot 같은 required Host configuration artifact입니다.
Guest PostgreSQL, Product Lab session, Guest control ledger, `.vital` library, Recorder raw archive와
secret은 현재 backup manifest에 포함된 것으로 추정하면 안 됩니다. 상세 계약은
[Backup/Restore 계약](backup-restore-contracts.md)을 봅니다.

### 7-2. 제품 lifecycle에 따른 데이터 변화

```text
Build
  -> Install / provision
      -> Boot materialization
          -> Runtime operation
              -> Backup / update / recovery
                  -> Standard uninstall or clean/reset
```

#### Build

Build machine이 rootfs, container image bundle, Guest deploy material, Host executable과
PKG/DMG를 생성하고 receipt와 smoke proof를 남깁니다. 이 artifact는 runtime state가 아니며,
Guest가 boot 중 누락된 image나 package를 network에서 보충하지 않습니다.

#### Install과 provision

Installer가 product directory, Host SQLite schema, VM disk, generated config, secret,
launchd service를 만듭니다. Package 설치 완료는 service start 요청이 끝났다는 뜻이며,
VitalServer ready를 뜻하지 않습니다. Platform Agent, VM provider와 Guest Runtime Controller가
각자 상태를 게시한 뒤에만 UI가 해당 owner의 ready를 표시할 수 있습니다.

#### Boot materialization

Platform Agent와 VM provider가 Host settings revision을 읽고 Guest boot input을 생성합니다.
Guest는 이 입력을 검증한 뒤 systemd와 Compose stack을 시작합니다. Generated JSON은 이 단계의
입력 또는 proof이며, Host SQLite나 Guest API가 제공할 current state를 대신하지 않습니다.

#### Runtime operation

Recorder traffic은 ingress에서 raw archive와 Redis spool로 분기되고, bounded replay를 통해
VitalServer로 전달됩니다. Observer 결과는 Guest/PostgreSQL read model에 projection됩니다.
Product Lab command는 Lab/PostgreSQL aggregate와 Guest operation ledger에 각각 자기 상태를
기록합니다. UI는 이 저장소를 직접 읽지 않고 Platform 또는 Runtime API를 사용합니다.

#### Backup, update와 recovery

Backup은 operation lease를 획득하고 manifest가 선언한 artifact만 수집합니다. Update는 적용 전
compatibility와 artifact를 검증하고, Guest activation과 Host health proof가 끝난 뒤 terminal
success를 기록합니다. 실패하면 원래 failure와 rollback result를 별도로 보존합니다. Restore도
호환성 검증이 끝나기 전에 일부 파일을 먼저 적용하지 않습니다.

#### 삭제와 uninstall

Hide는 delete가 아닙니다. Hide는 visibility state만 바꾸고 owner aggregate를 유지합니다.
Permanent delete는 해당 owner command가 성공한 뒤 public read model과 관계를 정리합니다.
Lab-created Recorder/Bed는 owning Lab session execution과 aggregate를 먼저 정리해야 하며,
dependency failure를 이미 삭제된 성공으로 바꾸지 않습니다.

Uninstall mode별 데이터 의미도 다릅니다.

| Mode | 데이터 lifecycle |
|---|---|
| Standard uninstall | Redis data-only backup을 먼저 만들고 logs, managed backups, Redis backups, 기본 Vital files directory를 보존 |
| Clean uninstall | User data를 보존하지 않음. 설정된 external Vital files directory는 configured-path read가 성공한 경우에만 삭제 |
| Force clean/reset | Clean 범위를 제거하고 runtime artifact, launchd state, package receipt, proxy listener 같은 fresh-install blocker까지 검증 |

Standard uninstall이 Guest PostgreSQL, Lab session, Guest control ledger 또는 raw archive를
backup했다는 뜻은 아닙니다. 보존 범위는 문서와 manifest에 명시된 항목만 인정합니다.
Clean uninstall 완료도 fresh-install readiness 성공과 같은 의미가 아니므로, 재설치 가능 여부는
별도의 readiness result로 확인합니다.

### 7-3. 상태와 데이터의 공통 전이 규칙

1. 상태 소유자만 자신의 state를 생성하고 전이합니다.
2. Database metadata와 실제 file/process/device resource 존재는 별도로 검증합니다.
3. Missing, invalid, failed, stale, empty와 zero를 서로 변환하지 않습니다.
4. Read/decode/permission/dependency failure를 empty collection이나 default success로 바꾸지 않습니다.
5. Diagnostics와 generated contract는 current state 또는 recovery input fallback이 아닙니다.
6. Delete, backup, restore, update와 uninstall은 terminal result와 required proof가 있어야 완료입니다.
7. Retention과 cleanup은 owner가 선언한 path와 policy 안에서만 수행하고 외부 데이터를 추정해 삭제하지 않습니다.
