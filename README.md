# tirosh-vitalserver

VitalDB VitalServer를 Docker Compose로 실행하기 위한 래퍼 저장소입니다.

이 저장소는 VitalServer 애플리케이션 코드를 직접 관리하지 않습니다. VitalDB upstream
코드는 `vitalserver` git submodule로 고정하고, 이 저장소에서는 Dockerfile,
Compose 설정, 실행 보조 파일만 관리합니다.

## 1. 빠른실행

```sh
git clone --recurse-submodules https://github.com/tirosh-chain/tirosh-vitalserver.git
cd tirosh-vitalserver
make up
```

```text
http://localhost:8080
```

Redis UI:

```text
http://localhost:8081
```

기본 관리자 계정:

```text
UserId: admin
Password: admin
```

## 2. 사용 방법

### 2-1. 요구사항

- Docker
- Docker Compose v2
- Git submodule 지원 Git 클라이언트

Apple Silicon 환경에서도 amd64 이미지로 실행되도록 `compose.yaml`에
`platform: linux/amd64`가 지정되어 있습니다.

### 2-2. 실행

기본 HTTP 포트는 `8080`입니다.

```sh
make up
```

설정을 고정해서 쓰려면 `.env.example`을 복사해 `.env`를 만듭니다.

```sh
cp .env.example .env
```

다른 경로의 환경변수 파일을 쓰려면 `COMPOSE_ENV_FILE`을 지정합니다.

```sh
COMPOSE_ENV_FILE=.env.local make up
```

예를 들어 포트를 바꾸려면 `.env`에서 `VITALSERVER_HTTP_PORT` 또는
`REDIS_UI_PORT`를 수정합니다.

```env
VITALSERVER_HTTP_PORT=18080
REDIS_UI_PORT=18081
```

이 경우 접속 주소는 `http://localhost:18080`, Redis UI 주소는
`http://localhost:18081`입니다. 한 번만 다르게 실행하려면 inline 환경변수도 사용할 수
있습니다.

```sh
VITALSERVER_HTTP_PORT=18080 make up
```

### 2-3. 초기 계정

초기 관리자 계정은 `admin` / `admin`입니다.

초기 비밀번호를 바꾸려면 최초 실행 전에 `.env`에서
`VITALSERVER_ADMIN_PASSWORD`를 수정합니다.

```env
VITALSERVER_ADMIN_PASSWORD=change-me
```

관리자 UserId는 upstream 코드에서 `admin`을 특별 취급하므로 변경하지 않습니다.
이미 `redis-data` 볼륨이 생성된 뒤에는 초기 계정 생성이 다시 실행되지 않습니다. 이
경우 웹 UI에서 비밀번호를 변경하거나, 개발 환경에서는 `make clean-volumes`로 데이터를
초기화한 뒤 다시 실행합니다.

## 3. 운영

### 3-1. 자주 쓰는 명령

```sh
make help       # 사용 가능한 명령 보기
make init       # submodule 초기화/업데이트
make build      # Docker image 빌드
make up         # 백그라운드 실행
make logs       # 로그 보기
make ps         # 컨테이너 상태 보기
make restart    # 재시작
make down       # 중지
```

Compose를 직접 사용할 수도 있습니다.

```sh
docker compose up -d --build
docker compose logs -f
docker compose down
```

### 3-2. 데이터 볼륨

Compose는 아래 Docker volume을 사용합니다.

- `redis-data`: Redis append-only 데이터
- `vital-files`: VitalServer 파일 저장소 (`/opt/vitalserver/vital_files`)
- `vital-vr-release`: VR release 디렉터리
- `vital-tmp-files`: 임시 파일 디렉터리

이 볼륨들은 호스트 경로를 직접 지정하는 bind mount가 아니라 Docker가 관리하는 named
volume입니다. 그래서 `compose.yaml`에는 `./data/...` 같은 로컬 경로가 보이지 않습니다.
실제 volume 이름은 Compose project 이름이 붙어 아래처럼 생성됩니다.

```text
tirosh-vitaldb_redis-data
tirosh-vitaldb_vital-files
tirosh-vitaldb_vital-vr-release
tirosh-vitaldb_vital-tmp-files
```

위치를 확인하려면 Docker volume 명령을 사용합니다.

```sh
docker volume ls
docker volume inspect tirosh-vitaldb_vital-files
```

호스트에서 직접 보이는 디렉터리로 관리하고 싶다면 named volume 대신 bind mount로 바꿀
수 있습니다. 예를 들어 `vital-files`를 `./data/vital-files`로 관리하려면:

```yaml
volumes:
  - type: bind
    source: ./data/vital-files
    target: /opt/vitalserver/vital_files
```

Redis UI는 Redis Commander를 사용하며 기본 포트는 `8081`입니다.

컨테이너만 내릴 때는 데이터가 유지됩니다.

```sh
make down
```

데이터 볼륨까지 삭제하려면:

```sh
make clean-volumes
```

## 4. 저장소 관리

### 4-1. 구조

```text
.
├── compose.yaml
├── Dockerfile
├── runtime/
│   └── node-preload.js
└── vitalserver/               # git submodule: vitaldb/vitalserver
    └── vitalserver-old/       # Docker image에 복사되는 upstream 코드
```

### 4-2. Submodule 초기화

이미 clone한 저장소에서 submodule이 비어 있다면 아래 명령으로 초기화합니다.

```sh
make init
```

또는 Git 명령을 직접 사용할 수 있습니다.

```sh
git submodule update --init --recursive
```

### 4-3. VitalServer upstream 업데이트

upstream 변경분을 반영하려면 submodule을 업데이트한 뒤, 변경된 submodule commit을
이 저장소에 commit합니다.

```sh
make update-submodule
git status
git add vitalserver
git commit -m "Update vitalserver submodule"
```

일반적인 작업에서는 `vitalserver` 내부 코드를 수정하지 않습니다. 우리 쪽
변경은 Dockerfile, `compose.yaml`, `runtime/` 아래 보조 파일에 둡니다.
