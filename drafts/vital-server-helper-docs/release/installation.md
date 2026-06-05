# Installation

이 문서는 Vital Server Helper 현장 설치 흐름을 설명합니다.

세부 command와 build 절차는 dev 문서에서 다룹니다. release 문서에서는 설치자가
확인해야 할 순서와 결과를 중심으로 설명합니다.

## 설치 전 확인

| 항목 | 확인 내용 |
|---|---|
| 장비 | 지원 Mac mini/Mac Studio 계열 장비 |
| 네트워크 | 병원 내부망 IP, VRecorder 접근 경로, 운영자 접근 경로 |
| 저장 위치 | `.vital` 파일 저장 directory |
| 권한 | 설치 권한, service 실행 권한, 저장 directory 접근 권한 |
| 모드 | 병원 내 기본 모드 또는 cloud 선택 모드 |

## 설치 흐름

1. 설치 파일을 준비합니다.
2. Vital Server Helper installer를 실행합니다.
3. 초기 설정에서 저장 위치와 네트워크 설정을 확인합니다.
4. Helper app을 열어 Status를 확인합니다.
5. Health Check를 실행해 VitalServer, VR/VRecorder, `.vital` 저장 상태를 확인합니다.
6. 필요하면 Logs에서 설치/서비스 로그를 확인합니다.

## 설치 후 확인

설치 후 아래 상태가 명시적으로 확인되어야 합니다.

| 상태 | 기대 결과 |
|---|---|
| VitalServer URL | 병원 내부망에서 접근 가능 |
| Health Check | 실행 가능 |
| VRecorder 연결 | 연결됨 또는 아직 연결되지 않음이 명시적으로 표시 |
| 저장 directory | 접근 가능 또는 권한 실패가 명시적으로 표시 |
| 로그 | 설치/서비스 로그 확인 가능 |

연결되지 않은 VRecorder는 정상 연결과 다릅니다. 권한 실패는 빈 저장 상태와 다릅니다.
설치 확인에서는 이 의미를 섞지 않습니다.
