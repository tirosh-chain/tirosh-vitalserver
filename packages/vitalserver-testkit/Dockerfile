FROM python:3.14-slim

WORKDIR /opt/vitalserver-testkit

COPY packages/vitalserver-testkit/pyproject.toml ./
COPY packages/vitalserver-testkit/src ./src
COPY config/testkit.toml ./config/testkit.toml

RUN pip install --no-cache-dir .

ENV PYTHONUNBUFFERED=1
ENV TESTKIT_HOST=0.0.0.0
ENV TESTKIT_PORT=18322

EXPOSE 18322

CMD ["vitalserver-testkit", "serve", "--host", "0.0.0.0", "--port", "18322"]
