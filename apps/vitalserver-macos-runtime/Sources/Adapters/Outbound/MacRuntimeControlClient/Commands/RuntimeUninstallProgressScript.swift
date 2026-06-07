enum RuntimeUninstallProgressScript {
    static let completedMarker = "uninstall process completed exitCode=0"
    static let failedMarkerPrefix = "uninstall process failed exitCode="
    static let terminalTitle = "VitalServer uninstall progress"
    static let terminalCompletedMessage = "Uninstall completed."
    static let terminalFailedMessage = "Uninstall failed. Check the log above."
    static let terminalOpenFailedMessage = "uninstall progress viewer failed to open"

    static func viewerScript(logPath: String, shellQuote: (String) -> String) -> String {
        """
        #!/usr/bin/env bash
        set -u
        log_file=\(shellQuote(logPath))
        printf "\(terminalTitle)\\n"
        printf "Log: %s\\n\\n" "${log_file}"
        touch "${log_file}" 2>/dev/null || true
        tail -n 0 -F "${log_file}" &
        tail_pid=$!
        while true; do
          if grep -q "\(completedMarker)" "${log_file}" 2>/dev/null; then
            kill "${tail_pid}" 2>/dev/null || true
            wait "${tail_pid}" 2>/dev/null || true
            printf "\\n\(terminalCompletedMessage)\\n"
            break
          fi
          if grep -q "\(failedMarkerPrefix)" "${log_file}" 2>/dev/null; then
            kill "${tail_pid}" 2>/dev/null || true
            wait "${tail_pid}" 2>/dev/null || true
            printf "\\n\(terminalFailedMessage)\\n"
            break
          fi
          sleep 1
        done
        printf "Press Return to close this window."
        read -r _
        """
    }

    static func startScript(
        command: String,
        logPath: String,
        previousLogPath: String,
        viewerScriptPath: String,
        shellQuote: (String) -> String
    ) -> String {
        let viewerScript = viewerScript(logPath: logPath, shellQuote: shellQuote)
        return """
        log_file=\(shellQuote(logPath))
        previous_log_file=\(shellQuote(previousLogPath))
        viewer_script=\(shellQuote(viewerScriptPath))
        if [ -s "${log_file}" ]; then
          cp "${log_file}" "${previous_log_file}"
        fi
        : > "${log_file}"
        printf %s \(shellQuote(viewerScript)) > "${viewer_script}"
        chmod 0755 "${viewer_script}"
        if ! open -a Terminal "${viewer_script}" >/dev/null 2>&1; then
          echo "\(terminalOpenFailedMessage)" >> "${log_file}"
        fi
        {
          \(command)
          background_status=$?
          if [ "${background_status}" -eq 0 ]; then
            echo "\(completedMarker)"
          else
            echo "\(failedMarkerPrefix)${background_status}"
          fi
          exit "${background_status}"
        } < /dev/null >> "${log_file}" 2>&1 &
        background_pid=$!
        sleep 0.2
        if kill -0 "${background_pid}" 2>/dev/null; then
          echo "Background uninstaller started."
        else
          wait "${background_pid}"
        fi
        """
    }
}
