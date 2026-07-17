# 146 Apple Virtualization이 bootstrap ISO를 disk attachment로 열지 못함

> 상태: implementation verified / entitlement-signed Guest boot evidence pending

## 증상

C35가 `guest-product-bootstrap.iso`를 생성한 뒤 macOS provider가 C32의
`guest-product-bootstrap` attachment를 열지 못했다.

```text
configured guest-product-bootstrap guest-product-bootstrap-volume
storage attachment cannot be opened: Invalid disk image.
The disk image format is not recognized.
```

이는 root RAW disk가 같은 provider에서 먼저 열렸다는 관측과 함께 발생했다. 따라서
Guest kernel이나 cloud-init failure가 아니라 Host attachment boundary failure였다.

## 원인

기존 C35/C34/C32의 `format` 하나가 서로 다른 두 사실을 섞었다.

| 섞인 사실 | 실제 owner / 소비자 |
| --- | --- |
| Host가 Apple Virtualization에 attach할 disk-image container | C32 macOS provider |
| Guest가 partition device에서 mount할 filesystem | cloud-init in the Guest |

`ISO9660`은 Guest-visible filesystem이다. Apple Virtualization의
`VZDiskImageStorageDeviceAttachment`는 standalone ISO filesystem file을 일반 RAW
disk image로 취급하지 않는다. 따라서 `format=iso9660`은 Guest transport 의도는
표현했지만 Host attachment 계약으로는 부정확했다.

## 조치

계약과 구현을 다음처럼 분리했다.

| Contract field | Meaning |
| --- | --- |
| `storageImageFormat: raw` | Host가 attach하는 file container 형식 |
| `guestVolumeFileSystem: iso9660` | Guest bootstrap partition이 제공하는 filesystem |

`NoCloudGuestProductBootstrapVolumeAdapter`는 이제 one-partition MBR RAW disk image를
만든다. 해당 partition은 `0xcd` type이고 ISO9660 filesystem label은 `CIDATA`다.
C35 output path도 `storage/guest-product-bootstrap.raw`로 바꿨다. filename, field,
type 모두 “Host RAW disk / Guest ISO9660 filesystem”이라는 같은 의미를 보존해야 한다.

focused Go test는 다음을 모두 검증한다.

1. artifact가 MBR signature와 bootstrap partition을 가진 RAW image인가;
2. partition 내부가 ISO9660 filesystem인가;
3. `meta-data`, `user-data`, payload digest가 declared C40 plan과 같은가.

실제 Ubuntu Noble release-candidate input으로 C41→C35도 재실행하여 C34에
`storageImageFormat=raw`, `guestVolumeFileSystem=iso9660`이 기록된 것을 확인했다.

## 현재 증거 경계

새 C32를 macOS CLI로 구성하면 이전의 “disk image format is not recognized” attachment
오류는 발생하지 않는다. 현재 unsigned development CLI에서는 다음 entitlement 오류에서
멈춘다.

```text
Invalid virtual machine configuration. The process doesn’t have the
“com.apple.security.virtualization” entitlement.
```

이는 disk attachment 생성 이후 `VZVirtualMachineConfiguration.validate()`에서 나온
오류다. 따라서 RAW artifact가 Guest boot, cloud-init discovery, systemd start를
증명하는 것은 아니다. 다음 proof owner는 entitlement를 가진 signed macOS runtime에서
actual Guest boot smoke를 실행하고 C24 evidence에 결과를 기록해야 한다.

## 예방 원칙

한 field에 provider transport/container와 Guest protocol/filesystem을 함께 넣지 않는다.
계약의 필드명은 owner와 consumer가 읽는 개념을 직접 나타내야 한다. provider가 읽는
값은 provider attachment model로, Guest가 mount하는 값은 Guest volume model로 나누고,
두 값을 같은 `format` 같은 generic 이름으로 재통합하지 않는다.
