import { Link } from 'react-router'
import { useTechnicianDecisions } from '../../api/review'
import { Badge } from '../../components/Badge'
import { buttonClasses } from '../../components/buttonClasses'
import { Card } from '../../components/Card'
import { dateTime } from '../../lib/time'
import { decidedByText, decisionOutcomeStatus, timeOf } from '../review/reviewRules'
import { formatScanId } from '../../lib/scanId'

/**
 * BU Home: the 3 latest decisions by technicians, each with "Check" (canvas BU 03).
 * One job per part: the scan ID is the title, the line under it says who decided, why and
 * when, and the badge only says where the scan ended up.
 */
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
            const status = decisionOutcomeStatus(d)
            return (
              <li key={d.decision_id} className="flex items-center gap-3 py-3">
                <div className="min-w-0 grow">
                  <div className="truncate text-body font-semibold">
                    {formatScanId(d.record_no)}
                  </div>
                  <div className="text-meta text-ink-subtle">
                    {decidedByText(d)}
                    {timeOf(d.decided_at) !== null && (
                      <span className="font-mono"> · {dateTime(d.decided_at)}</span>
                    )}
                  </div>
                </div>
                <Badge tone={status.tone}>{status.label}</Badge>
                <Link
                  to={`/review-queue/${d.scan_id}`}
                  className={buttonClasses('link')}
                  aria-label={`Check ${formatScanId(d.record_no)}`}
                >
                  Check →
                </Link>
              </li>
            )
          })}
        </ul>
      )}
    </Card>
  )
}
