import type { ReactNode } from "react";

export type KeyValueRow = {
  label: string;
  value: ReactNode;
  detail?: ReactNode;
};

export function KeyValueRows({ rows }: { rows: KeyValueRow[] }) {
  return (
    <dl className="key-value-rows">
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
