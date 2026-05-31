import type { ReactNode } from "react";

import { cn } from "./cn";

export type Metric = {
  label: string;
  value: ReactNode;
};

export function MetricStrip({
  metrics,
  className
}: {
  metrics: Metric[];
  className?: string;
}) {
  return (
    <div className={cn("metric-strip", className)}>
      {metrics.map((metric) => (
        <div key={metric.label} className="metric">
          <span>{metric.label}</span>
          <strong>{metric.value}</strong>
        </div>
      ))}
    </div>
  );
}
