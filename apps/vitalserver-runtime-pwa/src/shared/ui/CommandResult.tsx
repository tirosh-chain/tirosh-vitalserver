import type { RuntimeCommandResponse } from "../../domain/runtime-control/contracts/runtimeControlTypes";
import { ErrorState } from "./ErrorState";

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
    return <ErrorState error={error} />;
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
