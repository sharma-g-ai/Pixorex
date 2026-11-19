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
import { PhotoViewer } from '../../components/PhotoViewer'
import { ScanHistoryCard } from './ScanHistoryCard'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { buttonClasses } from '../../components/buttonClasses'
import { Card } from '../../components/Card'
import { DataTable, type Column } from '../../components/DataTable'
import { Dialog } from '../../components/Dialog'
import { PageHeader } from '../../components/layout/PageHeader'
import { DecisionReasonDialog } from './DecisionReasonDialog'
import { photoList } from './photos'
import { extractedText, flagText, verificationStatus } from './reviewRules'
import { formatScanId } from '../../lib/scanId'

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

  if (review.isPending) return <Card className="m-8">Loading the scan…</Card>
  if (review.isError)
    return (
      <Card className="m-8">We couldn't load this scan. It may have been decided already.</Card>
    )

  const scan = review.data
  // A decision belongs to one revision: after a fix the earlier rejection is history,
  // and the new revision waits for its own decision.
  const current = scan.decisions.find(
    (d) => d.is_current && d.revision_id === scan.current_revision.revision_id,
  )
  const waiting = scan.current_revision.review_status === 'waiting_for_approval' && !current

  return (
    <>
      <PageHeader
        title={scan.equipment_type_name}
        subtitle={`${formatScanId(scan.record_no)} · ${back.label}`}
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
              <LocationPath path={scan.location_path} />
              {/* Just the number: the earlier rejection and the fix are in the History below. */}
              <Meta term="Revision" value={`${scan.current_revision.revision_no}`} />
            </dl>
          </Card>
        </aside>

        <section className="flex min-w-0 grow flex-col gap-3.5" aria-label="Review">
          {/* No "Resubmitted · revision N" banner: History below already says who rejected the
              earlier revision, when and why, and that it was fixed and sent back. */}
          {scan.current_revision.empty_required_fields.length > 0 && (
            <Alert tone="danger">
              Sent with required fields empty:{' '}
              {scan.current_revision.empty_required_fields.join(', ')}.
            </Alert>
          )}
          <FieldsTable fields={scan.fields} />
          {/* Who decided, when and why is in the History timeline below, which updates as soon
              as a decision is saved: no confirmation banner, and only what can still be done
              is shown here. */}
          {waiting ? (
            <DecideActions scanId={scanId} capturedBy={scan.captured_by_name} />
          ) : (
            current && <CurrentDecision decision={current} capturedBy={scan.captured_by_name} />
          )}
          <ScanHistoryCard scanId={scanId} />
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

/**
 * The saved path ("Plant 04 › Building C › Bin 05", api PATH_SEPARATOR) shown one place per
 * line, biggest first and each one indented under the one above, instead of one long line.
 */
function LocationPath({ path }: { path: string }) {
  const parts = path.split(' › ')
  return (
    <div className="flex flex-col gap-1">
      <dt className="text-ink-muted">Location</dt>
      <dd>
        <ol aria-label={path} className="flex flex-col gap-0.5 font-semibold">
          {parts.map((part, i) => (
            <li
              key={i}
              className="wrap-break-word"
              style={{ paddingLeft: `calc(var(--spacing) * ${i * 3})` }}
            >
              {i > 0 && (
                <span aria-hidden="true" className="mr-1 text-ink-subtle">
                  ↳
                </span>
              )}
              {part}
            </li>
          ))}
        </ol>
      </dd>
    </div>
  )
}

function Photos({ photos }: { photos: { no: number; url: string }[] }) {
  const [shown, setShown] = useState(0)
  const [open, setOpen] = useState(false)
  const photo = photos[shown]
  if (!photo) {
    return (
      <div className="flex h-75 items-center justify-center rounded-xl bg-ink text-small text-white/70">
        No image available
      </div>
    )
  }
  return (
    <div className="flex flex-col gap-2">
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label={`Open image ${photo.no} of ${photos.length}`}
        className="relative block w-full cursor-zoom-in overflow-hidden rounded-xl bg-ink"
      >
        <PhotoImage
          key={photo.url}
          src={photo.url}
          alt={`Image ${photo.no} of ${photos.length}`}
          className="h-75 w-full object-contain"
        />
        <span className="absolute right-2.5 bottom-2.5 rounded-full bg-ink/60 px-2.5 py-1 text-meta font-semibold text-white">
          Image {photo.no} of {photos.length} · click to zoom
        </span>
      </button>
      {open && <PhotoViewer photos={photos} start={shown} onClose={() => setOpen(false)} />}
      {photos.length > 1 && (
        <div className="flex gap-2">
          {photos.map((p, i) => (
            <button
              key={p.no}
              type="button"
              aria-label={`Show image ${p.no}`}
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

/**
 * A signed photo: a loading note while it arrives, and a message instead of a broken image
 * if it can't be loaded (for example the 15-minute link ran out). Render with a key on the
 * url so a new photo starts from loading again.
 */
function PhotoImage({ src, alt, className }: { src: string; alt: string; className: string }) {
  const [state, setState] = useState<'loading' | 'loaded' | 'failed'>('loading')
  return (
    <>
      {state === 'loading' && (
        <div
          role="status"
          className="absolute inset-0 flex items-center justify-center text-small text-white/70"
        >
          Loading image…
        </div>
      )}
      {state === 'failed' ? (
        <div
          role="alert"
          className="flex h-75 items-center justify-center px-4 text-center text-small text-white/70"
        >
          We couldn't load this image. Refresh the page to get a new link.
        </div>
      ) : (
        <img
          src={src}
          alt={alt}
          className={`${className} ${state === 'loaded' ? '' : 'invisible'}`}
          onLoad={() => setState('loaded')}
          onError={() => setState('failed')}
        />
      )}
    </>
  )
}

function FieldsTable({ fields }: { fields: ReviewField[] }) {
  const columns: Column<ReviewField>[] = [
    { header: 'Field', width: 1, cell: (f) => <span className="font-semibold">{f.label}</span> },
    {
      // One column for the value that was submitted (was "AI read" + "Technician"). A
      // technician's fix shows what the AI read under it, struck through; the State column
      // says "Corrected".
      header: 'Extracted text',
      width: 2,
      cell: (f) => {
        const corrected = f.verification_state === 'corrected'
        return (
          <div className="flex flex-col gap-0.5">
            <span className="font-mono font-semibold">{extractedText(f) ?? '—'}</span>
            {corrected && f.ai_value !== null && (
              <span className="text-meta text-ink-subtle">
                AI read <span className="font-mono line-through">{f.ai_value}</span>
              </span>
            )}
            {/* The AI's score belongs to the AI's value, so it is shown only when kept. */}
            {!corrected && f.ai_value !== null && f.confidence !== null && (
              <span
                className={`text-meta ${f.flag_reasons.includes('low_confidence') ? 'font-semibold text-warning' : 'text-ink-subtle'}`}
              >
                {Math.round(f.confidence * 100)}% confidence
                {f.flag_reasons.includes('low_confidence') ? ' · needs review' : ''}
              </span>
            )}
          </div>
        )
      },
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

function DecideActions({ scanId, capturedBy }: { scanId: string; capturedBy: string }) {
  const decide = useDecide(scanId)
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const [rejecting, setRejecting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const approve = () =>
    decide
      .mutateAsync({ body: { decision: 'approved' }, idempotencyKey })
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
          }}
        />
      )}
    </>
  )
}

function CurrentDecision({ decision, capturedBy }: { decision: Decision; capturedBy: string }) {
  const [overriding, setOverriding] = useState(false)
  const [approving, setApproving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const [approveKey] = useState(() => crypto.randomUUID())
  const override = useOverride(decision.decision_id)
  // A delegated technician's decision, either way, can still be changed by the BU Admin
  // (contract 3.7); anything else is final and already in the History timeline.
  if (decision.decider_role !== 'delegated_technician') return null
  const approved = decision.decision === 'approved'

  const approve = async () => {
    setError(null)
    try {
      await override.mutateAsync({ body: { decision: 'approved' }, idempotencyKey: approveKey })
    } catch (err: unknown) {
      setError(conflictMessage(err)) // e.g. required fields sent empty: the API says so
    } finally {
      setApproving(false)
    }
  }

  return (
    <>
      <div className="flex items-center justify-end gap-3">
        <span className="text-body-sm text-ink-muted">
          {approved ? 'Approved' : 'Rejected'} by a delegated technician. The technician is told if
          you change it.
        </span>
        {approved ? (
          <Button variant="danger" onClick={() => setOverriding(true)}>
            Override: reject
          </Button>
        ) : (
          <Button onClick={() => setApproving(true)}>Override: approve</Button>
        )}
      </div>
      {error && <Alert tone="danger">{error}</Alert>}
      {approving && (
        <Dialog
          title={`Override ${decision.decided_by_name}'s rejection`}
          onClose={() => setApproving(false)}
          footer={
            <>
              <Button variant="secondary" onClick={() => setApproving(false)}>
                Cancel
              </Button>
              <Button disabled={override.isPending} onClick={() => void approve()}>
                {override.isPending ? 'Saving…' : 'Override and approve'}
              </Button>
            </>
          }
        >
          <p className="text-body-sm">
            The scan changes from Rejected to Approved. {decision.decided_by_name} is told you
            changed their decision, and {capturedBy}, who captured the scan, no longer has to fix
            it. Both are recorded in the audit log.
          </p>
        </Dialog>
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
          }}
        />
      )}
    </>
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
