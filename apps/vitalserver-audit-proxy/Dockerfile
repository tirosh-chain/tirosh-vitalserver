FROM node:20-alpine

WORKDIR /opt/vitalserver-audit-proxy

COPY apps/vitalserver-audit-proxy/ ./

ENV NODE_ENV=production
ENV AUDIT_PROXY_PORT=8080

EXPOSE 8080

CMD ["npm", "start"]
