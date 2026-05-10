.PHONY: build up down restart logs ps shell config clean-volumes
.PHONY: swagger swagger-down

build: init
	$(COMPOSE) build

up: init
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

restart: down up

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

shell:
	$(COMPOSE) exec app sh

config:
	$(COMPOSE) config

clean-volumes:
	$(COMPOSE) down --volumes

swagger:
	$(COMPOSE) --profile swagger up -d swagger-ui
	@printf "Swagger UI: http://localhost:$${SWAGGER_UI_PORT:-8082}\n"

swagger-down:
	$(COMPOSE) --profile swagger stop swagger-ui
