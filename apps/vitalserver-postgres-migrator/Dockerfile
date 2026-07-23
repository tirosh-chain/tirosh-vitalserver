FROM python:3.12-slim

WORKDIR /opt/vitalserver-postgres-migrator

COPY apps/vitalserver-postgres-migrator/ ./
RUN pip install --no-cache-dir .

ENV PYTHONUNBUFFERED=1
ENV VITALSERVER_POSTGRES_MIGRATION_CONFIG=/opt/vitalserver-postgres-migrator/alembic.ini

CMD ["vitalserver-postgres-migrate"]
