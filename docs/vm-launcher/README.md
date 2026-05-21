# VM Launcher 문서

Mac mini/Mac Studio에서 VitalServer를 Linux VM으로 운영하기 위한 문서군입니다.

처음 읽을 때는 이 문서에서 전체 구조를 잡고, 필요한 세부 문서로 이동합니다.

## 한눈에 보기

```text
VRecorder / Browser
  -> target Mac LAN IP :80
      -> macOS host nginx
          -> Linux VM shared/NAT IP :80
              -> Docker Compose edge nginx
                  -> vitalserver / redis-ui / swagger-ui / redis
```

v1의 기본값은 `shared/NAT VM + macOS host nginx`입니다. bridged mode는 Apple restricted entitlement 승인이 필요한 향후 옵션입니다.

## 책임 분리

| 영역 | 주 담당 | 핵심 책임 |
|---|---|---|
| 개발자 명령 | `make/vm/*.mk` | target dependency, 산출물 경로, 개발용 실행/설치 wrapper |
| Build | Python `packages/vm-build` | Ubuntu asset, cloud-init, rootfs, nginx bundle, Docker image bundle, update bundle |
| Runtime | Swift `vitalserver-vm` | VM lifecycle, install, health, configure, update, rollback, watchdog |
| Installer/launchd | Shell wrapper | `postinstall`, `proxy-run`, uninstall entrypoint 연결 |
| Guest | Shell + Compose | Linux guest Docker Compose stack, edge nginx container, VM runtime state 기록 |

## 문서 지도

| 문서 | 먼저 볼 때 |
|---|---|
| [Architecture](architecture.md) | 왜 shared/NAT + host nginx인지, 단일 노드에서 어디까지 보장하는지, 코드 책임이 어디인지 볼 때 |
| [Packaging and Update](packaging.md) | `make vm-pkg`, `make vm-dmg`, install settings, update bundle 계약을 볼 때 |
| [Runtime](runtime.md) | VM boot asset, cloud-init, guest bootstrap, network, identity, signing 정책을 볼 때 |
| [Troubleshooting](troubleshooting.md) | 502, disk full, cloud-init 재실행, bridged entitlement 같은 증상을 볼 때 |

## 자주 쓰는 명령

```sh
make vm-pkg
make vm-dmg
make vm-pkg-install
make vm-installed-health
```

clean golden rootfs를 다시 만든 release 검증용 package가 필요할 때:

```sh
make vm-pkg-release
make vm-dmg-release
```

개발용 VM을 직접 띄울 때:

```sh
make vm-up
make vm-health
make vm-down
```
