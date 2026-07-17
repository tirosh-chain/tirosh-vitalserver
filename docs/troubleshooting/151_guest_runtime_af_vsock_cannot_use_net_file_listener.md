# 151 Guest Runtime AF_VSOCK listener를 Go `net.FileListener`로 변환할 수 없음

> 상태: resolved by `GuestRuntimeControlVirtioSocketListener` Linux adapter

## 증상

Guest Product Process Supervisor는 Guest Runtime TCP control listener를 시작한 뒤
다음 오류로 virtio-socket listener를 시작하지 못했다.

```text
Guest Runtime control virtio-socket cannot become a network listener:
file file+net guest-runtime-control-virtio-socket: protocol not supported
```

이는 `AF_VSOCK` socket 생성, bind, listen이 실패했다는 뜻이 아니다. 이미 만들어진
Linux socket descriptor를 Go standard `net.FileListener`가 TCP/Unix listener로
분류하지 못한 adapter implementation failure다.

## 원인

`net.FileListener`는 `AF_VSOCK`를 일반 `net.Listener` family로 adapt하지 않는다.
그 결과 Guest Runtime이 C37에서 선언한 virtio-socket port를 TCP fallback으로 바꾸거나
Guest IP endpoint로 추측하지 않고도 listener construction에서 실패했다.

## 조치 방향

Linux adapter `guestruntimecontrolvirtiolistener`가 `AF_VSOCK` file descriptor를 직접
소유한다. `unix.Accept`, `unix.Read`, `unix.Write`, `unix.Close`, socket deadline을
`net.Listener`/`net.Conn` contract로 명시적으로 adapt하고 address는 IP가 아닌
`vsock://cid:port`로 표현한다.

## 예방 원칙

external transport family는 generic file-to-network conversion이 지원한다고 가정하지
않는다. package와 type 이름에 `GuestRuntimeControl`, `VirtioSocket`, `Listener`를 모두
넣어 C37 contract와 Linux adapter를 code search로 연결한다. unsupported adapter result를
TCP/Guest-IP fallback으로 바꾸지 않는다.

## 관련 경계

- C37 `controlVirtioSocketListener`
- `guestruntimecontrolvirtiolistener`
- `GuestRuntimeControlVirtioSocketListener`
