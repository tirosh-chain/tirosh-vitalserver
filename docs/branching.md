# Branch 운영 기준

이 저장소는 monorepo이고 package별 tag를 사용합니다. branch는 릴리즈 버전을 표현하기보다
작업의 위험도와 통합 위치를 구분하는 용도로 사용합니다.

## 기본 원칙

`main`은 보호된 안정 브랜치입니다. release와 tag의 기준으로 사용하고, 직접 commit하지
않습니다. `main`에 들어가는 변경은 PR로 검토한 뒤 merge합니다.

`develop`은 main으로 보내기 전 작업이 모이는 통합 브랜치입니다. 문서 정리나 작은 운영
개선은 `develop`에 직접 commit할 수 있습니다. `develop`은 깨질 수 있지만, 오래 깨진 상태로
두지 않습니다.

기능 구현, 위험한 변경, 실험은 별도 브랜치에서 진행합니다. 작업이 정리되면 `develop`으로
합치고, 여러 변경을 묶어 검증한 뒤 `develop`에서 `main`으로 PR을 보냅니다.

## Branch 역할

| Branch | 역할 | 기준 |
| --- | --- | --- |
| `main` | 안정 브랜치, release/tag 기준 | 보호 branch, PR로만 변경 |
| `develop` | 통합 작업 브랜치 | 작은 문서/정리 작업은 직접 commit 가능 |
| `feature/*` | 이슈 단위 구현 | `develop`에서 따고 `develop`으로 PR |
| `experiment/*` | 성공 여부가 불확실한 실험 | 버릴 수 있는 branch, merge 전 정리 필요 |
| `hotfix/*` | main 기준 긴급 수정 | `main`으로 PR, 필요하면 `develop`에도 반영 |

## 작업 흐름

일반 기능 작업:

```sh
git switch develop
git pull  # git pull --prune
git switch -c feature/issue-18-vrecorder-capture
```

작업이 끝나면 `feature/*`에서 `develop`으로 PR을 만듭니다.

작은 문서 정리:

```sh
git switch develop
git pull  # git pull --prune
# edit docs
git commit -m "Document branch workflow"
git push
```

release 정리:

```text
feature/* -> develop
develop에서 검증
develop -> main PR
main merge 후 package tag 생성
```

## Tag 기준

이 저장소는 monorepo이므로 release는 branch 이름이 아니라 tag로 구분합니다. package별로
필요한 tag prefix를 사용합니다.

예시:

```text
testkit-v0.1.0
capture-v0.1.0
```

`main`에 merge된 commit에 tag를 붙이는 것을 기본으로 합니다. `develop`의 임시 commit에는
release tag를 붙이지 않습니다.
