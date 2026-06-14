# ADR 0001: macOS Host Proxy로 VRecorder 원 IP 보존

## 상태

Accepted

## 배경

VitalServer의 Web Monitoring UI에서 `Network Settings`는 Redis의 `ip_<vrcode>` 값을 받아
`http://<ip>`로 엽니다. 이 값은 VRecorder가 Socket.IO `join_vr` event를 보낼 때
VitalServer가 확인한 client IP입니다.

macOS의 container runtime은 Linux container를 직접 macOS kernel 위에서 실행하지 않고,
Linux VM과 port forwarding/NAT 계층을 통해 container port를 노출합니다. Docker Desktop,
OrbStack, Colima 계열은 구현 세부는 다르지만 이 경계를 가집니다.

macOS container runtime에서 VitalServer container port를 직접 publish하면, container 안의
Node.js Socket.IO server는 실제 VRecorder IP 대신 runtime의 gateway/bridge IP를 볼 수
있습니다. 로컬 PoC에서는 host에서 `localhost:8080`으로 접속한 testkit이 container 안에서
`::ffff:192.168.97.1`로 관측됐고, 이 값이 `ip_<vrcode>`에 저장됐습니다.

```json
{
  "selected_ip": "192.168.97.1",
  "selected_source": "remote-address",
  "remote_address": "::ffff:192.168.97.1",
  "trust_proxy": false
}
```

이 현상은 VitalServer application logic이 장비 IP를 잘못 계산해서라기보다, macOS container
runtime의 port forwarding/NAT 경계 이후에 container가 연결을 받기 때문에 발생합니다.

### 관측된 주소를 해석하는 방법

이 문제를 볼 때 헷갈리기 쉬운 점은 `localhost`, macOS host IP, container runtime gateway IP,
VRecorder LAN IP가 모두 “접속 가능한 IP”처럼 보인다는 점입니다. 하지만 `Network Settings`에
저장되어야 하는 값은 반드시 VRecorder 장비의 LAN IP여야 합니다.

| 주소 종류 | 예시 | 의미 | `ip_<vrcode>`에 저장해도 되는가 |
| --- | --- | --- | --- |
| VRecorder LAN IP | `172.31.0.152` | 실제 장비가 네트워크에서 받은 주소 | 예 |
| VitalServer host IP | `172.31.0.146` | macOS 운영 장비의 LAN 주소 | 아니오 |
| browser local loopback | `127.0.0.1`, `localhost` | 브라우저가 실행 중인 PC 자기 자신 | 아니오 |
| container runtime gateway | `192.168.65.1`, `192.168.97.1` | macOS host와 Linux VM/container 사이의 내부 경계 주소 | 아니오 |
| 외부 cloud/proxy IP | `172.67.217.51` | DNS/CDN/cloud relay 등을 거친 경우 보이는 외부 peer | 아니오 |

특히 `127.0.0.1`과 `localhost`는 “현재 요청을 보내는 그 기계 자신”을 뜻합니다. 브라우저가
VitalServer가 설치된 macOS에서 직접 실행되면 `localhost`가 우연히 맞는 접속 주소처럼 보일 수
있지만, 다른 PC에서 접속하면 그 PC 자신을 가리키므로 WebSocket 연결이 실패합니다. 따라서 browser
접속 주소와 VRecorder 장비 주소를 같은 문제로 보면 안 됩니다.

## 문제

container가 보는 `socket.handshake.address`는 이미 NAT 이후의 peer address입니다. SNAT 또는
macOS container runtime의 user-space port forwarding이 source address를 rewrite하면, container
내부의 application은 원래 client IP를 표준 Socket.IO/Node.js API로 복원할 수 없습니다.

### 개념 정리

#### macOS에서 container가 VM을 거치는 이유

Linux container는 Linux kernel의 namespace, cgroup, network stack에 의존합니다. macOS kernel은
Linux container를 직접 실행하지 않으므로 Docker Desktop, OrbStack, Colima 같은 runtime은 macOS
위에 Linux VM을 띄우고 그 안에서 container를 실행합니다.

Apple은 이 VM을 만들 수 있는 API를 두 계층으로 제공합니다.

| 계층 | 역할 |
| --- | --- |
| Hypervisor.framework | vCPU와 memory 같은 낮은 수준의 가상화 primitive 제공 |
| Virtualization.framework | VM configuration, disk, network device 같은 높은 수준의 VM 구성 API 제공 |

이 API들은 VM을 실행하기 위한 기반이지, container connection의 원래 client IP를 application에
되돌려주는 기능이 아닙니다. 원 IP 보존 여부는 Docker Desktop, OrbStack, Colima 같은 runtime이
VM network와 port forwarding을 어떻게 구현하는지에 달려 있습니다.

따라서 “Docker Desktop이냐 OrbStack이냐”가 핵심은 아닙니다. runtime마다 내부 구현과 주소 대역은
다를 수 있지만, macOS host 바깥에서 들어온 연결을 Linux VM 안의 container port로 넘기는 순간
다음 질문이 생깁니다.

1. VM으로 넘길 때 source IP를 그대로 유지하는가?
2. user-space proxy가 새 TCP connection을 열면서 source IP를 runtime gateway로 바꾸는가?
3. container application이 NAT 이전 정보를 읽을 수 있는 공식 API가 있는가?

제품 기능은 이 질문들의 runtime별 답에 의존하면 안 됩니다. Docker Desktop, OrbStack, Colima의
세부 동작은 버전과 설정에 따라 바뀔 수 있고, Apple의 가상화 API 자체가 “container로 들어온
connection의 원래 peer address”를 application에 전달하는 계약을 제공하지 않기 때문입니다.

#### DNAT와 SNAT

container port publish는 보통 목적지 주소를 바꾸는 DNAT와, 필요할 경우 출발지 주소를 바꾸는
SNAT를 포함합니다.

```text
client 172.31.0.152:54321
  -> macOS host 172.31.0.146:8080
  -> runtime port-forward
  -> container 172.x.y.z:80
```

DNAT는 `172.31.0.146:8080`으로 들어온 packet의 목적지를 container의 `:80`으로 바꿉니다.
이것만 일어나면 application은 원래 client IP를 볼 가능성이 있습니다. 그러나 runtime이 VM 경계를
넘기거나 user-space proxy를 쓰면서 source address도 gateway address로 바꾸면 SNAT가 발생합니다.

```text
container에서 보이는 연결:
  remote address = 192.168.97.1

원래 연결:
  client address = 172.31.0.152
```

SNAT 이후 application이 받는 TCP connection에는 이미 `172.31.0.152`가 없습니다. Node.js의
`socket.handshake.address`는 현재 TCP peer를 보여줄 뿐이고, 사라진 원래 source address를
추론하지 않습니다.

#### WebSocket과 Socket.IO에서도 같은 문제가 생기는 이유

VRecorder는 HTTP page를 요청하는 것이 아니라 Socket.IO/WebSocket 연결로 `join_vr` event를
보냅니다. 하지만 WebSocket도 최초에는 HTTP Upgrade request로 시작하고, upgrade 이후에도 같은 TCP
connection 위에서 메시지를 주고받습니다.

```text
HTTP Upgrade request
  -> WebSocket connection
  -> Socket.IO event: join_vr(VR_TEST)
```

`join_vr` payload에는 `vrcode`만 있고, 실제 장비 IP가 별도 필드로 들어오지 않습니다. 그러므로
VitalServer가 저장할 수 있는 IP 후보는 결국 “이 Socket.IO connection의 peer address” 또는
신뢰된 proxy가 전달한 forwarding header입니다. TCP peer address가 이미 runtime gateway로 바뀐
뒤라면, `join_vr` event 처리 시점에는 원래 장비 IP를 알 수 없습니다.

#### 왜 container 안에서 원복할 수 없는가

NAT 이전 정보를 복원하려면 NAT를 수행한 계층의 state가 필요합니다. 하지만 VitalServer container는
그 state를 안정적인 제품 API로 받지 못합니다.

```text
VRecorder
  -> macOS host
  -> runtime port-forward / NAT state
  -> Linux VM
  -> container
```

container 내부에서 route table, interface, Docker network 정보를 읽어도 “현재 container가 어느
network에 붙어 있는지”는 알 수 있지만, “방금 들어온 `join_vr` socket의 NAT 이전 client IP”는 알 수
없습니다.

host에서 packet capture나 runtime 내부 state를 뒤져도 application event인 `join_vr(vrcode)`와
TCP/NAT entry를 안정적으로 묶어야 합니다. 이는 runtime별 내부 구현에 의존하고, timing과 reconnect,
여러 VRecorder 동시 접속, 같은 IP의 여러 `vrcode` 상황에서 깨지기 쉽습니다.

#### 왜 proxy header는 가능한가

macOS host proxy는 NAT 전에 client connection을 직접 받습니다. 이 시점의 `$remote_addr`는 proxy가
본 실제 peer address입니다. proxy가 이 값을 HTTP/WebSocket upgrade request의 header로 명시적으로
전달하면, container 안의 VitalServer는 더 이상 사라진 TCP source를 복원할 필요가 없습니다.

```text
VRecorder 172.31.0.152
  -> macOS host nginx
       X-Real-IP: 172.31.0.152
       X-Forwarded-For: 172.31.0.152
  -> Docker backend
  -> VitalServer
```

이때 header를 아무나 보낼 수 있으면 spoofing 위험이 있으므로, VitalServer는 기본적으로 header를
신뢰하지 않습니다. `VITALSERVER_TRUST_PROXY=1`은 “이 배포에서는 앞단의 host proxy를 trust
boundary로 삼는다”는 명시적 선언입니다. nginx config는 client가 직접 보낸 forwarding header를
그대로 통과시키지 않고 `$remote_addr`로 덮어씁니다.

이 구조에서 중요한 보안 조건은 Docker backend를 외부에 직접 열지 않는 것입니다. backend가
`0.0.0.0:18080`처럼 외부에 노출되면 client가 nginx를 우회해서 container에 직접 접속할 수 있고,
직접 조작한 `X-Forwarded-For` header를 보낼 위험이 생깁니다. 그래서 제품 구성에서는 backend를
`127.0.0.1:18080`에만 bind하고, 외부 장비와 브라우저는 host nginx public port로만 들어오게 합니다.

```text
허용:
  external client -> macOS nginx public port -> 127.0.0.1:18080 backend

차단해야 함:
  external client -> 18080 backend direct
```

원 IP가 사라진 뒤 container 내부에서 다음 방법으로 복원하려는 접근은 제품 기능으로 부적합합니다.

- Docker network interface 또는 route table 조회
- runtime 내부 Linux VM, port-forwarder, vpnkit/bridge state 의존
- conntrack/iptables state를 container나 macOS host에서 역조회
- packet capture 결과를 `vrcode`와 사후 매칭

이 방법들은 runtime 내부 구현에 의존하거나, `join_vr(vrcode)`와 TCP connection을 안정적으로
매핑할 수 없습니다. 또한 macOS 운영 환경과 container runtime 버전에 따라 동작이 달라질 수
있습니다.

## 결정

macOS 제품 구성에서는 Docker backend를 외부에 직접 노출하지 않고, macOS host에서 실행되는 nginx
proxy를 VitalServer의 public edge로 둡니다.

```text
VRecorder / Browser
  -> macOS host nginx :80 또는 :8080
  -> Docker backend 127.0.0.1:18080
  -> VitalServer container :80
```

Docker backend는 loopback에만 publish합니다.

```env
VITALSERVER_BIND_HOST=127.0.0.1
VITALSERVER_HTTP_PORT=18080
VITALSERVER_TRUST_PROXY=1
```

host nginx는 실제 client IP를 확인한 뒤 VitalServer에 forwarding header로 전달합니다.

```nginx
proxy_set_header X-Forwarded-For $remote_addr;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Client-IP $remote_addr;
proxy_set_header Forwarded "for=$remote_addr;proto=$scheme;host=$host";
```

현재 제품 방향에서는 원본 VitalServer가 이 header를 직접 신뢰하지 않습니다. trust boundary는
macOS host nginx와 audit proxy이며, audit proxy가 selected client IP를 계산한 뒤 Redis
`ip_<vrcode>` key를 bounded verify/rewrite로 보정합니다. client가 직접 보낸 forwarding header는
nginx config에서 `$remote_addr`로 덮어씁니다.

### 운영 포트 의미

이 결정 이후 macOS 제품 구성의 포트는 두 계층으로 나뉩니다.

| 계층 | 예시 | 외부 노출 | 용도 |
| --- | --- | --- | --- |
| host proxy public port | `80` 또는 `8080` | 예 | 브라우저와 VRecorder가 접속하는 주소 |
| Docker backend port | `127.0.0.1:18080` | 아니오 | nginx가 내부적으로 VitalServer container에 전달하는 주소 |

VRecorder에는 host proxy public port를 안내해야 합니다. Docker backend port는 설치된 macOS host
내부에서만 사용되는 구현 세부입니다.

### Browser와 VRecorder 접속의 차이

Browser는 Web Monitoring UI와 Socket.IO browser client를 사용합니다. 이때 browser WebSocket은
same-origin으로 연결되어야 합니다. 예를 들어 사용자가 `http://172.31.0.146:8080`으로 접속했다면
browser WebSocket도 같은 origin의 `ws://172.31.0.146:8080/socket.io/...`로 붙어야 합니다.

VRecorder는 `join_vr`을 보내는 장비입니다. VitalServer가 `Network Settings`를 열 때 쓰는 Redis
값은 browser의 IP가 아니라 VRecorder의 IP입니다. 따라서 browser WebSocket 문제가 해결되어도,
VRecorder의 `join_vr` connection source가 runtime gateway로 보이면 `Network Settings`는 여전히
잘못된 주소를 열게 됩니다.

## 결과

장점:

- VRecorder 원 IP가 container runtime NAT 이전의 macOS host boundary에서 보존됩니다.
- VitalServer container는 계속 Docker/Compose로 운영할 수 있습니다.
- 외부 장비는 하나의 macOS host public port만 사용합니다.
- 설치형 배포에서 nginx config와 launchd plist를 함께 제공할 수 있습니다.

단점:

- macOS native 구성요소인 nginx와 launchd가 제품 구성에 추가됩니다.
- Docker Compose만으로는 완전한 운영 구성이 되지 않습니다.
- 설치/업데이트/삭제 시 container와 native proxy를 함께 관리해야 합니다.

## 대안

### Docker published port 직접 사용

구성이 단순하지만 macOS container runtime에서 원 IP가 gateway/bridge IP로 바뀔 수 있습니다.
`Network Settings`가 실제 VRecorder 장비가 아니라 runtime 내부 주소를 열게 됩니다.

### VitalServer를 macOS host에서 직접 실행

원 IP 보존은 가능하지만 Node.js runtime, Redis, file storage, process supervision을 host에 직접
설치해야 하므로 배포와 복구가 복잡해집니다.

### Linux VM bridged network에서 운영

macOS 위에 bridged Linux VM을 두고 그 안에서 Docker를 운영하면 원 IP 보존 가능성이 높습니다.
다만 운영자가 VM network와 Docker runtime을 함께 관리해야 하므로 설치형 macOS 제품의 복잡도가
높아집니다.

### VRecorder가 자기 IP를 event payload로 전송

application layer에서 가장 명확하지만 실제 VRecorder 장비 코드를 수정할 수 없으므로 현재 제약에서
선택할 수 없습니다.

### container runtime 내부 VM/port-forwarder 상태 역조회

비공식 내부 구현에 의존하므로 제품 기능으로 채택하지 않습니다. Docker Desktop, OrbStack,
Colima 등 runtime 업데이트, 권한, 보안 정책에 따라 쉽게 깨질 수 있고, connection과 `vrcode`를
안정적으로 매핑하기 어렵습니다.

## 검증 기준

PoC 또는 운영 검증에서 아래를 확인합니다.

1. Docker backend는 `127.0.0.1:<backend-port>`에만 publish됩니다.
2. 외부 client는 macOS host nginx public port로 접속합니다.
3. `join_vr` log에서 `selected_source`가 `x-forwarded-for`, `x-real-ip`, `forwarded`, 또는
   `x-client-ip` 중 하나입니다.
4. Redis `ip_<vrcode>` 값이 Docker gateway IP가 아니라 VRecorder 장비의 LAN IP입니다.
5. Web Monitoring의 `Network Settings`가 `http://<vrecorder-lan-ip>`를 엽니다.
