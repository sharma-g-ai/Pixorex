import { Link } from 'react-router'
import { useTechnicianDecisions } from '../../api/review'
import { Badge } from '../../components/Badge'
import { buttonClasses } from '../../components/buttonClasses'
import { Card } from '../../components/Card'
import { decidedByText, technicianDecisionStatus } from '../review/reviewRules'

/** BU Home: the 3 latest decisions by technicians, each with "Check" (canvas BU 03). */
export function RecentDecisions({ buId }: { buId: string }) {
  const decisions = useTechnicianDecisions(buId)
  const latest = (decisions.data ?? []).slice(0, 3)
  return (
    <Card
      title="Recent decisions by technicians"
      action={
        <Link to="/delegations?tab=decided" className={buttonClasses('link')}>
          All decisions
        </Link>
      }
    >
      {decisions.isPending ? (
        <p className="text-body text-ink-muted">Loading…</p>
      ) : latest.length === 0 ? (
        <p className="text-body text-ink-muted">No decisions by technicians yet.</p>
      ) : (
        <ul className="flex flex-col divide-y divide-line-soft">
          {latest.map((d) => {
            const status = technicianDecisionStatus(d)
            return (
              <li key={d.decision_id} className="flex items-center gap-3 py-3">
                <div className="min-w-0 grow">
                  <div className="truncate text-body font-semibold">{d.record_no}</div>
                  <div className="text-meta text-ink-subtle">{decidedByText(d)}</div>
                </div>
                <Badge tone={status.tone}>{status.label}</Badge>
                <Link to={`/review-queue/${d.scan_id}`} className={buttonClasses('link')}>
                  Check
                </Link>
              </li>
            )
          })}
        </ul>
      )}
    </Card>
  )
}
