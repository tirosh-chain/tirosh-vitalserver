import Foundation

struct RuntimeUninstallProgressScriptPlan {
    let command: String
    let logPath: String
    let previousLogPath: String
    let viewerScriptPath: String
    let workerScriptPath: String
    let workerPIDPath: String
    let runID: String

    init(
        command: String,
        logPath: String,
        previousLogPath: String,
        viewerScriptPath: String,
        workerScriptPath: String? = nil,
        workerPIDPath: String? = nil,
        runID: String = UUID().uuidString
    ) {
        self.command = command
        self.logPath = logPath
        self.previousLogPath = previousLogPath
        self.viewerScriptPath = viewerScriptPath
        self.workerScriptPath = workerScriptPath ?? "\(viewerScriptPath).worker"
        self.workerPIDPath = workerPIDPath ?? "\(viewerScriptPath).pid"
        self.runID = runID
    }
}

enum RuntimeUninstallProgressScript {
    static let startedMarker = "uninstall process started"
    static let completedMarker = "uninstall process completed exitCode=0"
    static let failedMarkerPrefix = "uninstall process failed exitCode="
    static let missingMarkerStatus = "missing-marker"
    static let terminalTitle = "VitalServer uninstall progress"
    static let terminalCompletedMessage = "Uninstall completed."
    static let terminalFailedMessage = "Uninstall failed. Check the log above."
    static let terminalOpenFailedMessage = "uninstall progress viewer failed to open"

    static func viewerScript(
        logPath: String,
        workerPIDPath: String,
        runID: String = UUID().uuidString,
        shellQuote: (String) -> String
    ) -> String {
        """
        #!/usr/bin/env bash
        set -u
        log_file=\(shellQuote(logPath))
        worker_pid_file=\(shellQuote(workerPIDPath))
        marker_run_id=\(shellQuote("runID=\(runID)"))
        completed_marker=\(shellQuote("\(completedMarker) runID=\(runID)"))
        failed_marker_prefix=\(shellQuote(failedMarkerPrefix))
        started_marker=\(shellQuote("\(startedMarker) runID=\(runID)"))
        observed_worker_start=false
        printf "\(terminalTitle)\\n"
        printf "Log: %s\\n\\n" "${log_file}"
        touch "${log_file}" 2>/dev/null || true
        tail -n 0 -F "${log_file}" &
        tail_pid=$!
        finish_tail() {
          kill "${tail_pid}" 2>/dev/null || true
          wait "${tail_pid}" 2>/dev/null || true
        }
        has_terminal_marker() {
          grep -q "${completed_marker}" "${log_file}" 2>/dev/null \
            || grep -q "${failed_marker_prefix}.*${marker_run_id}" "${log_file}" 2>/dev/null
        }
        wait_for_terminal_marker() {
          for _ in 1 2 3 4 5 6 7 8 9 10; do
            if has_terminal_marker; then
              return 0
            fi
            sleep 0.2
          done
          return 1
        }
        current_worker_pid() {
          if [ ! -s "${worker_pid_file}" ]; then
            return 1
          fi
          if ! grep -qx "${marker_run_id}" "${worker_pid_file}" 2>/dev/null; then
            return 1
          fi
          sed -n '2p' "${worker_pid_file}" 2>/dev/null
        }
        while true; do
          if grep -q "${completed_marker}" "${log_file}" 2>/dev/null; then
            finish_tail
            printf "\\n\(terminalCompletedMessage)\\n"
            break
          fi
          if grep -q "${failed_marker_prefix}.*${marker_run_id}" "${log_file}" 2>/dev/null; then
            finish_tail
            printf "\\n\(terminalFailedMessage)\\n"
            break
          fi
          if grep -q "${started_marker}" "${log_file}" 2>/dev/null; then
            observed_worker_start=true
          fi
          worker_pid="$(current_worker_pid || true)"
          if [ -n "${worker_pid}" ]; then
            if [ "${observed_worker_start}" = true ] && [ -n "${worker_pid}" ] && ! kill -0 "${worker_pid}" 2>/dev/null; then
              if wait_for_terminal_marker; then
                continue
              fi
              rm -f "${worker_pid_file}" 2>/dev/null || true
              finish_tail
              printf "\\n\(terminalFailedMessage)\\n"
              break
            fi
          fi
          sleep 1
        done
        printf "Press Return to close this window."
        read -r _
        """
    }

    static func workerScript(
        plan: RuntimeUninstallProgressScriptPlan,
        shellQuote: (String) -> String
    ) -> String {
        """
        #!/usr/bin/env bash
        set +e
        log_file=\(shellQuote(plan.logPath))
        worker_pid_file=\(shellQuote(plan.workerPIDPath))
        marker_run_id=\(shellQuote("runID=\(plan.runID)"))
        started_marker=\(shellQuote("\(startedMarker) runID=\(plan.runID)"))
        completed_marker=\(shellQuote("\(completedMarker) runID=\(plan.runID)"))
        failed_marker_prefix=\(shellQuote(failedMarkerPrefix))

        has_terminal_marker() {
          grep -q "${completed_marker}" "${log_file}" 2>/dev/null \
            || grep -q "${failed_marker_prefix}.*${marker_run_id}" "${log_file}" 2>/dev/null
        }

        cleanup_pid_file() {
          rm -f "${worker_pid_file}" 2>/dev/null || true
        }

        mark_signal_failure() {
          signal_name="$1"
          if ! has_terminal_marker; then
            echo "${failed_marker_prefix}signal-${signal_name} ${marker_run_id}" >> "${log_file}"
          fi
          cleanup_pid_file
          exit 129
        }

        trap 'mark_signal_failure HUP' HUP
        trap 'mark_signal_failure TERM' TERM
        trap 'cleanup_pid_file' EXIT

        {
          echo "${started_marker}"
          \(plan.command)
          background_status=$?
          if [ "${background_status}" -eq 0 ]; then
            echo "${completed_marker}"
          else
            echo "${failed_marker_prefix}${background_status} ${marker_run_id}"
          fi
          cleanup_pid_file
          exit "${background_status}"
        } >> "${log_file}" 2>&1
        """
    }

    static func startScript(
        command: String,
        logPath: String,
        previousLogPath: String,
        viewerScriptPath: String,
        shellQuote: (String) -> String
    ) -> String {
        startScript(
            plan: RuntimeUninstallProgressScriptPlan(
                command: command,
                logPath: logPath,
                previousLogPath: previousLogPath,
                viewerScriptPath: viewerScriptPath
            ),
            shellQuote: shellQuote
        )
    }

    static func startScript(
        plan: RuntimeUninstallProgressScriptPlan,
        shellQuote: (String) -> String
    ) -> String {
        let viewerScript = viewerScript(
            logPath: plan.logPath,
            workerPIDPath: plan.workerPIDPath,
            runID: plan.runID,
            shellQuote: shellQuote
        )
        let workerScript = workerScript(plan: plan, shellQuote: shellQuote)
        return """
        log_file=\(shellQuote(plan.logPath))
        previous_log_file=\(shellQuote(plan.previousLogPath))
        viewer_script=\(shellQuote(plan.viewerScriptPath))
        worker_script=\(shellQuote(plan.workerScriptPath))
        worker_pid_file=\(shellQuote(plan.workerPIDPath))
        marker_run_id=\(shellQuote("runID=\(plan.runID)"))
        started_marker=\(shellQuote("\(startedMarker) runID=\(plan.runID)"))
        completed_marker=\(shellQuote("\(completedMarker) runID=\(plan.runID)"))
        failed_marker_prefix=\(shellQuote(failedMarkerPrefix))
        if [ -s "${log_file}" ]; then
          cp "${log_file}" "${previous_log_file}"
        fi
        : > "${log_file}"
        chmod 0644 "${log_file}" 2>/dev/null || true
        rm -f "${worker_pid_file}"
        printf %s \(shellQuote(viewerScript)) > "${viewer_script}"
        printf %s \(shellQuote(workerScript)) > "${worker_script}"
        chmod 0755 "${viewer_script}"
        chmod 0755 "${worker_script}"
        if ! open -a Terminal "${viewer_script}" >/dev/null 2>&1; then
          echo "\(terminalOpenFailedMessage)" >> "${log_file}"
        fi
        /bin/bash "${worker_script}" </dev/null >> "${log_file}" 2>&1 &
        background_pid=$!
        {
          echo "${marker_run_id}"
          echo "${background_pid}"
        } > "${worker_pid_file}"
        chmod 0644 "${worker_pid_file}" 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
          if grep -q "${started_marker}" "${log_file}" 2>/dev/null \
            || grep -q "${completed_marker}" "${log_file}" 2>/dev/null \
            || grep -q "${failed_marker_prefix}.*${marker_run_id}" "${log_file}" 2>/dev/null; then
            echo "Background uninstaller started."
            exit 0
          fi
          if ! kill -0 "${background_pid}" 2>/dev/null; then
            wait "${background_pid}"
            background_status=$?
            if ! grep -q "${completed_marker}" "${log_file}" 2>/dev/null \
              && ! grep -q "${failed_marker_prefix}.*${marker_run_id}" "${log_file}" 2>/dev/null; then
              echo "${failed_marker_prefix}${background_status} ${marker_run_id}" >> "${log_file}"
            fi
            rm -f "${worker_pid_file}"
            exit "${background_status}"
          fi
          sleep 0.5
        done
        echo "\(failedMarkerPrefix)\(missingMarkerStatus) ${marker_run_id}" >> "${log_file}"
        exit 1
        """
    }
}
