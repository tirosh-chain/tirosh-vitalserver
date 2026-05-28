import type { ReactNode } from "react";

export type DataTableColumn<T> = {
  key: string;
  header: string;
  render: (row: T) => ReactNode;
  className?: string;
};

export type DataTableProps<T> = {
  columns: DataTableColumn<T>[];
  rows: T[];
  getRowKey: (row: T) => string;
  selectedKey?: string | null;
  onSelectRow?: (row: T) => void;
  emptyText: string;
};

export function DataTable<T>({
  columns,
  rows,
  getRowKey,
  selectedKey,
  onSelectRow,
  emptyText
}: DataTableProps<T>) {
  if (rows.length === 0) {
    return <p className="empty-state">{emptyText}</p>;
  }

  return (
    <>
      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              {columns.map((column) => (
                <th key={column.key} className={column.className}>
                  {column.header}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => {
              const rowKey = getRowKey(row);
              const selected = selectedKey === rowKey;
              return (
                <tr
                  key={rowKey}
                  className={selected ? "selected-row" : undefined}
                  onClick={onSelectRow ? () => onSelectRow(row) : undefined}
                >
                  {columns.map((column) => (
                    <td key={column.key} className={column.className}>
                      {column.render(row)}
                    </td>
                  ))}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <div className="data-card-list">
        {rows.map((row) => {
          const rowKey = getRowKey(row);
          const selected = selectedKey === rowKey;
          const [titleColumn, ...detailColumns] = columns;
          const Tag = onSelectRow ? "button" : "article";
          return (
            <Tag
              key={rowKey}
              type={onSelectRow ? "button" : undefined}
              className={selected ? "data-card selected-row" : "data-card"}
              onClick={onSelectRow ? () => onSelectRow(row) : undefined}
            >
              <div className="data-card-title">
                {titleColumn ? titleColumn.render(row) : rowKey}
              </div>
              <dl className="data-card-rows">
                {detailColumns.map((column) => (
                  <div key={column.key} className="data-card-row">
                    <dt>{column.header}</dt>
                    <dd>{column.render(row)}</dd>
                  </div>
                ))}
              </dl>
            </Tag>
          );
        })}
      </div>
    </>
  );
}
