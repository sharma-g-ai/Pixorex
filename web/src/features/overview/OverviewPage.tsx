import { Link } from 'react-router'
import { useViewer } from '../../app/viewer'
import { PageHeader } from '../../components/layout/PageHeader'
import { Card, PageBody } from '../../components/Page'
import { StatTile } from '../../components/StatTile'
import {
  consumedTotals,
  consumptionLines,
  daysAgo,
  negativeStock,
  scopeLabel,
  stockLines,
  totals,
  unrecognisedFor,
  visibleCustomers,
  visibleVessels,
} from '../../data/queries'
import { can, roleInfo } from '../../data/roles'
import { NOW } from '../../data/sample'
import { useStore } from '../../data/store'
import { formatCans, formatLiters } from '../../lib/format'
import { RecentActivity } from '../activity/RecentActivity'
import { lateVessels, NeedsAttention } from './NeedsAttention'

const FROM = daysAgo(29)
const TO = NOW.slice(0, 10)

/**
 * Headline numbers and what needs attention. Breakdowns by region, customer and vessel live on
 * Sea Stock and Consumption, so they are not repeated here.
 */
export function OverviewPage() {
  useStore()
  const { user } = useViewer()
  const custs = visibleCustomers(user)
  const vess = visibleVessels(user)
  const ids = vess.map((v) => v.id)
  const stock = totals(stockLines(ids))
  const consumed = consumedTotals(consumptionLines(ids, FROM, TO))
  const late = lateVessels(ids).length
  const review = can(user, 'view-review')
    ? negativeStock(ids).length + unrecognisedFor(ids).length
    : null

  return (
    <>
      <PageHeader
        title="Overview"
        subtitle={`${roleInfo(user.role).label} · ${scopeLabel(user)}`}
      />
      <PageBody>
        <div className="grid grid-cols-2 gap-3.5 lg:grid-cols-3 xl:grid-cols-6">
          {custs.length > 1 && <StatTile value={custs.length} label="Customers" />}
          <StatTile value={vess.length} label="Vessels" to="/sea-stock" />
          <StatTile
            value={formatLiters(stock.liters)}
            label={`Sea Stock · ${formatCans(stock.cans)}`}
            to="/sea-stock"
          />
          <StatTile
            value={formatLiters(consumed.liters)}
            label={`Consumed, last 30 days · ${formatCans(consumed.cans)}`}
            to="/consumption"
          />
          <StatTile value={late} label="Late or no sync" tone={late > 0 ? 'warning' : 'default'} />
          {review !== null && (
            <StatTile
              value={review}
              label="Need review"
              tone={review > 0 ? 'warning' : 'default'}
            />
          )}
        </div>

        <div className="grid gap-5 xl:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
          <NeedsAttention />
          <div>
            <Card
              title="Recent activity"
              actions={
                <Link
                  to="/activity"
                  className="text-small font-semibold text-brand hover:underline"
                >
                  All activity →
                </Link>
              }
            >
              <RecentActivity vesselIds={ids} limit={10} />
            </Card>
          </div>
        </div>
      </PageBody>
    </>
  )
}
