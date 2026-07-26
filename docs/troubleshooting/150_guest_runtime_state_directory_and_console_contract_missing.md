# 150 Guest Runtime state directory가 없고 service 오류가 boot console에 보이지 않음

> 상태: resolved by C38 logging and C39 state-directory declarations

## 증상

Guest product supervisor는 systemd에서 시작됐지만 Guest Runtime이 다음 오류로 즉시
종료했다.

```text
Guest Runtime state initialization failed:
state database parent is unreadable: stat /var/lib/vitalserver/guest-runtime: no such file or directory
```

초기에는 service standard output/error가 console capture에 나오지 않아, Host는 단지
C32 bridge connection failure만 볼 수 있었다.

## 원인

C37 `GuestRuntimeProcessDeployment.stateDatabasePath`가 SQLite DB의 parent directory를
선언했지만, C39 bootstrap desired input은 그 directory를 만들 책임을 표현하지 않았다.
또한 C38 systemd deployment가 service output의 sink를 명시하지 않아 boot console은
runtime startup failure의 owner evidence가 아니었다.

## 조치 방향

C39 `GuestRuntimeStateDirectory`가 `/var/lib/vitalserver/guest-runtime`와 `0700` mode를
명시한다. C40 bootstrap composer는 C37 database path의 parent가 바로 그 C39 directory인지
검증하고, NoCloud bootstrap이 service start **전에** directory를 provision한다. C38은
`StandardOutput=journal+console`과 `StandardError=journal+console`을 explicit desired
input으로 render한다.

## 예방 원칙

SQLite adapter는 missing parent directory를 새 state 또는 default success로 바꾸지
않는다. persistent path의 owner, mode, creation 순서는 deployment contract에서 함께
표현한다. service error observability는 journal-only implicit default가 아니라 C38의
versioned desired logging declaration으로 관리한다.

## 관련 경계

- C37 `GuestProductProcessDeploymentConfiguration`
- C38 `GuestProductServiceManagerDeploymentConfiguration`
- C39 `GuestProductBootstrapConfiguration`
- C40 Guest product bootstrap artifact composer
