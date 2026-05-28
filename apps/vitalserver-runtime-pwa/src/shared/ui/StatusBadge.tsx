import type { ReactNode } from "react";

export type StatusBadgeProps = {
  tone: "success" | "warning" | "danger" | "neutral";
  children: ReactNode;
};

export function StatusBadge({ tone, children }: StatusBadgeProps) {
  return <span className={`status-badge status-badge-${tone}`}>{children}</span>;
}
