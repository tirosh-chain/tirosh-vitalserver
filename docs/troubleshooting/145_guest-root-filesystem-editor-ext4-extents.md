# 145 Host ext4 editor가 Ubuntu root에 파일을 쓰지 못함

> 상태: root-editor 경계 제거 완료 / 실제 Guest boot evidence pending

## 증상

C42 Linux boot artifact extraction, C43 MBR root-storage assembly, C41 input
assembly가 성공한 뒤 C35 `GuestArtifactCompiler`가 다음처럼 실패했다.

```text
stage=filesystem-editor-invocation
file destination /opt/vitalserver/bin/guest-runtime:
source bytes cannot be written: could not convert extents into tree:
block number not found for node
```

## 원인

당시 C40 `GoDiskFSGuestRootFilesystemExt4Adapter`는 synthetic ext4 integration
image에는 write할 수 있었지만 Ubuntu Noble cloud-image의 ext4 extent tree에 새 file
extent를 할당하지 못했다. 더 근본적으로는 Host release build가 Guest-owned root
filesystem을 직접 수정하는 authority를 갖고 있었다. C42/C43는 base identity와
partition layout만 증명하며, Host가 Guest root를 수정해도 된다는 권한이나 모든 ext4
feature write 지원을 증명하지 않는다.

## 조치

이 실패를 다른 Host-side ext4 tool로 우회하지 않았다. C39/C40의 역할을 아래처럼
분리했다.

1. C43은 byte-identified writable raw `guest-root` base만 조립한다.
2. C39 `GuestProductBootstrapConfiguration`은 Guest Product payload, archive,
   systemd unit/link의 desired installation vocabulary만 선언한다.
3. C40 `GuestProductBootstrapVolumeCompositionPlan`은 C39와 verified inputs에서
   Host가 attach할 read-only RAW storage image를 만들고, 그 Guest-visible MBR
   partition에 ISO9660 `CIDATA` filesystem을 넣는다.
4. Guest cloud-init이 attached volume의 payload를 verify하고, 그 뒤에만 자기 root
   filesystem과 systemd를 변경한다.

선택된 C35 `GuestProductBootstrapArtifactComposer`의 focused test는 raw root bytes가
unchanged이고 bootstrap RAW storage image가 생성됨을 확인한다. C41/C35/C34/C32는
정확히 두 storage artifact—writable RAW root, read-only RAW bootstrap image와
그 안의 ISO9660 Guest filesystem—를 명시적으로 전달한다.

## 남은 검증

아직 다음은 성공으로 주장하지 않는다.

- 실제 ARM64 Guest가 두 storage artifact를 attach해 boot하는가;
- cloud-init이 `CIDATA`를 인식하고 C39 payload를 install하는가;
- systemd가 declared service를 enable/start하는가;
- package install과 C24 clean-host lifecycle이 통과하는가.

이들은 Guest boot smoke와 C24 evidence가 각각 소유한다. Host command fallback, VM
cache, `PATH` discovery, 또는 bootstrap failure를 empty output으로 바꾸는 방식은
허용되지 않는다.

## 예방 원칙

Host와 Guest가 서로 다른 filesystem state owner일 때, Host build는 immutable delivery
artifact까지만 compose한다. Guest-owned root write, systemd action, completion fact는
Guest의 explicit bootstrap contract와 boot evidence로 검증한다. Release base를 바꾸면
C35 composition test뿐 아니라 actual Guest boot smoke를 compile gate로 실행한다.
