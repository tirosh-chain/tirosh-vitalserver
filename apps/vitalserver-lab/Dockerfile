FROM python:3.14-alpine

WORKDIR /opt/vitalserver-lab

RUN apk add --no-cache postgresql-client
RUN pip install --no-cache-dir 'python-socketio[client]>=4.6,<5'

COPY apps/vitalserver-lab/ ./

ENV PYTHONUNBUFFERED=1
ENV VITALSERVER_LAB_HOST=0.0.0.0
ENV VITALSERVER_LAB_PORT=8080
ENV VITALSERVER_LAB_VITAL_FILES_MOUNT=/mnt/tirosh-vital-files

EXPOSE 8080

CMD ["python", "-m", "vitalserver_lab.server"]
