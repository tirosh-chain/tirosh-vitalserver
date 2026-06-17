FROM python:3.14-alpine

WORKDIR /opt/vitalserver-redis-relay

COPY apps/vitalserver-redis-relay/ ./

ENV PYTHONUNBUFFERED=1
ENV REDIS_RELAY_CONFIG_PATH=/run/tirosh/config/redis-relay.toml
ENV REDIS_RELAY_STATUS_PATH=/run/tirosh/status/redis-relay-status.json

CMD ["python", "-m", "vitalserver_redis_relay"]
