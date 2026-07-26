FROM python:3.14-slim

WORKDIR /opt/vitalserver-recorder-recovery

COPY packages/vitalserver-core /opt/vitalserver-core
RUN pip install --no-cache-dir /opt/vitalserver-core

COPY packages/vitalserver-vitalfile /opt/vitalserver-vitalfile
RUN pip install --no-cache-dir /opt/vitalserver-vitalfile

COPY apps/vitalserver-recorder-recovery/ ./

RUN pip install --no-cache-dir .

ENV PYTHONUNBUFFERED=1
ENV RECORDER_RECOVERY_HOST=0.0.0.0
ENV RECORDER_RECOVERY_PORT=8080

EXPOSE 8080

CMD ["vitalserver-recorder-recovery", "serve", "--host", "0.0.0.0", "--port", "8080"]
