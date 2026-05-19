.PHONY: build app-build app-rebuild up down restart logs ps shell config clean clean-volumes
.PHONY: open
.PHONY: swagger swagger-down

build: init
	$(COMPOSE) build

app-build: init
	$(COMPOSE) build app

app-rebuild: init
	$(COMPOSE) build app
	VITALSERVER_BIND_HOST="$(VITALSERVER_BIND_HOST)" \
	VITALSERVER_HTTP_PORT="$(VITALSERVER_HTTP_PORT)" \
	VITALSERVER_REDIS_HOST="$(VITALSERVER_REDIS_HOST)" \
	VITALSERVER_REDIS_PORT="$(VITALSERVER_REDIS_PORT)" \
	VITALSERVER_TRUST_PROXY="$(VITALSERVER_TRUST_PROXY)" \
	$(COMPOSE) up -d --no-deps --force-recreate app

up: init proxy-test
	VITALSERVER_BIND_HOST="$(VITALSERVER_BIND_HOST)" \
	VITALSERVER_HTTP_PORT="$(VITALSERVER_HTTP_PORT)" \
	VITALSERVER_REDIS_HOST="$(VITALSERVER_REDIS_HOST)" \
	VITALSERVER_REDIS_PORT="$(VITALSERVER_REDIS_PORT)" \
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
	@port="$(VITALSERVER_PROXY_PORT)"; \
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
	VITALSERVER_REDIS_HOST="$(VITALSERVER_REDIS_HOST)" \
	VITALSERVER_REDIS_PORT="$(VITALSERVER_REDIS_PORT)" \
	VITALSERVER_TRUST_PROXY="$(VITALSERVER_TRUST_PROXY)" \
	$(COMPOSE) config

clean-volumes:
	$(MAKE) proxy-stop
	$(COMPOSE) down --volumes

clean:
	$(MAKE) proxy-clean
	$(COMPOSE) down --volumes --remove-orphans --rmi local

swagger:
	$(COMPOSE) --profile swagger up -d --no-deps swagger-ui
	@printf "Swagger UI: http://localhost:$${SWAGGER_UI_PORT:-8082}\n"

swagger-down:
	$(COMPOSE) --profile swagger stop swagger-ui
