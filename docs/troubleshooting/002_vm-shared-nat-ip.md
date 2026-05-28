# 002 VM IP가 `192.168.64.x`로 보임

> ID: TS-002  
> Category: Network  
> Owner: macOS runtime  
> Status: active

증상:

cloud-init log에 아래처럼 표시됩니다.

```text
Address 192.168.64.3
Gateway 192.168.64.1
```

원인:

shared/NAT mode에서는 macOS Virtualization NAT DHCP가 VM IP를 부여합니다. 이 IP는 병원 LAN DHCP에서 받은 IP가 아닙니다.

조치:

v1 구조에서는 정상입니다. 사용자는 이 VM IP로 직접 접속하지 않고, target Mac host nginx로 접속합니다.

```text
VRecorder
  -> http://<target Mac LAN IP>/
      -> host nginx
      -> VM shared/NAT IP
```

host nginx를 경유하면 VRecorder 원 IP 보존이 가능합니다.

VM이 병원 LAN IP를 직접 받는 구조를 검증하려면 bridged mode를 사용합니다.

```sh
make vm-interfaces
VM_BRIDGED_CODESIGN_IDENTITY="Developer ID Application: ..." \
VM_BRIDGED_INTERFACE=en0 \
make vm-up-bridged
```

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
