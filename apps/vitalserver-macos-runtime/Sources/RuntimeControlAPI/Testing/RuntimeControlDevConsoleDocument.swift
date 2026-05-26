import Foundation

public enum RuntimeControlDevConsoleDocument {
    public static let path = "/dev/runtime-control"

    public static func response(for request: RuntimeControlHTTPRequest) -> RuntimeControlHTTPResponse? {
        guard request.method == .get else {
            return nil
        }
        let requestPath = URLComponents(string: request.path)?.path ?? request.path
        guard requestPath == path || requestPath == "\(path)/" || requestPath == "\(path).html" else {
            return nil
        }
        return RuntimeControlHTTPResponse(
            status: .ok,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: Data(html.utf8)
        )
    }

    public static let html = #"""
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Runtime Control API Console</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f4f6f7;
      --panel: #ffffff;
      --text: #24272a;
      --muted: #747b82;
      --line: #d8dde1;
      --accent: #0b6bd3;
      --ok: #2fbf5b;
      --bad: #d33f49;
      --warn: #b7791f;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font: 14px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      padding: 18px 22px;
      border-bottom: 1px solid var(--line);
      background: var(--panel);
    }
    h1, h2 {
      margin: 0;
      letter-spacing: 0;
    }
    h1 { font-size: 20px; }
    h2 { font-size: 16px; }
    main {
      display: grid;
      grid-template-columns: minmax(280px, 360px) 1fr;
      gap: 14px;
      padding: 14px;
    }
    section {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 14px;
      min-width: 0;
    }
    .stack { display: grid; gap: 14px; }
    .grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(220px, 1fr));
      gap: 14px;
    }
    .read-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(260px, 1fr));
      gap: 14px;
    }
    label {
      display: grid;
      gap: 5px;
      color: var(--muted);
      font-size: 12px;
      margin-top: 12px;
    }
    input, select {
      width: 100%;
      border: 1px solid var(--line);
      border-radius: 6px;
      padding: 8px 10px;
      font: inherit;
      color: var(--text);
      background: white;
    }
    button {
      border: 1px solid var(--line);
      border-radius: 6px;
      padding: 8px 10px;
      font: inherit;
      color: var(--text);
      background: #fff;
      cursor: pointer;
    }
    button.primary {
      border-color: var(--accent);
      background: var(--accent);
      color: white;
    }
    button:disabled {
      color: #9aa0a6;
      cursor: default;
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 12px;
    }
    .metric {
      display: grid;
      grid-template-columns: 110px 1fr;
      gap: 8px;
      padding: 7px 0;
      border-bottom: 1px solid #edf0f2;
    }
    .metric:last-child { border-bottom: 0; }
    .metric span:first-child { color: var(--muted); }
    .metric strong {
      min-width: 0;
      overflow-wrap: anywhere;
    }
    .list {
      display: grid;
      gap: 8px;
      margin-top: 10px;
    }
    .list-item {
      border: 1px solid #edf0f2;
      border-radius: 6px;
      padding: 8px;
      min-width: 0;
    }
    .list-item strong {
      display: block;
      overflow-wrap: anywhere;
    }
    .list-item span {
      color: var(--muted);
      font-size: 12px;
      overflow-wrap: anywhere;
    }
    .subtle {
      color: var(--muted);
      font-size: 12px;
      margin-top: 8px;
    }
    .status-dot {
      display: inline-block;
      width: 10px;
      height: 10px;
      border-radius: 50%;
      margin-right: 7px;
      background: var(--muted);
    }
    .status-dot.open { background: var(--ok); }
    .status-dot.error { background: var(--bad); }
    .status-dot.idle { background: var(--warn); }
    .stream-head {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 10px;
      margin-bottom: 10px;
    }
    .stream-state {
      white-space: nowrap;
      color: var(--muted);
      font-size: 12px;
    }
    pre {
      margin: 0;
      min-height: 220px;
      max-height: 420px;
      overflow: auto;
      padding: 10px;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: #101418;
      color: #e6edf3;
      font: 12px/1.45 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      white-space: pre-wrap;
      overflow-wrap: anywhere;
    }
    @media (max-width: 980px) {
      main, .grid, .read-grid { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <header>
    <h1>Runtime Control API Console</h1>
    <div id="clock"></div>
  </header>
  <main>
    <div class="stack">
      <section>
        <h2>Connection</h2>
        <label>
          Base URL
          <input id="baseUrl" autocomplete="off">
        </label>
        <label>
          Token
          <input id="token" autocomplete="off" value="vitalserver-helper-dev">
        </label>
        <div class="actions">
          <button class="primary" id="refresh">Refresh</button>
          <button id="connectAll">Connect streams</button>
          <button id="disconnectAll">Disconnect</button>
        </div>
      </section>
      <section>
        <h2>Runtime Status</h2>
        <div id="statusMetrics"></div>
      </section>
      <section>
        <h2>Runtime Info</h2>
        <div id="installMetrics"></div>
      </section>
      <section>
        <h2>Backups</h2>
        <div id="backupMetrics"></div>
      </section>
      <section>
        <h2>Log Source</h2>
        <label>
          Source
          <select id="logSource">
            <option value="helperMessage">helperMessage</option>
            <option value="install">install</option>
            <option value="command">command</option>
            <option value="launcher">launcher</option>
            <option value="proxyOutput">proxyOutput</option>
            <option value="proxyError">proxyError</option>
            <option value="updateActivation">updateActivation</option>
            <option value="containers" selected>containers</option>
          </select>
        </label>
        <label>
          Line limit
          <input id="lineLimit" type="number" min="1" value="80">
        </label>
      </section>
    </div>
    <div class="stack">
      <div class="read-grid">
        <section>
          <h2>Settings</h2>
          <div id="settingsMetrics"></div>
        </section>
        <section>
          <h2>Release</h2>
          <div id="releaseMetrics"></div>
        </section>
      </div>
      <div class="grid">
      <section>
        <div class="stream-head">
          <h2>Status Stream</h2>
          <span class="stream-state"><span id="statusDot" class="status-dot"></span><span id="statusState">closed</span></span>
        </div>
        <pre id="statusStream"></pre>
      </section>
      <section>
        <div class="stream-head">
          <h2>Event Stream</h2>
          <span class="stream-state"><span id="eventDot" class="status-dot"></span><span id="eventState">closed</span></span>
        </div>
        <pre id="eventStream"></pre>
      </section>
      <section>
        <div class="stream-head">
          <h2>Log Stream</h2>
          <span class="stream-state"><span id="logDot" class="status-dot"></span><span id="logState">closed</span></span>
        </div>
        <pre id="logStream"></pre>
      </section>
      </div>
    </div>
  </main>
  <script>
    const streams = new Map();
    let latestStatus = null;
    let latestSettings = {};
    const $ = (id) => document.getElementById(id);
    $("baseUrl").value = window.location.origin;

    function headers() {
      return { "X-Runtime-Control-Token": $("token").value };
    }

    function endpoint(path) {
      return new URL(path, $("baseUrl").value).toString();
    }

    async function getJSON(path) {
      const response = await fetch(endpoint(path), { headers: headers() });
      const text = await response.text();
      if (!response.ok) {
        throw new Error(text || `HTTP ${response.status}`);
      }
      return text ? JSON.parse(text) : null;
    }

    async function refreshStatus() {
      const [status, settings, install, release, backups, redisBackups] = await Promise.all([
        getJSON("/runtime/status"),
        getJSON("/runtime/settings"),
        getJSON("/runtime/install"),
        getJSON("/runtime/release"),
        getJSON("/host/backups"),
        getJSON("/host/backups/redis")
      ]);
      latestStatus = status;
      latestSettings = settings || {};
      renderStatus(latestStatus, latestSettings);
      renderInstall(install);
      renderSettings(settings);
      renderRelease(release);
      renderBackups(backups, redisBackups);
      append("statusStream", "snapshot", status);
    }

    function renderStatus(status, settings = {}) {
      const vitalServerURL = `http://127.0.0.1:${status.proxyPort || 80}/`;
      const redisUIURL = `http://127.0.0.1:${status.proxyPort || 80}/redis-ui/`;
      const swaggerURL = `http://127.0.0.1:${status.proxyPort || 80}/swagger/`;
      const values = [
        ["overall health", status.runtimeState],
        ["operation", status.operation],
        ["message", status.statusMessage],
        ["VitalServer", serviceText(status.hostProxyHTTP)],
        ["started", formatDate(status.startedAt)],
        ["uptime", formatUptime(status.startedAt)],
        ["VitalServer URL", vitalServerURL],
        ["Redis UI URL", redisUIURL],
        ["Swagger URL", swaggerURL],
        ["data directory", settings.vitalFilesDirectory],
        ["runtime version", status.runtimeVersion],
        ["VM IP", status.vmIP],
        ["guest HTTP", status.guestHTTP],
        ["host proxy HTTP", status.hostProxyHTTP],
        ["Redis UI HTTP", status.redisUIHTTP],
        ["Swagger HTTP", status.swaggerUIHTTP],
        ["guest log sync service", status.guestLogSyncServiceLoaded ? "running" : "stopped"],
        ["CPU", formatPercent(status.cpuUsagePercent)],
        ["memory", formatUsage(status.memory)],
        ["VM disk", formatUsage(status.systemDisk)],
        ["data storage", formatUsage(status.dataStorage)],
        ["updated", formatDate(status.updatedAt)]
      ];
      $("statusMetrics").innerHTML = metricsHTML(values);
    }

    function renderInstall(install) {
      const values = [
        ["app bundle", install.appBundlePath],
        ["package identifier", install.packageIdentifier],
        ["runtime home", install.runtimeHomePath],
        ["rollback backups", install.backupsPath],
        ["Redis backups", install.redisBackupsPath]
      ];
      $("installMetrics").innerHTML = metricsHTML(values);
    }

    function renderSettings(settings) {
      const values = [
        ["CPU", settings.cpuCount],
        ["memory", `${settings.memoryGiB || "-"} GiB`],
        ["disk", `${settings.diskGiB || "-"} GiB`],
        ["network", settings.networkMode],
        ["proxy port", settings.proxyPort],
        ["public host", settings.publicHost],
        ["public port", settings.publicPort],
        ["start on boot", settings.startOnBoot],
        ["auto recovery", settings.autoRecoveryEnabled],
        ["prevent Mac sleep", settings.preventSystemSleep],
        ["Redis backups", settings.redisBackupRetentionCount]
      ];
      $("settingsMetrics").innerHTML = metricsHTML(values);
    }

    function renderRelease(release) {
      const values = [
        ["helper version", release.helperVersion],
        ["minimum updater", release.minimumUpdaterVersion],
        ["VitalServer version", release.vitalServerVersion]
      ];
      const services = (release.services || []).map((service) => (
        `<div class="list-item"><strong>${escapeHtml(service.name || "-")}</strong><span>${escapeHtml(service.image || "-")} · ${escapeHtml(service.version || "-")}</span></div>`
      )).join("");
      $("releaseMetrics").innerHTML = `${metricsHTML(values)}<div class="list">${services || emptyText("No services")}</div>`;
    }

    function renderBackups(backups = [], redisBackups = []) {
      const values = [
        ["rollback backups", backups.length],
        ["Redis backups", redisBackups.length]
      ];
      const rollbackList = listBackups(backups, "No rollback backups");
      const redisList = listBackups(redisBackups, "No Redis backups");
      $("backupMetrics").innerHTML = `${metricsHTML(values)}<div class="subtle">Rollback</div>${rollbackList}<div class="subtle">Redis</div>${redisList}`;
    }

    function metricsHTML(values) {
      return values.map(([key, value]) => (
        `<div class="metric"><span>${escapeHtml(key)}</span><strong>${escapeHtml(displayValue(value))}</strong></div>`
      )).join("");
    }

    function listBackups(backups, emptyLabel) {
      if (!backups || backups.length === 0) {
        return emptyText(emptyLabel);
      }
      return `<div class="list">${backups.map((backup) => (
        `<div class="list-item"><strong>${escapeHtml(fileName(backup.path))}</strong><span>${escapeHtml(formatBytes(backup.sizeBytes))} · ${escapeHtml(backup.path || "-")}</span></div>`
      )).join("")}</div>`;
    }

    function emptyText(label) {
      return `<div class="subtle">${escapeHtml(label)}</div>`;
    }

    function connectAll() {
      connectStream("status", "/runtime/status/stream", "statusStream", "statusState", "statusDot");
      connectStream("events", "/runtime/events/stream?limit=50", "eventStream", "eventState", "eventDot");
      connectStream("logs", `/host/logs/stream?source=${encodeURIComponent($("logSource").value)}&lineLimit=${encodeURIComponent($("lineLimit").value)}`, "logStream", "logState", "logDot");
    }

    function disconnectAll() {
      for (const controller of streams.values()) {
        controller.abort();
      }
      streams.clear();
      setState("statusState", "statusDot", "closed");
      setState("eventState", "eventDot", "closed");
      setState("logState", "logDot", "closed");
    }

    async function connectStream(name, path, outputId, stateId, dotId) {
      streams.get(name)?.abort();
      const controller = new AbortController();
      streams.set(name, controller);
      $(outputId).textContent = "";
      setState(stateId, dotId, "connecting");
      try {
        const response = await fetch(endpoint(path), {
          headers: { ...headers(), "Accept": "text/event-stream" },
          signal: controller.signal
        });
        if (!response.ok || !response.body) {
          throw new Error(await response.text() || `HTTP ${response.status}`);
        }
        setState(stateId, dotId, "open");
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = "";
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          const frames = buffer.split("\n\n");
          buffer = frames.pop() || "";
          for (const frame of frames) {
            if (frame.trim()) {
              appendFrame(outputId, frame);
            }
          }
        }
        setState(stateId, dotId, "closed");
      } catch (error) {
        if (controller.signal.aborted) {
          setState(stateId, dotId, "closed");
          return;
        }
        setState(stateId, dotId, "error");
        append(outputId, "error", { message: String(error.message || error) });
      } finally {
        if (streams.get(name) === controller) {
          streams.delete(name);
        }
      }
    }

    function appendFrame(outputId, frame) {
      const parsed = {};
      for (const line of frame.split("\n")) {
        if (line.startsWith(":")) {
          parsed.comment = line.slice(1).trim();
          continue;
        }
        const index = line.indexOf(":");
        if (index === -1) continue;
        parsed[line.slice(0, index)] = line.slice(index + 1).trimStart();
      }
      let data = parsed.data;
      try {
        data = JSON.parse(parsed.data);
      } catch (_) {}
      if (outputId === "logStream" && data && typeof data.text === "string") {
        $(outputId).textContent = `[${new Date().toLocaleTimeString()}] ${parsed.event || "runtime-log"}\n${data.text}\n`;
        return;
      }
      append(outputId, parsed.event || "message", { id: parsed.id, comment: parsed.comment, data });
      if (outputId === "statusStream" && parsed.data) {
        try {
          latestStatus = JSON.parse(parsed.data);
          renderStatus(latestStatus, latestSettings);
        } catch (_) {}
      }
    }

    function append(outputId, label, value) {
      const node = $(outputId);
      const line = `[${new Date().toLocaleTimeString()}] ${label}\n${JSON.stringify(value, null, 2)}\n\n`;
      node.textContent = line + node.textContent;
    }

    function setState(stateId, dotId, state) {
      $(stateId).textContent = state;
      $(dotId).className = `status-dot ${state === "open" ? "open" : state === "error" ? "error" : state === "connecting" ? "idle" : ""}`;
    }

    function displayValue(value) {
      if (value === undefined || value === null || value === "") {
        return "-";
      }
      if (typeof value === "boolean") {
        return value ? "true" : "false";
      }
      return String(value);
    }

    function serviceText(httpStatus) {
      const code = Number(httpStatus);
      if (Number.isInteger(code) && code >= 200 && code < 300) {
        return "Reachable";
      }
      if (httpStatus === "failed") {
        return "Unreachable";
      }
      return "Waiting";
    }

    function formatDate(value) {
      if (!value) return "-";
      const date = new Date(value);
      if (Number.isNaN(date.getTime())) return value;
      return date.toLocaleString();
    }

    function formatUptime(startedAt) {
      if (!startedAt) return "-";
      const started = new Date(startedAt);
      if (Number.isNaN(started.getTime())) return "-";
      const seconds = Math.max(Math.floor((Date.now() - started.getTime()) / 1000), 0);
      const days = Math.floor(seconds / 86400);
      const hours = Math.floor((seconds % 86400) / 3600);
      const minutes = Math.floor((seconds % 3600) / 60);
      const remainingSeconds = seconds % 60;
      const clock = [hours, minutes, remainingSeconds].map((value) => String(value).padStart(2, "0")).join(":");
      return days > 0 ? `${days}d ${clock}` : clock;
    }

    function formatPercent(value) {
      if (value === undefined || value === null) return "-";
      return `${Number(value).toFixed(1)}%`;
    }

    function formatUsage(value) {
      if (!value || value.usedBytes === undefined || value.totalBytes === undefined) {
        return "-";
      }
      return `${formatBytes(value.usedBytes)} / ${formatBytes(value.totalBytes)}`;
    }

    function formatBytes(value) {
      if (value === undefined || value === null) return "-";
      const units = ["B", "KiB", "MiB", "GiB", "TiB"];
      let size = Number(value);
      let unit = 0;
      while (size >= 1024 && unit < units.length - 1) {
        size /= 1024;
        unit += 1;
      }
      return `${size >= 10 || unit === 0 ? size.toFixed(0) : size.toFixed(1)} ${units[unit]}`;
    }

    function fileName(path) {
      if (!path) return "-";
      return String(path).split("/").filter(Boolean).pop() || path;
    }

    function escapeHtml(value) {
      return String(value).replace(/[&<>"']/g, (char) => ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#039;"
      }[char]));
    }

    $("refresh").addEventListener("click", () => refreshStatus().catch((error) => append("statusStream", "error", { message: error.message })));
    $("connectAll").addEventListener("click", connectAll);
    $("disconnectAll").addEventListener("click", disconnectAll);
    function reconnectLogs() {
      if (streams.has("logs")) {
        connectStream("logs", `/host/logs/stream?source=${encodeURIComponent($("logSource").value)}&lineLimit=${encodeURIComponent($("lineLimit").value)}`, "logStream", "logState", "logDot");
      }
    }

    $("logSource").addEventListener("change", reconnectLogs);
    $("lineLimit").addEventListener("change", reconnectLogs);
    setInterval(() => {
      $("clock").textContent = new Date().toLocaleString();
      if (latestStatus) {
        renderStatus(latestStatus, latestSettings);
      }
    }, 1000);
    refreshStatus().catch((error) => append("statusStream", "error", { message: error.message }));
  </script>
</body>
</html>
"""#
}
