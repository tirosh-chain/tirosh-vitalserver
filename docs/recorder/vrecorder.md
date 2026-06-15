# Vital Recorder

이 문서는 VitalServer가 Vital Recorder, 이하 VRecorder, 접속을 어떻게 인식하고 Web
Monitoring UI에 어떤 상태로 표시하는지 정리합니다. 실제 VRecorder client source는 이
repo에 포함되어 있지 않으므로, 아래 내용은 VitalServer server code가 기대하는 호환 동작을
기준으로 합니다. 실제 제품의 송신 event는 장비 접속 로그와 Redis 값으로 검증합니다.

## 동작 기준

### Socket.IO 접속 흐름

VitalServer code 기준으로 VRecorder 호환 client는 Socket.IO로 접속한 뒤 아래 흐름을 수행해야
합니다.

1. `join_vr` event를 `vrcode`와 함께 보냅니다.
2. VitalServer는 해당 socket을 `vrcode` room에 join시키고, 현재 서버 시간을 `dt` event로
   돌려줍니다.
3. VitalServer는 접속 IP를 Redis `ip_<vrcode>`에 저장합니다.
4. VRecorder는 같은 연결에서 `send_data` event를 주기적으로 보냅니다.
5. Web Monitoring은 bed별로 `join_bed`를 보내고, `recv_vr_ipaddr`로 받은 IP를
   Network Settings 대상 주소로 사용합니다.

`join_vr`는 Network Settings IP를 저장하는 서버-side entrypoint입니다. 이 repo 안에서는
실제 VRecorder가 `join_vr`를 emit하는 client code를 확인할 수 없지만, 해당 event가 없으면
`ip_<vrcode>`를 채우는 정상 경로가 사라집니다. UI의 online/offline 판단은 `join_vr` 연결
자체가 아니라 `send_data`로 갱신되는 timestamp를 기준으로 합니다.

### VRecorder 식별 기준

VitalServer code 기준으로 VRecorder의 identity는 IP가 아니라 `vrcode`입니다.

`join_vr(vrcode)`를 받으면 VitalServer는 해당 socket을 `vrcode` room에 join시키고,
Redis에는 현재 접속 주소를 `ip_<vrcode>`로 저장합니다. 따라서 `ip_<vrcode>`는 장비의
고정 식별자가 아니라, 특정 `vrcode`가 마지막으로 등록한 현재 접속 주소입니다.

정리하면 아래처럼 봅니다.

| 관계 | 의미 |
| --- | --- |
| `1 vrcode = 1 VRecorder identity` | VitalServer가 VRecorder를 구분하는 기준 |
| `1 vrcode -> 1 current IP` | `join_vr` 시점의 접속 IP가 `ip_<vrcode>`에 저장됨 |
| `1 vrcode -> N beds` | 하나의 VRecorder가 여러 room/bed data를 보낼 수 있음 |
| `1 IP -> N vrcode 가능` | 같은 host/VM/NAT 뒤에서 여러 `vrcode`가 접속하는 것도 구조상 가능 |

같은 `vrcode`가 다른 IP에서 다시 `join_vr`를 보내면 `ip_<vrcode>` 값은 새 IP로 덮어써집니다.
실제 제품 운영에서는 보통 장비 1대가 `vrcode` 1개를 가지는 것으로 보는 것이 자연스럽지만,
testkit처럼 한 VM에서 여러 virtual recorder를 실행하면 같은 IP에 여러 `vrcode`가 매핑될 수
있습니다.

### Realtime Payload

`send_data` payload는 zlib으로 압축된 JSON입니다. VitalServer가 기대하는 최상위 구조는
아래와 같습니다.

```json
{
  "vrcode": "VR_CODE",
  "ver": "testkit",
  "rooms": {
    "0": {
      "roomname": "BED01",
      "ptcon": 1,
      "recording": 1,
      "dtapp": 1710000000,
      "dtcase": 1710000000,
      "dtstart": 1710000000,
      "dtend": 1710000001,
      "devs": [],
      "trks": []
    }
  }
}
```

VitalServer는 수신 후 `roomname`으로 bed id를 만들고, Redis에 아래 값을 갱신합니다.

| Key | 의미 | UI 영향 |
| --- | --- | --- |
| `ip_<vrcode>` | `join_vr` 처리 시 확인한 client IP | Network Settings 대상 주소 |
| `utime_<vrcode>` | VRecorder 단위 마지막 `send_data` 시각 | VR 관리/목록 참고 값 |
| `utime_<bedid>` | bed 단위 마지막 `send_data` 시각 | bed online/offline 판단 |
| `ptcon_<bedid>` | 환자 연결 여부 | 환자 아이콘, patient filter |
| `dtapp_<bedid>` | VRecorder app timestamp | command menu 활성화 판단 |
| `devs_<bedid>` | 장비 목록과 장비 상태 | device 상태 사각형 |

### UI 상태 표시 기준

#### Bed 상태

| 상태 | 판단 기준 | 표시 | 의미 |
| --- | --- | --- | --- |
| 데이터 없음 | `lastData` 없음 | 끊긴 Wi-Fi 아이콘, `N/A` | 아직 해당 bed 데이터가 들어오지 않음 |
| Offline | `dtEnd + 60 < dtplayer` | 끊긴 Wi-Fi 아이콘, 마지막 수신 후 경과 시간 | 마지막 데이터가 60초 이상 오래됨 |
| Online | `dtEnd + 60 >= dtplayer` | bed 이름과 상태 정보 | 최근 데이터가 들어오고 있음 |
| Command 가능 | `wm_serverNow() >= dtapp` | command menu 활성화 | VRecorder에 원격 명령을 보낼 수 있음 |
| Command 불가 | `wm_serverNow() < dtapp` 또는 offline | command menu disabled | 아직 명령 불가 또는 offline |

끊긴 Wi-Fi 아이콘은 `/static/img/discon.svg`입니다. 상단 toolbar의 Wi-Fi 이미지는 상태 표시가
아니라 online/offline 필터 버튼입니다.

#### Patient status 및 Recording 상태

| 상태 | 판단 기준 | 표시 | 의미 |
| --- | --- | --- | --- |
| Patient present | `ptcon` truthy | 사람 아이콘 | VitalServer가 patient present 상태를 보고함 |
| Patient not present | `ptcon` falsy | 사람 아이콘 없음 | VitalServer가 patient not present 상태를 보고함 |
| Patient not reported | `ptcon` 없음 또는 해석 불가 | 사람 아이콘 없음 | patient 상태를 판단하지 않음 |
| Recording on | `recording` truthy | case 시간 빨간색 | 기록 중 |
| Recording off | `recording` falsy | case 시간 흰색 | 기록 중 아님 |
| Standby | numeric track 없음 | `Waiting for next patient ...` | 데이터는 들어오지만 numeric vital sign 없음 |

#### Device 상태

| 상태 | 판단 기준 | 표시 | 의미 |
| --- | --- | --- | --- |
| Device on | `device.status === "on"` | 파란 사각형, device 이름 | 장비 상태 on |
| Device on typo 호환 | `device.stauts === "on"` | 파란 사각형, device 이름 | upstream 오타 필드 호환 |
| Device off/unknown | `status !== "on"` | 빨간 사각형, device 이름 | 장비 off, 미연결, unknown, 또는 status 누락 |
| Device 없음 | `devs` 없음 또는 빈 배열 | 장비 사각형 없음 | 장비 목록 없음 |

빨간 사각형은 VRecorder 자체가 끊겼다는 뜻이 아닙니다. bed는 online이어도 device status가
`"on"`이 아니면 빨간 사각형이 표시됩니다.

#### Filter 상태

| 상태 | 판단 기준 | 표시 | 의미 |
| --- | --- | --- | --- |
| Filter active | `filts` 있음 | 보라색 사각형, filter 이름 | 필터 적용/표시 |
| Filter 없음 | `filts` 없음 또는 빈 배열 | 필터 사각형 없음 | 필터 없음 |

#### Toolbar Filter

| 상태 | 판단 기준 | 표시 | 의미 |
| --- | --- | --- | --- |
| Offline filter | 상단 Wi-Fi 버튼 `wifi-off` | offline bed만 표시 | 화면 필터 |
| Online filter | 상단 Wi-Fi 버튼 `wifi` | online bed만 표시 | 화면 필터 |
| 전체 보기 | 기본 Wi-Fi 버튼 | 전체 bed 표시 | 화면 필터 없음 |

### Network Settings

Web Monitoring의 Network Settings는 서버 redirect가 아니라 브라우저 JS 동작입니다.

1. Web Monitoring client가 `join_bed(bedid, vrcode)`를 보냅니다.
2. VitalServer가 Redis `ip_<vrcode>`를 읽어 `recv_vr_ipaddr(bedid, ip)`로 보냅니다.
3. 브라우저는 `wm_rooms[bedid].vr_ipaddr`에 IP를 저장합니다.
4. Network Settings 클릭 시 `window.open("http://" + vr_ipaddr)`를 실행합니다.

macOS Docker Desktop에서 Docker published port를 직접 노출하면 VRecorder 원 IP 대신 Docker
gateway IP가 저장될 수 있습니다. 운영 환경에서는 host-level proxy가 실제 client IP를
forwarding header로 전달하고, VitalServer는 `VITALSERVER_TRUST_PROXY=1`일 때만 해당 header를
신뢰합니다.

macOS 제품 구성에서는 Docker backend를 `127.0.0.1:<backend-port>`로만 열고, VRecorder와
브라우저는 macOS host nginx public port로 접속합니다. 이때 Network Settings 검증은
Docker backend port가 아니라 host proxy port를 대상으로 수행합니다.

### Testkit 구현 기준

testkit이 실제 VRecorder처럼 보이려면 아래를 만족해야 합니다.

| 영역 | 필요 동작 |
| --- | --- |
| 접속 등록 | Socket.IO 연결 후 `join_vr` 전송 |
| IP 검증 | `ip_<vrcode>`가 VM 또는 장비의 실제 LAN IP로 저장되는지 확인 |
| Online 표시 | 같은 연결에서 주기적으로 `send_data` 전송 |
| Device 표시 | `devs`에 `status` 값을 명시해 파란/빨간 사각형을 의도적으로 재현 |
| Patient status 표시 | `ptcon` 값을 조정해 patient icon 재현 |
| Command 수신 | `update`, `restart`, `reboot`, `del_bed`, `add_event`, `edit_bed`, `edit_conf` 수신 |
| Network Settings | testkit VM에서 HTTP 상태 페이지를 제공해 `http://<vr_ipaddr>` 접속 검증 |

macOS runtime의 Test 탭에서는 guest compose 안의 `testkit` container가 virtual VRecorder를
생성하고 `http://edge/`로 접속합니다. 이 경로는 Helper/TestKit 제어, VitalServer 수신,
observer 반영을 검증하기 위한 내부 QA 경로입니다.

VM 또는 별도 장비에서 실제 VRecorder network behavior까지 검증할 때는 testkit을 bridged
network로 DHCP LAN IP를 받는 환경에서 실행하고, VitalServer public proxy 주소로 접속합니다.
Network Settings를 눌렀을 때 열린 페이지가 testkit 상태 페이지라면 VitalServer의 `join_vr`
처리, proxy IP 보존, Web Monitoring IP 전달이 함께 검증된 것입니다.

예시:

```sh
uv run vitalserver-testkit stream-recorder \
  --vitalserver-url http://<vitalserver-host>:8080 \
  --vrcode VR_TEST \
  --status-page \
  --status-port 80
```

일반 사용자 권한으로 port `80`을 bind할 수 없는 환경에서는 `--status-port 8080` 같은 대체
port로 상태 페이지를 먼저 확인합니다. 단, Web Monitoring의 Network Settings는 현재 port를
붙이지 않고 `http://<vr_ipaddr>`를 열기 때문에 실제 Network Settings 검증에는 port `80`에서
상태 페이지가 떠 있어야 합니다.

#### 수동 E2E 체크리스트

아래 항목은 실제 VM 또는 장비 network에서 확인합니다. unit/integration test는 Socket.IO
lifecycle과 status page 동작을 검증하지만, 실제 client IP 보존 여부는 배포 network 구성을
통과해야만 확인할 수 있습니다.

| 단계 | 확인 항목 |
| --- | --- |
| VM network | testkit VM이 bridged network에서 DHCP LAN IP를 받음 |
| 접속 | `stream-recorder --status-page --status-port 80`로 VitalServer public 주소에 접속 |
| Redis | `ip_<vrcode>` 값이 Docker gateway가 아니라 VM LAN IP로 저장됨 |
| Web Monitoring | 해당 bed가 online으로 표시되고 최근 `send_data`가 반영됨 |
| Network Settings | 버튼 클릭 시 `http://<vm-lan-ip>`가 열리고 testkit status page가 표시됨 |
| Status JSON | `/status.json`에서 `join_sent`, `server_dt`, management event 이력을 확인 가능 |
