# vitaldb-observer

`vitaldb-observer`는 VitalServer Source Redis를 read-only로 읽어 최신 관측 snapshot을
HTTP로 제공하는 stateless foreground daemon입니다. Redis를 수정하거나 외부에 노출하지
않으며, 역사 데이터베이스나 Runtime Control의 owner가 아닙니다.

설치, 설정, launchd 운영, 장애 판단은 canonical 문서를 사용합니다.

- [VitalDB Observer](../../docs/vitaldb-observer/index.md)

## 책임

- Redis recorder/bed/activity 상태를 읽어 snapshot을 계산한다.
- 선택적 proxy access log를 진단 근거로만 붙인다.
- `/health`, `/ready`, `/api/v1/observations`를 제공한다.
- launchd가 생명주기를 소유하는 foreground 프로세스로 동작한다.

## 개발 확인

```sh
.venv/bin/python -m pytest apps/vitaldb-observer/tests
.venv/bin/ruff check apps/vitaldb-observer
.venv/bin/ruff format --check apps/vitaldb-observer
.venv/bin/python -m mypy apps/vitaldb-observer
```

Docker와 module 실행은 `python -m vitaldb_observer.server`를 유지합니다.
