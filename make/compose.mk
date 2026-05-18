.PHONY: build up down restart logs ps shell config clean-volumes
.PHONY: open
.PHONY: swagger swagger-down
.PHONY: proxy-config

build: init
	$(COMPOSE) build

up: init
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

restart: down
	$(COMPOSE) up -d

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

open:
	@url="$${VITALSERVER_URL:-http://localhost:$${VITALSERVER_HTTP_PORT:-8080}}"; \
	printf "VitalServer: %s\n" "$$url"; \
	"$(PYTHON)" -m webbrowser -t "$$url"

shell:
	$(COMPOSE) exec app sh

config:
	$(COMPOSE) config

clean-volumes:
	$(COMPOSE) down --volumes

swagger:
	$(COMPOSE) --profile swagger up -d --no-deps swagger-ui
	@printf "Swagger UI: http://localhost:$${SWAGGER_UI_PORT:-8082}\n"

swagger-down:
	$(COMPOSE) --profile swagger stop swagger-ui

proxy-config:
	@VITALSERVER_PROXY_PORT="$${VITALSERVER_PROXY_PORT:-8080}" \
	VITALSERVER_HTTP_PORT="$${VITALSERVER_HTTP_PORT:-18080}" \
	"$(PYTHON)" -c 'import os, pathlib; p=pathlib.Path("infra/macos-nginx/vitalserver.conf.template"); s=p.read_text(); print(s.replace("$${VITALSERVER_PROXY_PORT}", os.environ["VITALSERVER_PROXY_PORT"]).replace("$${VITALSERVER_HTTP_PORT}", os.environ["VITALSERVER_HTTP_PORT"]), end="")'
