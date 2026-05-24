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
      main, .grid { grid-template-columns: 1fr; }
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
            <option value="containers">containers</option>
          </select>
        </label>
        <label>
          Line limit
          <input id="lineLimit" type="number" min="1" value="80">
        </label>
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
  </main>
  <script>
    const streams = new Map();
    const $ = (id) => document.getElementById(id);
    $("baseUrl").value = window.location.origin;

    function headers() {
      return { "X-Runtime-Control-Token": $("token").value };
    }

    function endpoint(path) {
      return new URL(path, $("baseUrl").value).toString();
    }

    async function refreshStatus() {
      const response = await fetch(endpoint("/runtime/status"), { headers: headers() });
      const text = await response.text();
      if (!response.ok) {
        throw new Error(text || `HTTP ${response.status}`);
      }
      const status = JSON.parse(text);
      renderStatus(status);
      append("statusStream", "snapshot", status);
    }

    function renderStatus(status) {
      const values = [
        ["state", status.runtimeState],
        ["operation", status.operation],
        ["version", status.runtimeVersion],
        ["updated", status.updatedAt],
        ["url", status.vitalServerURL],
        ["vm", status.vm?.ipAddress || status.vmIP || ""]
      ];
      $("statusMetrics").innerHTML = values.map(([key, value]) => (
        `<div class="metric"><span>${escapeHtml(key)}</span><strong>${escapeHtml(String(value || "-"))}</strong></div>`
      )).join("");
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
      append(outputId, parsed.event || "message", { id: parsed.id, comment: parsed.comment, data });
      if (outputId === "statusStream" && parsed.data) {
        try { renderStatus(JSON.parse(parsed.data)); } catch (_) {}
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

    function escapeHtml(value) {
      return value.replace(/[&<>"']/g, (char) => ({
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
    $("logSource").addEventListener("change", () => streams.has("logs") && connectStream("logs", `/host/logs/stream?source=${encodeURIComponent($("logSource").value)}&lineLimit=${encodeURIComponent($("lineLimit").value)}`, "logStream", "logState", "logDot"));
    setInterval(() => { $("clock").textContent = new Date().toLocaleString(); }, 1000);
    refreshStatus().catch((error) => append("statusStream", "error", { message: error.message }));
  </script>
</body>
</html>
"""#
}
