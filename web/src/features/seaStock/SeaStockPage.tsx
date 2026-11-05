import { useState } from 'react'
import { useViewer } from '../../app/viewer'
import { Button } from '../../components/Button'
import { DataTable } from '../../components/DataTable'
import { Icon } from '../../components/icons'
import { PageHeader } from '../../components/layout/PageHeader'
import { Card, Muted, PageBody } from '../../components/Page'
import { FilterBar, useScopeFilter } from '../../components/ScopeFilters'
import { SelectField } from '../../components/SelectField'
import { SyncAge } from '../../components/StockBadges'
import { Tabs } from '../../components/Tabs'
import { TextField } from '../../components/TextField'
import type { ComponentType, Vessel } from '../../data/model'
import { customerById, oldestSync, stockByProduct, stockLines, totals, vesselById } from '../../data/queries'
import { useStore } from '../../data/store'
import { downloadCsv } from '../../lib/csv'
import { componentOptions, itemMatches } from '../../lib/filters'
import { formatLiters } from '../../lib/format'
import { groupOfVessel, rollUpLabels, rollUpsFor, type RollUp } from '../../lib/rollUp'
import { StockTable, TotalsLine } from './StockTable'
import { VesselDetails } from './VesselDetails'

interface GroupRow {
  key: string
  name: string
  vessels: Vessel[]
  products: number
  cans: number
  liters: number
}

/**
 * FR-20 Sea Stock for any vessel in scope, rolled up by product, vessel or customer
 * (FR-24), with CSV export. Picking one vessel shows its details: this is also the vessel page.
 */
export function SeaStockPage() {
  useStore()
  const { user } = useViewer()
  const scope = useScopeFilter()
  const rollUps = rollUpsFor[user.role]
  const [by, setBy] = useState<RollUp>('product')
  const [component, setComponent] = useState<ComponentType | ''>('')
  const [search, setSearch] = useState('')

  const ids = scope.vessels.map((v) => v.id)
  const lines = stockLines(ids).filter((l) => itemMatches(l.item, component, search))
  const products = stockByProduct(ids).filter((p) => itemMatches(p.item, component, search))
  const sum = totals(lines)
  const single = scope.vessels.length === 1 ? scope.vessels[0] : undefined
  const view: RollUp = single ? 'product' : by

  const groups = new Map<string, GroupRow>()
  if (view !== 'product') {
    for (const v of scope.vessels) {
      const g = groupOfVessel(v, view)
      const own = lines.filter((l) => l.vessel === v.id)
      const t = totals(own)
      const row = groups.get(g.key) ?? {
        key: g.key,
        name: g.name,
        vessels: [],
        products: 0,
        cans: 0,
        liters: 0,
      }
      row.vessels.push(v)
      row.cans += t.cans
      row.liters += t.liters
      row.products = new Set([
        ...lines
          .filter((l) => row.vessels.some((x) => x.id === l.vessel))
          .map((l) => l.item.articleNo),
      ]).size
      groups.set(g.key, row)
    }
  }
  const groupRows = [...groups.values()].sort((a, b) => a.name.localeCompare(b.name))

  const exportSummary = () =>
    view === 'product'
      ? downloadCsv(
          'sea-stock-by-product.csv',
          [
            'Article no.',
            'Product',
            'Shade',
            'Component type',
            'Pack size',
            'Vessels',
            'Cans',
            'Liters',
          ],
          products.map((p) => [
            p.item.articleNo,
            p.item.product,
            p.item.shade,
            p.item.componentType,
            p.item.packSize,
            p.vessels,
            p.cans,
            p.liters,
          ]),
        )
      : downloadCsv(
          `sea-stock-by-${view}.csv`,
          [rollUpLabels[view], 'Vessels', 'Products', 'Cans', 'Liters'],
          groupRows.map((g) => [g.name, g.vessels.length, g.products, g.cans, g.liters]),
        )

  const exportDetail = () =>
    downloadCsv(
      'sea-stock-detail.csv',
      [
        'Customer',
        'Customer code',
        'Vessel',
        'IMO',
        'Article no.',
        'Product',
        'Shade',
        'Component type',
        'Pack size',
        'Cans',
        'Liters',
        'Last sync (UTC)',
      ],
      lines.map((l) => {
        const v = vesselById(l.vessel)
        const c = v && customerById(v.customer)
        return [
          c?.name ?? '',
          c?.customerCode ?? '',
          v?.name ?? '',
          v?.imo ?? '',
          l.item.articleNo,
          l.item.product,
          l.item.shade,
          l.item.componentType,
          l.item.packSize,
          l.cans,
          l.liters,
          v?.lastSync ?? '',
        ]
      }),
    )

  return (
    <>
      <PageHeader
        title="Sea Stock"
        subtitle="Paint and thinners on board, as of each vessel’s last sync"
        actions={
          <>
            <Button variant="secondary" onClick={exportSummary}>
              <Icon name="download" /> Export summary
            </Button>
            <Button variant="secondary" onClick={exportDetail}>
              <Icon name="download" /> Export detail
            </Button>
          </>
        }
      />
      <PageBody>
        <FilterBar>
          {scope.controls}
          <SelectField
            label="Component type"
            className="w-40"
            value={component}
            onChange={(e) => setComponent(e.target.value as ComponentType | '')}
            options={componentOptions}
          />
          <TextField
            label="Search"
            placeholder="Article no., product or shade"
            className="w-64"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </FilterBar>

        {single && <VesselDetails vessel={single} />}

        <Card flush>
          <div className="flex min-h-12 items-center justify-between gap-4 px-5 pt-3">
            {!single && rollUps.length > 1 ? (
              <Tabs
                label="Roll up by"
                current={by}
                onChange={setBy}
                tabs={rollUps.map((r) => ({
                  key: r,
                  label: `By ${rollUpLabels[r].toLowerCase()}`,
                }))}
              />
            ) : (
              <h2 className="text-card-title font-bold">By product</h2>
            )}
            <Muted>
              {scope.vessels.length} {scope.vessels.length === 1 ? 'vessel' : 'vessels'} ·{' '}
              {sum.cans} cans · {formatLiters(sum.liters)}
            </Muted>
          </div>
          <div className="p-4">
            {view === 'product' ? (
              <>
                <StockTable
                  rows={products.map((p) => ({ ...p, key: p.item.articleNo }))}
                  extra={
                    single
                      ? []
                      : [{ header: 'Vessels', width: 0.6, align: 'right', cell: (p) => p.vessels }]
                  }
                />
                {products.length > 0 && <TotalsLine cans={sum.cans} liters={sum.liters} />}
              </>
            ) : (
              <DataTable
                label={`Sea Stock by ${view}`}
                rows={groupRows}
                rowKey={(g) => g.key}
                empty="Nothing matches these filters"
                columns={[
                  {
                    header: rollUpLabels[view],
                    width: 1.8,
                    cell: (g) =>
                      view === 'vessel' && g.vessels[0] ? (
                        <div>
                          <button
                            type="button"
                            onClick={() => g.vessels[0] && scope.setVessel(g.vessels[0].id)}
                            className="font-semibold text-brand hover:underline"
                          >
                            {g.name}
                          </button>
                          <div>
                            <Muted>{customerById(g.vessels[0].customer)?.name}</Muted>
                          </div>
                        </div>
                      ) : (
                        <b>{g.name}</b>
                      ),
                  },
                  ...(view === 'vessel'
                    ? []
                    : [
                        {
                          header: 'Vessels',
                          width: 0.6,
                          align: 'right' as const,
                          cell: (g: GroupRow) => g.vessels.length,
                        },
                      ]),
                  { header: 'Products', width: 0.7, align: 'right', cell: (g) => g.products },
                  { header: 'Cans', width: 0.6, align: 'right', cell: (g) => g.cans },
                  {
                    header: 'Liters',
                    width: 0.8,
                    align: 'right',
                    cell: (g) => <b>{formatLiters(g.liters)}</b>,
                  },
                  {
                    header: view === 'vessel' ? 'Last sync' : 'Oldest sync',
                    width: 1.2,
                    cell: (g) => (
                      <SyncAge at={oldestSync(g.vessels)} />
                    ),
                  },
                ]}
              />
            )}
          </div>
        </Card>
      </PageBody>
    </>
  )
}
