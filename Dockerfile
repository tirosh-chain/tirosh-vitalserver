FROM node:12.16.2

WORKDIR /opt/vitalserver

COPY vitalserver/vitalserver-old/ ./
COPY runtime/node-preload.js /opt/vitalserver/runtime/node-preload.js

RUN mkdir -p vital_files service/tmp_files service/vr_release logs \
  && ln -sfn vital_files "Z:"

ENV NODE_ENV=production
ENV NODE_OPTIONS="--require /opt/vitalserver/runtime/node-preload.js"
ENV VITALSERVER_MIN_CPUS=6

EXPOSE 80

CMD ["node", "service/app.js"]
