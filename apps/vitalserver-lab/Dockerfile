FROM python:3.12-slim

WORKDIR /opt/vitalserver-lab

COPY packages/vitalserver-core /opt/vitalserver-core
RUN pip install --no-cache-dir /opt/vitalserver-core

COPY packages/vitalserver-vitalfile /opt/vitalserver-vitalfile
RUN pip install --no-cache-dir /opt/vitalserver-vitalfile

RUN pip install --no-cache-dir \
    'python-socketio[client]>=4.6,<5' \
    'SQLAlchemy==2.0.51' \
    'psycopg[binary]==3.3.4' \
    'vitaldb>=1.7,<2'

COPY apps/vitalserver-lab/ ./

ENV PYTHONUNBUFFERED=1
ENV VITALSERVER_LAB_HOST=0.0.0.0
ENV VITALSERVER_LAB_PORT=8080
ENV VITALSERVER_LAB_VITAL_FILES_MOUNT=/mnt/tirosh-vital-files

EXPOSE 8080

CMD ["python", "-m", "vitalserver_lab.server"]
