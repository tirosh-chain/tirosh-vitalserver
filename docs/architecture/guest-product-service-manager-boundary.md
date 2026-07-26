# Guest Product Service Manager 경계

> 상태: C38 contract·deterministic systemd unit composition과 C40 NoCloud bootstrap-volume composition 구현 완료 / Guest systemd install/start/restart·boot proof는 pending

Linux Guest에서 systemd는 `GuestProductProcessSupervisor`라는 **한 process**의
OS-level service lifetime을 소유한다. Supervisor는 Guest Runtime과 Recorder Gateway
두 required process의 product lifetime을 소유한다. 이 두 역할을 같은 `service` 또는
generic `launcher`로 합치지 않는다.

```text
C38 GuestProductServiceManagerDeploymentConfiguration
  └─ systemd unit (Guest OS service manager desired configuration)
      └─ GuestProductProcessSupervisor (two required child-process lifetime owner)
          ├─ Guest Runtime (Guest control state owner)
          └─ Recorder Gateway (Recorder ingress, delivery replay, and cold-path capture state owner)
```

## 역할과 책임

| 구성요소 | owner | 명시적으로 하는 일 | 하지 않는 일 |
| --- | --- | --- | --- |
| C38 `GuestProductServiceManagerDeploymentConfiguration` | Guest product service-manager deployment | unit name, Supervisor executable/C37 path, restart mode/delay, install target 선언 | systemd가 실제 enabled/running임을 주장 |
| `guest_product_systemd_service_unit_composer` | release build adapter | canonical C38을 systemd unit text로 deterministic하게 변환 | unit install/enable/start/stop 또는 systemd state 관측 |
| systemd | Guest OS | unit install, enable/start/stop/restart와 OS process cgroup lifecycle | Guest Runtime/Recorder domain operation이나 packet receipt 소유 |
| `GuestProductProcessSupervisor` | Guest Product | C37을 읽고 두 required child의 start/exit/termination policy 실행 | systemd unit policy, Host VM lifecycle, upstream health 추측 |

`GuestProductServiceManagerDeploymentConfiguration`이라는 이름에는 `GuestProduct`
scope, `ServiceManager` owner boundary, `Deployment` desired-input lifecycle,
`Configuration` document role이 모두 들어 있다. `guest_product_systemd_service_unit_composer`
는 output technology가 systemd unit이라는 점과 release-build adapter 역할을 함께 드러낸다.

## C38이 보장하는 것과 보장하지 않는 것

C38는 `serviceManagerKind=systemd`, `.service` unit name, absolute Supervisor/C37
path, `Restart=on-failure`, restart delay, `WantedBy=multi-user.target`를 모두
required input으로 만든다. Composer는 C38 schema를 canonical source로 검증한 뒤:

```ini
[Service]
ExecStart=<supervisor executable> --deployment-configuration <C37 path>
Restart=on-failure
RestartSec=<explicit delay>
KillMode=control-group
```

를 만든다. `KillMode=control-group`은 Supervisor가 비정상 종료해도 같은 systemd cgroup에
남은 child를 OS가 정리할 수 있도록 한 **service-manager policy**다. 이는 child exit,
Gateway delivery-replay settlement, VitalServer delivery, Guest readiness의 성공 증거가 아니다.

Composer는 output file name이 `serviceUnitName`과 정확히 같은지 확인하고 existing
output을 덮어쓰지 않는다. 그래서 caller가 guessed unit name이나 stale build result를
service deployment input으로 바꿀 수 없다.

## C35와 package provenance

C35의 기존 additive pair는 `guestProductProcessSupervisorArtifact`와
`guestProductProcessDeploymentConfigurationArtifact`다. 이 v1 rule은 이미 frozen
baseline이므로 C38을 넣기 위해 기존 pair의 `allOf` semantics를 바꾸지 않는다.
`guestProductServiceManagerDeploymentConfigurationArtifact`는 별도 additive C35 input이다.

제품 PKG composer는 C35의 named Product input—Supervisor, C37, C38, C39—and the
selected `GuestProductBootstrapArtifactComposer` identity가 supplied bytes의
size/SHA-256과 정확히 같은지 요구한다. 이 guard는 historical non-product C35
command의 의미를 바꾸지 않으면서 release가 complete Guest Product bootstrap source를
selected builder에 제공했음을 기록한다. 이 provenance는 cloud-init이 root filesystem에
실제로 install한 것, systemd unit이 설치된 것, Guest boot가 성공한 것을 증명하지
않는다.

## 남은 증거

- release-approved `GuestProductBootstrapArtifactComposer`와
  `GuestProductBootstrapVolumeComposer`가 Supervisor, C37, C38, generated unit을
  byte-identified `CIDATA` volume으로 compose하는 evidence;
- Linux Guest boot 후 cloud-init이 C39 exact destination에 payload를 install한 evidence;
- Linux Guest boot 후 systemd daemon-reload, unit enable/start/restart/stop evidence;
- Supervisor exit와 systemd cgroup cleanup이 Recorder Gateway delivery replay/cold-path capture/Archive lifecycle을
  숨기지 않는 smoke test;
- macOS/Windows/Linux clean-host installation과 reboot/update/rollback/uninstall C24 proof.

이 공백은 shell fallback, guessed service name, Host-side process probing으로 채우지 않는다.
