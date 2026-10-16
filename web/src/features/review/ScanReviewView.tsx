import { useState } from 'react'
import { Link } from 'react-router'
import { ApiError, errorMessage, problemCode } from '../../api/client'
import {
  useDecide,
  useOverride,
  useScanReview,
  type Decision,
  type ReviewField,
} from '../../api/review'
import { Alert } from '../../components/Alert'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { buttonClasses } from '../../components/buttonClasses'
import { Card } from '../../components/Card'
import { DataTable, type Column } from '../../components/DataTable'
import { PageHeader } from '../../components/layout/PageHeader'
import { timeAgo } from '../../lib/time'
import { DecisionReasonDialog } from './DecisionReasonDialog'
import { photoList } from './photos'
import { flagText, rejectCategoryLabels, verificationStatus } from './reviewRules'

interface ScanReviewViewProps {
  scanId: string
  /** Where "← Back" goes and what it is called, e.g. the review queue. */
  back: { to: string; label: string }
}

/**
 * One scan for review: photos, AI value next to the technician's, and the decision
 * (canvas BU 07, 20–23 and EA 05–07; contracts 3.4, 3.5, 3.7).
 */
export function ScanReviewView({ scanId, back }: ScanReviewViewProps) {
  const review = useScanReview(scanId)
  const [notice, setNotice] = useState<string | null>(null)

  if (review.isPending) return <Card className="m-8">Loading the scan…</Card>
  if (review.isError)
    return (
      <Card className="m-8">We couldn't load this scan. It may have been decided already.</Card>
    )

  const scan = review.data
  const current = scan.decisions.find((d) => d.is_current)
  const waiting = scan.current_revision.review_status === 'waiting_for_approval' && !current

  return (
    <>
      <PageHeader
        title={scan.equipment_type_name}
        subtitle={`${scan.record_no} · ${back.label}`}
        actions={
          <Link to={back.to} className={buttonClasses('link')}>
            ← Back
          </Link>
        }
      />
      <div className="flex grow flex-col gap-5 overflow-y-auto px-8 pt-6 pb-8 lg:flex-row lg:items-start">
        <aside className="flex w-full shrink-0 flex-col gap-3 lg:w-95">
          <Photos photos={photoList(scan.photos)} />
          <Card>
            <dl className="flex flex-col gap-2 text-body-sm">
              <Meta term="Captured by" value={scan.captured_by_name} />
              <Meta term="Type" value={scan.equipment_type_name} />
              <Meta term="Location" value={scan.location_path} />
              <Meta
                term="Revision"
                value={`${scan.current_revision.revision_no}${scan.current_revision.origin === 'rejection_fix' ? ' · fixed after a rejection' : ''}`}
              />
            </dl>
          </Card>
        </aside>

        <section className="flex min-w-0 grow flex-col gap-3.5" aria-label="Review">
          {notice && (
            <Alert tone="info" role="status">
              {notice}
            </Alert>
          )}
          {scan.current_revision.empty_required_fields.length > 0 && (
            <Alert tone="danger">
              Sent with required fields empty:{' '}
              {scan.current_revision.empty_required_fields.join(', ')}.
            </Alert>
          )}
          <FieldsTable fields={scan.fields} />
          {waiting ? (
            <DecideActions scanId={scanId} capturedBy={scan.captured_by_name} onDone={setNotice} />
          ) : current ? (
            <CurrentDecision
              decision={current}
              capturedBy={scan.captured_by_name}
              onDone={setNotice}
            />
          ) : (
            <Alert tone="info">This scan is not waiting for a decision.</Alert>
          )}
          {scan.decisions.length > 0 && <DecisionHistory decisions={scan.decisions} />}
        </section>
      </div>
    </>
  )
}

function Meta({ term, value }: { term: string; value: string }) {
  return (
    <div className="flex justify-between gap-2.5">
      <dt className="text-ink-muted">{term}</dt>
      <dd className="text-right font-semibold">{value}</dd>
    </div>
  )
}

function Photos({ photos }: { photos: { no: number; url: string }[] }) {
  const [shown, setShown] = useState(0)
  const photo = photos[shown]
  if (!photo) {
    return (
      <div className="flex h-75 items-center justify-center rounded-xl bg-ink text-small text-white/70">
        No photo available
      </div>
    )
  }
  return (
    <div className="flex flex-col gap-2">
      <a
        href={photo.url}
        target="_blank"
        rel="noreferrer"
        className="relative block overflow-hidden rounded-xl bg-ink"
      >
        <img
          src={photo.url}
          alt={`Photo ${photo.no} of ${photos.length}`}
          className="h-75 w-full object-contain"
        />
        <span className="absolute right-2.5 bottom-2.5 rounded-full bg-ink/60 px-2.5 py-1 text-meta font-semibold text-white">
          Photo {photo.no} of {photos.length} · open full size
        </span>
      </a>
      {photos.length > 1 && (
        <div className="flex gap-2">
          {photos.map((p, i) => (
            <button
              key={p.no}
              type="button"
              aria-label={`Show photo ${p.no}`}
              aria-pressed={i === shown}
              onClick={() => setShown(i)}
              className={`size-16 overflow-hidden rounded-lg border-2 ${i === shown ? 'border-brand-navy' : 'border-transparent'}`}
            >
              <img src={p.url} alt="" className="size-full object-cover" />
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

function FieldsTable({ fields }: { fields: ReviewField[] }) {
  const columns: Column<ReviewField>[] = [
    { header: 'Field', width: 1, cell: (f) => <span className="font-semibold">{f.label}</span> },
    {
      header: 'AI read',
      width: 1.5,
      cell: (f) => (
        <span
          className={`font-mono ${f.verification_state === 'corrected' ? 'text-ink-subtle line-through' : 'text-ink-muted'}`}
        >
          {f.ai_value ?? '—'}
        </span>
      ),
    },
    {
      header: 'Technician',
      width: 1.4,
      cell: (f) => <span className="font-mono font-semibold">{f.technician_value ?? '—'}</span>,
    },
    {
      header: 'Why it was flagged',
      width: 1.3,
      cell: (f) => <span className="text-small text-ink-muted">{flagText(f)}</span>,
    },
    {
      header: 'State',
      width: 1.6,
      cell: (f) => {
        const status = verificationStatus(f)
        return <Badge tone={status.tone}>{status.label}</Badge>
      },
    },
  ]
  return (
    <DataTable
      label="Extracted fields"
      columns={columns}
      rows={fields}
      rowKey={(f) => f.field_key}
      empty="No fields."
    />
  )
}

function DecideActions({
  scanId,
  capturedBy,
  onDone,
}: {
  scanId: string
  capturedBy: string
  onDone: (t: string) => void
}) {
  const decide = useDecide(scanId)
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const [rejecting, setRejecting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const approve = () =>
    decide
      .mutateAsync({ body: { decision: 'approved' }, idempotencyKey })
      .then(() => onDone('Approved. The technician is told.'))
      .catch((err: unknown) => setError(conflictMessage(err)))

  return (
    <>
      <div className="flex justify-end gap-2.5">
        <Button variant="danger" disabled={decide.isPending} onClick={() => setRejecting(true)}>
          Reject
        </Button>
        <Button disabled={decide.isPending} onClick={() => void approve()}>
          {decide.isPending ? 'Saving…' : 'Approve'}
        </Button>
      </div>
      {error && <Alert tone="danger">{error}</Alert>}
      {rejecting && (
        <DecisionReasonDialog
          title="Reject this scan"
          confirmLabel="Reject scan"
          noteLabel={`Note for ${capturedBy}`}
          outro={`${capturedBy} sees this in the app under Needs action, with the category and your note.`}
          onClose={() => setRejecting(false)}
          onSubmit={async (category, note) => {
            await decide.mutateAsync({
              body: { decision: 'rejected', reject_category: category, note: note || null },
              idempotencyKey,
            })
            setRejecting(false)
            onDone(`Rejected · ${rejectCategoryLabels[category]}. ${capturedBy} is told.`)
          }}
        />
      )}
    </>
  )
}

function CurrentDecision({
  decision,
  capturedBy,
  onDone,
}: {
  decision: Decision
  capturedBy: string
  onDone: (t: string) => void
}) {
  const [overriding, setOverriding] = useState(false)
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const override = useOverride(decision.decision_id)
  const byTechnician = decision.decider_role === 'delegated_technician'
  const verdict = decision.decision === 'approved' ? 'Approved' : 'Rejected'

  return (
    <>
      <Alert tone="info">
        <b>
          {verdict} by {decision.decided_by_name}
        </b>{' '}
        · {timeAgo(decision.decided_at)}.
        {byTechnician &&
          decision.decision === 'approved' &&
          ' You can keep this decision or override it — the technician is told if you change it.'}
      </Alert>
      {byTechnician && decision.decision === 'approved' && (
        <div className="flex justify-end">
          <Button variant="danger" onClick={() => setOverriding(true)}>
            Override: reject
          </Button>
        </div>
      )}
      {overriding && (
        <DecisionReasonDialog
          title={`Override ${decision.decided_by_name}'s approval`}
          confirmLabel="Override and reject"
          noteLabel="Why you disagree"
          intro="The scan changes from Approved to Rejected."
          outro={`${decision.decided_by_name} is told you changed their decision, with your reason. ${capturedBy}, who captured the scan, sees it as rejected under Needs action. Both are recorded in the audit log.`}
          onClose={() => setOverriding(false)}
          onSubmit={async (category, note) => {
            await override.mutateAsync({
              body: { decision: 'rejected', reject_category: category, note: note || null },
              idempotencyKey,
            })
            setOverriding(false)
            onDone(`Decision changed to rejected. ${decision.decided_by_name} is told.`)
          }}
        />
      )}
    </>
  )
}

function DecisionHistory({ decisions }: { decisions: Decision[] }) {
  return (
    <Card title="Decisions">
      <ul className="flex flex-col gap-2 text-body-sm">
        {decisions.map((d) => (
          <li key={d.decision_id} className={d.is_current ? '' : 'text-ink-subtle line-through'}>
            {d.decision === 'approved' ? 'Approved' : 'Rejected'}
            {d.reject_category
              ? ` · ${rejectCategoryLabels[d.reject_category as keyof typeof rejectCategoryLabels] ?? d.reject_category}`
              : ''}{' '}
            by {d.decided_by_name} · {timeAgo(d.decided_at)}
            {d.note ? ` — “${d.note}”` : ''}
          </li>
        ))}
      </ul>
    </Card>
  )
}

/** A 409 here means someone else decided first (contract 3.5: first decider wins). */
function conflictMessage(err: unknown): string {
  if (err instanceof ApiError) {
    const code = problemCode(err.problem)
    if (code === 'already-decided')
      return 'Someone else decided this scan first. Refresh to see their decision.'
    if (code === 'own-scan') return 'You captured this scan, so you can’t review it.'
  }
  return errorMessage(err)
}
