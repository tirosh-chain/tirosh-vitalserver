# Deployment Modes

Vital Server Helper는 병원 내 기본 모드와 병원 외 cloud 선택 모드를 구분합니다.

기본 모드는 병원 내부망 운영입니다. cloud 연계는 기본 제공 모드가 아니라, 병원이
outbound 연결을 허용하는 경우에만 별도로 검토하는 선택 모드입니다.

## Hospital Intranet Mode

병원 내 기본 모드는 Vital Server Helper 장비가 병원 내부망에 설치되고, VRecorder와
운영자가 같은 내부망에서 접근하는 방식입니다.

```text
VRecorder / Browser
  -> 병원 내부망
      -> Vital Server Helper
          -> Vital Server
          -> Health Check
```

| 특징 | 설명 |
|---|---|
| outbound 없음 | 외부 연결 없이 내부망에서 운영 가능 |
| 현장 접근 | 운영자가 내부망 browser 또는 Helper app에서 상태 확인 |
| 명시 상태 | VRecorder activity, `.vital` 저장 상태, runtime 상태를 구분 |
| 병원 정책 우선 | 네트워크, 저장 위치, 접근 권한은 병원 정책 안에서 결정 |

## Cloud Option

Cloud 선택 모드는 병원이 outbound 연결을 허용하는 경우에만 검토합니다. 현재 preview
범위는 병원 내부망 운영 검토가 중심이며, cloud 선택 모드는 기본 SaaS, 원격 관제,
또는 자동 외부 전송 기능을 의미하지 않습니다.

```text
Vital Server Helper
  -> 병원 outbound 허용 구간
      -> cloud service
```

이 모드는 아래 전제가 필요합니다.

| 전제 | 설명 |
|---|---|
| outbound 허용 | 병원 보안 정책에서 외부 연결을 명시적으로 허용 |
| 데이터 범위 합의 | 어떤 상태 또는 데이터를 외부로 보낼지 사전 합의 |
| 보안 정책 확인 | 인증, 암호화, 접근 제어, audit 기준 확인 |
| 장애 대응 기준 | 연결 실패, 전송 실패, 지연 상태를 명시적으로 표시 |

cloud 선택 모드는 병원 내 기본 모드를 대체하지 않습니다. 병원 내부망 운영을 기본으로
두고, 허용된 병원에서만 별도로 검토합니다.

## 개인정보와 보안 경계

cloud 선택 모드는 기본값이 아닙니다. 환자 정보, 생체신호 데이터, recorder 식별자,
저장 파일 목록, 운영 로그 중 어떤 정보가 외부로 나가는지는 병원 정책에 따라
명시적으로 합의해야 합니다.

외부 전송을 사용하는 경우에도 최소 전송, 인증, 암호화, 접근 제어, audit log,
장애 시 degraded 표시를 별도 검토 항목으로 둡니다. dependency failure나 전송 실패는
정상 상태 또는 빈 결과로 표시하지 않습니다.
