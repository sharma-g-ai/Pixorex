import type { ReactNode } from 'react'

export interface Column<Row> {
  header: string
  /** Relative width, as a CSS grid fraction (default 1). */
  width?: number
  align?: 'left' | 'right'
  cell: (row: Row) => ReactNode
}

interface DataTableProps<Row> {
  /** Accessible name of the table. */
  label: string
  columns: Column<Row>[]
  rows: Row[]
  rowKey: (row: Row) => string
  /** Shown instead of rows when there are none. */
  empty: ReactNode
}

/** Bordered table with a grey header row (canvas list style). */
export function DataTable<Row>({ label, columns, rows, rowKey, empty }: DataTableProps<Row>) {
  const template = columns.map((c) => `minmax(0,${c.width ?? 1}fr)`).join(' ')
  const align = (c: Column<Row>) => (c.align === 'right' ? 'text-right' : '')

  return (
    <div role="table" aria-label={label} className="overflow-hidden rounded-xl border border-line">
      <div
        role="row"
        className="grid gap-3.5 border-b border-line bg-table-head px-4.5 py-2.75 text-caption font-bold tracking-wider text-ink-subtle uppercase"
        style={{ gridTemplateColumns: template }}
      >
        {columns.map((c, i) => (
          <div key={i} role="columnheader" className={align(c)}>
            {c.header}
          </div>
        ))}
      </div>
      {rows.length === 0 ? (
        <div className="px-4.5 py-6 text-center text-body text-ink-muted">{empty}</div>
      ) : (
        rows.map((row) => (
          <div
            key={rowKey(row)}
            role="row"
            className="grid items-center gap-3.5 border-b border-line-soft px-4.5 py-3 text-body last:border-b-0"
            style={{ gridTemplateColumns: template }}
          >
            {columns.map((c, i) => (
              <div key={i} role="cell" className={`min-w-0 ${align(c)}`}>
                {c.cell(row)}
              </div>
            ))}
          </div>
        ))
      )}
    </div>
  )
}
