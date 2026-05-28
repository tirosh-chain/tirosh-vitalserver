import { summarizeRuntimeControlError } from "../../domain/runtime-control/errors/runtimeControlError";

export function ErrorState({
  error,
  title
}: {
  error: unknown;
  title?: string;
}) {
  const summary = summarizeRuntimeControlError(error);

  return (
    <div className="error-state" role="alert">
      <strong>{title ?? summary.title}</strong>
      <span>{summary.detail}</span>
      <small>{summary.recovery}</small>
    </div>
  );
}
