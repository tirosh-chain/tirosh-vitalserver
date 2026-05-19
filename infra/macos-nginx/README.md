# macOS VitalServer Proxy

macOS container runtime port forwarding can rewrite the client address before
the request reaches the VitalServer container. The host proxy must run outside
Docker so it can capture the VRecorder source IP and forward it to VitalServer
with trusted headers.

## Backend Environment

Use a loopback-only Docker backend and enable proxy trust in VitalServer.

```env
VITALSERVER_BIND_HOST=127.0.0.1
VITALSERVER_HTTP_PORT=18080
VITALSERVER_TRUST_PROXY=1
VITALSERVER_PUBLIC_HOST=
VITALSERVER_PUBLIC_PORT=
```

External VRecorder devices and browsers should connect to the macOS host proxy,
not to the Docker backend port.

## Render nginx Config

```sh
VITALSERVER_PROXY_PORT=80 VITALSERVER_HTTP_PORT=18080 make proxy-config \
  > /Library/Application\ Support/TiroshVitalServer/nginx/vitalserver.conf
```

The generated config overwrites client-supplied forwarding headers with
nginx's `$remote_addr` at the macOS host trust boundary.

## Render launchd Plist

```sh
make proxy-plist \
  > /Library/LaunchDaemons/com.tirosh.vitalserver-proxy.plist
```

The installer should provide the nginx binary, render both templates, load the
LaunchDaemon, and start Docker Compose with the backend environment above.
