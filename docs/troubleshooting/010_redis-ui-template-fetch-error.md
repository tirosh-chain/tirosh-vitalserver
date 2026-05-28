# 010 Redis UI가 `failed to fetch html template`을 표시

> ID: TS-010  
> Category: Guest containers  
> Owner: macOS runtime  
> Status: resolved

증상:

```text
failed to fetch html template templates/editBranch.ejs
```

원인:

Redis Commander는 browser에서 `templates/*.ejs` 같은 상대 경로를 가져옵니다. `/redis-ui/` 아래에 붙일 때 nginx가 prefix를 그대로 upstream에 넘기면 Redis Commander의 정적 template 경로와 어긋날 수 있습니다.

조치:

guest edge nginx는 `/redis-ui/` prefix를 제거해서 Redis Commander upstream에는 root path로 보이게 합니다.

```nginx
location = /redis-ui {
  return 301 /redis-ui/;
}

location /redis-ui/ {
  proxy_pass http://redis-ui:8081/;
}
```

Compose에는 `URL_PREFIX=/redis-ui`를 넣지 않습니다. prefix는 edge nginx가 처리하고 Redis Commander는 root app처럼 실행합니다.

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
