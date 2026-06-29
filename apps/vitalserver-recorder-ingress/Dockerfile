FROM node:20-alpine

WORKDIR /opt/vitalserver-recorder-ingress

COPY apps/vitalserver-recorder-ingress/ ./

RUN npm ci
RUN npm run build
RUN npm prune --omit=dev

ENV NODE_ENV=production
ENV RECORDER_INGRESS_PORT=8080

EXPOSE 8080

CMD ["npm", "start"]
