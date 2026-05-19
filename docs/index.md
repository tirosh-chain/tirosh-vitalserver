# 문서 지도

이 디렉터리는 VitalServer 제품화 작업에서 확인한 사실과 운영 기준을 정리합니다.
문서가 흩어지지 않도록 각 문서의 역할을 아래처럼 나눕니다.

## 문서 역할

| 문서 | 역할 |
| --- | --- |
| [VitalServer 제품화 전략](vitalserver-productization.md) | 저장소의 목표, 제품화 기준, 아직 비어 있는 영역 |
| [Branch 운영 기준](branching.md) | main/develop/feature branch와 package tag 운영 방식 |
| [Vital Recorder](vrecorder.md) | VRecorder 접속 흐름과 Web Monitoring 상태 표시 기준 |
| [Testkit 사용법](testkit-usage.md) | `vitalserver-testkit` CLI와 검증 시나리오 실행 방법 |
| [Redis 데이터 구조](redis-data-model.md) | VitalServer가 Redis에 저장하는 key 구조와 relay 설계 |
| [ADR 0001](adr/0001-macos-host-proxy-for-vrecorder-ip.md) | macOS host proxy로 VRecorder 원 IP를 보존하기로 한 결정 |
| [OpenAPI 문서](openapi.yaml) | upstream VitalServer route를 분석해 만든 Swagger/OpenAPI spec |

## 읽는 순서

처음 보는 사람은 아래 순서로 읽습니다.

1. repository root의 [README](../README.md)
2. [VitalServer 제품화 전략](vitalserver-productization.md)
3. [Branch 운영 기준](branching.md)
4. [Vital Recorder](vrecorder.md)
5. [Testkit 사용법](testkit-usage.md)
6. [Redis 데이터 구조](redis-data-model.md)

Swagger UI로 API를 확인할 때는 root에서 아래 명령을 실행합니다.

```sh
make swagger
```

이후 `http://localhost:8082`에서 [OpenAPI 문서](openapi.yaml)를 볼 수 있습니다.

## 작성 기준

- 문서는 가능한 한 한글로 작성합니다.
- CLI, API, Socket.IO, Redis, Docker, Compose처럼 개발자에게 익숙한 용어는 원어를 유지합니다.
- 실행 방법은 [Testkit 사용법](testkit-usage.md)에 모으고, 전략 문서에는 판단 기준만 남깁니다.
- Redis key와 relay처럼 구현의 근거가 되는 사실은 [Redis 데이터 구조](redis-data-model.md)에 모읍니다.
