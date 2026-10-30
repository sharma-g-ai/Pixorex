import { useState } from 'react'
import { useViewer } from '../../app/viewer'
import { Button } from '../../components/Button'
import { DataTable } from '../../components/DataTable'
import { Icon } from '../../components/icons'
import { PageHeader } from '../../components/layout/PageHeader'
import { Card, Muted, Note, PageBody } from '../../components/Page'
import { usePeriod } from '../../components/PeriodPicker'
import { FilterBar, useScopeFilter } from '../../components/ScopeFilters'
import { ComponentBadge } from '../../components/StockBadges'
import { Tabs } from '../../components/Tabs'
import type { Transaction } from '../../data/model'
import {
  consumptionLines,
  customerById,
  itemByArticle,
  liters,
  vesselById,
} from '../../data/queries'
import { downloadCsv } from '../../lib/csv'
import { formatDate, formatLiters } from '../../lib/format'
import { rollUpLabels, rollUpsFor, type RollUp } from '../../lib/rollUp'

type GroupBy = RollUp

interface Group {
  key: string
  name: string
  cans: number
  liters: number
  scans: number
}

function groupKey(t: Transaction, by: GroupBy): { key: string; name: string } {
  const vessel = vesselById(t.vessel)
  const customer = vessel && customerById(vessel.customer)
  const item = itemByArticle(t.articleNo)
  switch (by) {
    case 'product':
      return {
        key: t.articleNo,
        name: `${item?.product ?? t.articleNo}${item?.shade ? ` · ${item.shade}` : ''}`,
      }
    case 'vessel':
      return { key: t.vessel, name: vessel?.name ?? t.vessel }
    case 'customer':
      return { key: customer?.id ?? '', name: customer?.name ?? '' }
  }
}

/** Consumption (FR-07 deductions) rolled up by product, vessel or customer (FR-24). */
export function ConsumptionPage() {
  const { user } = useViewer()
  const rollUps = rollUpsFor[user.role]
  const scope = useScopeFilter()
  const period = usePeriod()
  const [by, setBy] = useState<GroupBy>('product')
  const lines = consumptionLines(
    scope.vessels.map((v) => v.id),
    period.from,
    period.to,
  )

  const groups = new Map<string, Group>()
  for (const t of lines) {
    const { key, name } = groupKey(t, by)
    const g = groups.get(key) ?? { key, name, cans: 0, liters: 0, scans: 0 }
    g.cans -= t.cans
    g.liters -= liters(t.articleNo, t.cans)
    g.scans += 1
    groups.set(key, g)
  }
  const rows = [...groups.values()].sort((a, b) => b.liters - a.liters)
  const sum = rows.reduce(
    (acc, r) => ({ cans: acc.cans + r.cans, liters: acc.liters + r.liters }),
    { cans: 0, liters: 0 },
  )
  const max = Math.max(1, ...rows.map((r) => r.liters))
  const groupLabel = rollUpLabels[by]
  const exportSummary = () =>
    downloadCsv(
      `consumption-by-${by}-${period.from}-to-${period.to}.csv`,
      [groupLabel, 'Scans', 'Cans', 'Liters'],
      rows.map((r) => [r.name, r.scans, r.cans, r.liters]),
    )

  return (
    <>
      <PageHeader
        title="Consumption"
        subtitle="Cans taken from the locker for a job, each counted as used in full"
        actions={
          <>
            <Button variant="secondary" onClick={exportSummary}>
              <Icon name="download" /> Export summary
            </Button>
            <Button
              variant="secondary"
              onClick={() =>
                downloadCsv(
                  `consumption-${period.from}-to-${period.to}.csv`,
                  [
                    'Date',
                    'Customer',
                    'Vessel',
                    'IMO',
                    'Article no.',
                    'Product',
                    'Shade',
                    'Component type',
                    'Pack size',
                    'Cans',
                    'Liters',
                  ],
                  lines.map((t) => {
                    const v = vesselById(t.vessel)
                    const item = itemByArticle(t.articleNo)
                    return [
                      t.recordedAt.slice(0, 10),
                      customerById(v?.customer ?? '')?.name ?? '',
                      v?.name ?? '',
                      v?.imo ?? '',
                      t.articleNo,
                      item?.product ?? '',
                      item?.shade ?? '',
                      item?.componentType ?? '',
                      item?.packSize ?? '',
                      -t.cans,
                      -liters(t.articleNo, t.cans),
                    ]
                  }),
                )
              }
            >
              <Icon name="download" /> Export detail
            </Button>
          </>
        }
      />
      <PageBody>
        <FilterBar>
          {period.controls}
          {scope.controls}
        </FilterBar>

        <Card flush>
          <div className="flex items-center justify-between gap-4 px-5 pt-3">
            <Tabs
              label="Group by"
              current={by}
              onChange={setBy}
              tabs={rollUps.map((r) => ({ key: r, label: `By ${rollUpLabels[r].toLowerCase()}` }))}
            />
            <Muted>
              {formatDate(period.from)} – {formatDate(period.to)} · {sum.cans} cans ·{' '}
              {formatLiters(sum.liters)}
            </Muted>
          </div>
          <div className="p-4">
            <DataTable
              label={`Consumption by ${by}`}
              rows={rows}
              rowKey={(r) => r.key}
              empty="No consumption recorded in this period"
              columns={[
                {
                  header: groupLabel,
                  width: 2,
                  cell: (r) => {
                    const item = by === 'product' ? itemByArticle(r.key) : undefined
                    return (
                      <div className="flex min-w-0 items-center gap-2">
                        <span className="truncate font-semibold">{r.name}</span>
                        {item && <ComponentBadge type={item.componentType} />}
                      </div>
                    )
                  },
                },
                {
                  header: 'Share of liters',
                  width: 2,
                  cell: (r) => (
                    <div className="h-2 rounded-full bg-line-soft" aria-hidden="true">
                      <div
                        className="h-2 rounded-full bg-brand"
                        style={{ width: `${(r.liters / max) * 100}%` }}
                      />
                    </div>
                  ),
                },
                { header: 'Scans', width: 0.6, align: 'right', cell: (r) => r.scans },
                { header: 'Cans', width: 0.6, align: 'right', cell: (r) => r.cans },
                {
                  header: 'Liters',
                  width: 0.8,
                  align: 'right',
                  cell: (r) => <b>{formatLiters(r.liters)}</b>,
                },
              ]}
            />
          </div>
        </Card>

        <Note>
          Returns to the locker are not scanned and opened cans are not tracked by the liter (BRD
          §10). Consumption here is what was scanned out and has synced.
        </Note>
      </PageBody>
    </>
  )
}
