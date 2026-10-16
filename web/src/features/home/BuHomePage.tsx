import { useInvites } from '../../api/invites'
import { useBatches, useReviewQueue } from '../../api/review'
import { useDashboard } from '../../app/DashboardContext'
import { Card } from '../../components/Card'
import { NeedsYouItem } from '../../components/NeedsYouItem'
import { PageHeader } from '../../components/layout/PageHeader'
import { StatTile } from '../../components/StatTile'
import { RecentActivityCard } from '../auditLog/RecentActivityCard'
import { RecentDecisions } from './RecentDecisions'
import { buNeedsYou, calmSummary, greeting } from './homeRules'

/** BU Admin home: today's numbers, what needs them, recent technician decisions (canvas BU 03, 28). */
export function BuHomePage() {
  const { me, unit } = useDashboard()
  if (!unit?.bu_id) return null
  return (
    <HomeOfUnit
      key={unit.bu_id}
      buId={unit.bu_id}
      unitName={unit.name ?? ''}
      userName={me.full_name}
    />
  )
}

function HomeOfUnit({
  buId,
  unitName,
  userName,
}: {
  buId: string
  unitName: string
  userName: string
}) {
  const queue = useReviewQueue(buId, 'waiting')
  const batches = useBatches(buId)
  const invites = useInvites(buId)
  const counts = queue.data?.counts
  const needs = buNeedsYou(counts, batches.data ?? [], invites.data ?? [])
  const today = new Date().toLocaleDateString('en-GB', {
    weekday: 'long',
    day: 'numeric',
    month: 'short',
  })

  return (
    <>
      <PageHeader title={greeting(userName)} subtitle={`${unitName} · ${today}`} />
      <div className="flex grow flex-col gap-5 overflow-y-auto px-8 pt-6 pb-8">
        <div className="grid grid-cols-2 gap-3.5 lg:grid-cols-4">
          <StatTile value={counts?.waiting ?? '–'} label="waiting review" to="/review-queue" />
          <StatTile
            value={counts?.delegated ?? '–'}
            label="in delegated batches"
            to="/delegations"
          />
          <StatTile value={counts?.approved_this_week ?? '–'} label="approved this week" />
          <StatTile
            value={counts?.over_1d ?? '–'}
            label={
              counts?.over_1d
                ? 'waiting over 24 h · also with your Enterprise Admin'
                : 'waiting over 24 h'
            }
            tone={counts?.over_1d ? 'warning' : 'default'}
          />
        </div>

        {queue.isPending ? (
          <Card>Loading…</Card>
        ) : needs.length > 0 ? (
          <Card title="Needs you">
            <div className="grid grid-cols-1 gap-3.5 md:grid-cols-2">
              {needs.map((item) => (
                <NeedsYouItem key={item.title} {...item} />
              ))}
            </div>
          </Card>
        ) : (
          <Card title={`Nothing urgent in ${unitName}`}>
            <p className="text-body text-ink-muted">{calmSummary(counts?.waiting ?? 0)}</p>
          </Card>
        )}

        {/* Canvas: decisions while something needs the admin; recent activity when nothing does. */}
        {queue.isPending ? null : needs.length > 0 ? (
          <RecentDecisions buId={buId} />
        ) : (
          <RecentActivityCard
            buId={buId}
            title={`Recent activity in ${unitName}`}
            hide={['Unit', 'Type']}
          />
        )}
      </div>
    </>
  )
}
