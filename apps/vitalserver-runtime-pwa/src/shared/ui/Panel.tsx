import type { PropsWithChildren, ReactNode } from "react";

import { cn } from "./cn";

export type PanelProps = PropsWithChildren<{
  title: string;
  actions?: ReactNode;
  className?: string;
  headerClassName?: string;
}>;

export function Panel({
  title,
  actions,
  children,
  className,
  headerClassName
}: PanelProps) {
  return (
    <section className={cn("panel", className)}>
      <div className={cn("panel-header", headerClassName)}>
        <h2>{title}</h2>
        {actions ? <div className="panel-actions">{actions}</div> : null}
      </div>
      {children}
    </section>
  );
}
