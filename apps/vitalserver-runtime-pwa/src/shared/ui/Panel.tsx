import type { PropsWithChildren, ReactNode } from "react";

export type PanelProps = PropsWithChildren<{
  title: string;
  actions?: ReactNode;
}>;

export function Panel({ title, actions, children }: PanelProps) {
  return (
    <section className="panel">
      <div className="panel-header">
        <h2>{title}</h2>
        {actions ? <div className="panel-actions">{actions}</div> : null}
      </div>
      {children}
    </section>
  );
}
