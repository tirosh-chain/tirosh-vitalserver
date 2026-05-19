.PHONY: build up down restart logs ps shell config clean-volumes
.PHONY: open
.PHONY: swagger swagger-down

build: init
	$(COMPOSE) build

up: init proxy-test
	VITALSERVER_BIND_HOST="$(VITALSERVER_BIND_HOST)" \
	VITALSERVER_HTTP_PORT="$(VITALSERVER_HTTP_PORT)" \
	VITALSERVER_TRUST_PROXY="$(VITALSERVER_TRUST_PROXY)" \
	$(COMPOSE) up -d
	$(MAKE) proxy-run

down:
	$(MAKE) proxy-stop
	$(COMPOSE) down

restart: down
	$(MAKE) up

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

open:
	@port="$${VITALSERVER_PROXY_PORT:-80}"; \
	if [ -n "$${VITALSERVER_URL:-}" ]; then \
		url="$$VITALSERVER_URL"; \
	elif [ "$$port" = "80" ]; then \
		url="http://localhost"; \
	else \
		url="http://localhost:$$port"; \
	fi; \
	printf "VitalServer: %s\n" "$$url"; \
	"$(PYTHON)" -m webbrowser -t "$$url"

shell:
	$(COMPOSE) exec app sh

config:
	VITALSERVER_BIND_HOST="$(VITALSERVER_BIND_HOST)" \
	VITALSERVER_HTTP_PORT="$(VITALSERVER_HTTP_PORT)" \
	VITALSERVER_TRUST_PROXY="$(VITALSERVER_TRUST_PROXY)" \
	$(COMPOSE) config

clean-volumes:
	$(MAKE) proxy-stop
	$(COMPOSE) down --volumes

swagger:
	$(COMPOSE) --profile swagger up -d --no-deps swagger-ui
	@printf "Swagger UI: http://localhost:$${SWAGGER_UI_PORT:-8082}\n"

swagger-down:
	$(COMPOSE) --profile swagger stop swagger-ui
