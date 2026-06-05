import type { ReactNode } from "react";

import { cn } from "./cn";

export type KeyValueRow = {
  label: string;
  value: ReactNode;
  detail?: ReactNode;
};

export function KeyValueRows({
  rows,
  className
}: {
  rows: KeyValueRow[];
  className?: string;
}) {
  return (
    <dl className={cn("key-value-rows", className)}>
      {rows.map((row) => (
        <div key={row.label} className="key-value-row">
          <dt>{row.label}</dt>
          <dd>
            <span>{row.value}</span>
            {row.detail ? <span className="muted detail">{row.detail}</span> : null}
          </dd>
        </div>
      ))}
    </dl>
  );
}
