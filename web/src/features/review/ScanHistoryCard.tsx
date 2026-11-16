import { useScanHistory, type HistoryEvent } from '../../api/review'
import { Card } from '../../components/Card'
import { dateTime, timeAgo } from '../../lib/time'

const dot: Partial<Record<HistoryEvent['kind'], string>> = {
  rejected: 'border-danger',
  read_failed: 'border-danger',
  approved: 'border-success',
  resubmitted: 'border-warning',
  decision_changed: 'border-warning',
}

/**
 * What happened to a scan and where it is now (contract 3.28), so nobody has to read the
 * audit log to find the status. Oldest first; the phone shows the same events.
 */
export function ScanHistoryCard({ scanId }: { scanId: string }) {
  const history = useScanHistory(scanId)
  if (history.isPending) return null
  if (history.isError)
    return (
      <Card title="History">
        <p className="text-body-sm text-ink-muted">We couldn't load the history.</p>
      </Card>
    )
  // No "Now: …" line: it repeated the last event below, with the same time (13 Nov review).
  const { events } = history.data
  return (
    <Card title="History">
      <ol aria-label="History" className="flex flex-col">
        {events.map((e, i) => (
          <li key={`${e.kind}-${e.at}-${i}`} className="relative flex gap-3 pb-3.5 last:pb-0">
            {i < events.length - 1 && (
              <span aria-hidden className="absolute top-4 bottom-0 left-1.75 w-0.5 bg-line" />
            )}
            <span
              aria-hidden
              className={`mt-1 size-4 shrink-0 rounded-full border-[3px] bg-surface ${dot[e.kind] ?? 'border-brand-navy'}`}
            />
            <div className="min-w-0">
              <div className="text-body-sm font-semibold">{e.title}</div>
              {e.detail && <div className="text-body-sm text-ink-muted">{e.detail}</div>}
              <div className="font-mono text-meta text-ink-subtle" title={timeAgo(e.at)}>
                {dateTime(e.at)}
              </div>
            </div>
          </li>
        ))}
      </ol>
    </Card>
  )
}
