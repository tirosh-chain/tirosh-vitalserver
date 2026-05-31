import type { ReactNode } from "react";

import { cn } from "./cn";

export type StatusBadgeProps = {
  tone: "success" | "warning" | "danger" | "neutral";
  children: ReactNode;
  className?: string;
};

export function StatusBadge({ tone, children, className }: StatusBadgeProps) {
  return (
    <span className={cn("status-badge", `status-badge-${tone}`, className)}>
      {children}
    </span>
  );
}
