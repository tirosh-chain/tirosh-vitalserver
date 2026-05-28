import { Panel } from "./Panel";

export function PlaceholderPage({ title }: { title: string }) {
  return (
    <Panel title={title}>
      <p className="empty-state">
        This PWA section is scaffolded. The Runtime Control API client boundary
        is in place, and the Swift UI parity view will be added next.
      </p>
    </Panel>
  );
}
