import type { RuntimeCommandResponse } from "../../domain/runtime-control/contracts/runtimeControlTypes";

export function CommandResult({
  result,
  error,
  emptyText = "No operation has completed yet."
}: {
  result?: RuntimeCommandResponse;
  error: Error | null;
  emptyText?: string;
}) {
  if (error) {
    return <p className="error-state">{String(error)}</p>;
  }

  if (!result) {
    return <p className="muted">{emptyText}</p>;
  }

  return (
    <pre className="command-output">
      {[
        `exitCode: ${result.result?.exitCode ?? "unknown"}`,
        result.result?.stdout ?? "",
        result.result?.stderr ?? ""
      ]
        .filter(Boolean)
        .join("\n")}
    </pre>
  );
}
