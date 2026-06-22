FROM node:20-alpine

WORKDIR /opt/vitalserver-recorder-ingress

COPY apps/vitalserver-recorder-ingress/ ./

ENV NODE_ENV=production
ENV RECORDER_INGRESS_PORT=8080

EXPOSE 8080

CMD ["npm", "start"]
