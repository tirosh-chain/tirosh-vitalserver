FROM python:3.14-alpine

WORKDIR /opt/vitaldb-observer

COPY apps/vitaldb-observer/ ./

ENV PYTHONUNBUFFERED=1
ENV VITALDB_OBSERVER_HOST=0.0.0.0
ENV VITALDB_OBSERVER_PORT=8080

EXPOSE 8080

CMD ["python", "-m", "vitaldb_observer.server"]
