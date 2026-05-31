import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { Button } from "./Button";
import { CommandResult } from "./CommandResult";
import { ConfirmButton } from "./ConfirmButton";
import { DataTable } from "./DataTable";
import { ErrorState } from "./ErrorState";
import { KeyValueRows } from "./KeyValueRows";
import { MetricStrip } from "./MetricStrip";
import { Panel } from "./Panel";
import { StatusBadge } from "./StatusBadge";
import { cn } from "./cn";

describe("shared components", () => {
  it("renders button variants and keeps button as the default type", () => {
    render(
      <Button tone="danger" className="extra">
        Delete
      </Button>
    );

    const button = screen.getByRole("button", { name: "Delete" });
    expect(button).toHaveAttribute("type", "button");
    expect(button).toHaveClass("ui-button-danger", "extra");
  });

  it("confirms before firing destructive button actions", () => {
    const onClick = vi.fn();
    const confirm = vi.spyOn(globalThis, "confirm").mockReturnValue(false);

    const { rerender } = render(
      <ConfirmButton confirmMessage="Sure?" onClick={onClick}>
        Run
      </ConfirmButton>
    );

    fireEvent.click(screen.getByRole("button", { name: "Run" }));
    expect(confirm).toHaveBeenCalledWith("Sure?");
    expect(onClick).not.toHaveBeenCalled();

    confirm.mockReturnValue(true);
    rerender(
      <ConfirmButton confirmMessage="Sure?" onClick={onClick}>
        Run
      </ConfirmButton>
    );
    fireEvent.click(screen.getByRole("button", { name: "Run" }));
    expect(onClick).toHaveBeenCalledTimes(1);

    confirm.mockRestore();
  });

  it("renders command output, empty state, and error state", () => {
    const { rerender } = render(<CommandResult error={null} />);
    expect(screen.getByText("No operation has completed yet.")).toBeInTheDocument();

    rerender(
      <CommandResult
        error={null}
        result={{ result: { exitCode: 0, stdout: "ok", stderr: "" } }}
      />
    );
    expect(screen.getByText(/exitCode: 0/)).toHaveTextContent("ok");

    rerender(<CommandResult error={new Error("boom")} />);
    expect(screen.getByRole("alert")).toHaveTextContent("boom");
  });

  it("renders selectable tables and empty table state", () => {
    const onSelect = vi.fn();
    const { rerender } = render(
      <DataTable
        emptyText="No rows"
        rows={[{ id: "a", name: "Alpha" }]}
        selectedKey="a"
        getRowKey={(row) => row.id}
        onSelectRow={onSelect}
        columns={[
          { key: "name", header: "Name", render: (row) => row.name },
          { key: "id", header: "ID", render: (row) => row.id }
        ]}
      />
    );

    expect(screen.getAllByText("Alpha").length).toBeGreaterThan(0);
    fireEvent.click(screen.getByRole("row", { name: /Alpha/ }));
    expect(onSelect).toHaveBeenCalledWith({ id: "a", name: "Alpha" });
    fireEvent.click(screen.getByRole("button", { name: /Alpha/ }));
    expect(onSelect).toHaveBeenCalledTimes(2);

    rerender(
      <DataTable
        emptyText="No rows"
        rows={[]}
        getRowKey={(row: { id: string }) => row.id}
        columns={[]}
      />
    );
    expect(screen.getByText("No rows")).toBeInTheDocument();
  });

  it("renders common layout primitives", () => {
    render(
      <Panel title="Panel title" actions={<Button>Action</Button>}>
        <KeyValueRows
          className="kv"
          rows={[{ label: "State", value: "Ready", detail: "fresh" }]}
        />
        <MetricStrip metrics={[{ label: "Events", value: 3 }]} />
        <StatusBadge tone="success">Healthy</StatusBadge>
      </Panel>
    );

    expect(screen.getByRole("heading", { name: "Panel title" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Action" })).toBeInTheDocument();
    expect(screen.getByText("Ready")).toBeInTheDocument();
    expect(screen.getByText("fresh")).toBeInTheDocument();
    expect(screen.getByText("Events")).toBeInTheDocument();
    expect(screen.getByText("Healthy")).toHaveClass("status-badge-success");
  });

  it("renders summarized runtime errors and joins class names", () => {
    render(<ErrorState title="Custom failure" error={new TypeError("Failed to fetch")} />);

    expect(screen.getByRole("alert")).toHaveTextContent("Custom failure");
    expect(screen.getByRole("alert")).toHaveTextContent(
      "The Remote Console could not reach the Runtime Control API endpoint."
    );
    expect(cn("a", false, "b")).toBe("a b");
  });
});
