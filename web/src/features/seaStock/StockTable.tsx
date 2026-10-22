import { DataTable, type Column } from '../../components/DataTable'
import { Mono } from '../../components/Page'
import { ComponentBadge } from '../../components/StockBadges'
import type { Item } from '../../data/model'
import { formatLiters } from '../../lib/format'

export interface StockRow {
  key: string
  item: Item
  cans: number
  liters: number
}

/** Sea Stock by product, shade and component type, in cans and liters (FR-09, FR-20). */
export function StockTable<Row extends StockRow>({
  rows,
  extra = [],
  label = 'Sea Stock',
}: {
  rows: Row[]
  extra?: Column<Row>[]
  label?: string
}) {
  return (
    <DataTable
      label={label}
      rows={rows}
      rowKey={(r) => r.key}
      empty="No Sea Stock recorded"
      columns={[
        { header: 'Article no.', width: 0.8, cell: (r) => <Mono>{r.item.articleNo}</Mono> },
        {
          header: 'Product',
          width: 1.5,
          cell: (r) => <span className="font-semibold">{r.item.product}</span>,
        },
        {
          header: 'Shade',
          width: 1.1,
          cell: (r) => r.item.shade || <span className="text-ink-subtle">—</span>,
        },
        {
          header: 'Component',
          width: 0.9,
          cell: (r) => <ComponentBadge type={r.item.componentType} />,
        },
        { header: 'Pack', width: 0.6, align: 'right', cell: (r) => r.item.packSize },
        ...extra,
        {
          header: 'Cans',
          width: 0.6,
          align: 'right',
          cell: (r) => (
            <span className={`font-semibold ${r.cans < 0 ? 'text-danger' : ''}`}>{r.cans}</span>
          ),
        },
        {
          header: 'Liters',
          width: 0.8,
          align: 'right',
          cell: (r) => (
            <span className={`font-semibold ${r.liters < 0 ? 'text-danger' : ''}`}>
              {formatLiters(r.liters)}
            </span>
          ),
        },
      ]}
    />
  )
}

/** Totals line under a stock table. */
export function TotalsLine({
  cans,
  liters,
  label = 'Total',
}: {
  cans: number
  liters: number
  label?: string
}) {
  return (
    <div className="mt-3 flex justify-end gap-6 px-4.5 text-body">
      <span className="text-ink-muted">{label}</span>
      <span className="font-bold">{cans} cans</span>
      <span className="w-24 text-right font-bold">{formatLiters(liters)}</span>
    </div>
  )
}
