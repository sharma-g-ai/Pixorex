import { useState } from 'react'
import { useSearchParams } from 'react-router'
import {
  useBatch,
  useBatches,
  useReassignBatch,
  useRemindBatch,
  useTakeBackBatch,
  type Batch,
} from '../../api/review'
import { errorMessage } from '../../api/client'
import { useDashboard } from '../../app/DashboardContext'
import { Alert } from '../../components/Alert'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { Card } from '../../components/Card'
import { ConfirmDialog } from '../../components/ConfirmDialog'
import { DataTable, type Column } from '../../components/DataTable'
import { PageHeader } from '../../components/layout/PageHeader'
import { ProgressBar } from '../../components/ProgressBar'
import { Tabs } from '../../components/Tabs'
import { TextAreaField } from '../../components/TextAreaField'
import { timeAgo } from '../../lib/time'
import { DelegateDialog } from './DelegateDialog'
import { batchStatus } from './reviewRules'
import { TechnicianDecisionsTable } from './TechnicianDecisionsTable'

type Open = { kind: 'reassign' | 'take-back'; batch: Batch } | null

/** BU-04 Delegation console: batches and technician decisions (canvas BU 13–19; contracts 3.10–3.14). */
export function DelegationsPage() {
  const { unit } = useDashboard()
  if (!unit?.bu_id) return null
  return <DelegationsOfUnit key={unit.bu_id} buId={unit.bu_id} />
}

function DelegationsOfUnit({ buId }: { buId: string }) {
  const batches = useBatches(buId)
  const [params] = useSearchParams()
  const [tab, setTab] = useState<'batches' | 'decided'>(
    params.get('tab') === 'decided' ? 'decided' : 'batches',
  )
  const [open, setOpen] = useState<Open>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const done = (text: string) => {
    setOpen(null)
    setNotice(text)
  }

  const columns: Column<Batch>[] = [
    {
      header: 'Batch',
      width: 0.6,
      cell: (b) => <span className="font-mono font-semibold">{b.batch_no}</span>,
    },
    { header: 'Delegated to', width: 1.3, cell: (b) => b.assigned_to_name },
    {
      header: 'Progress',
      width: 1.4,
      cell: (b) => (
        <ProgressBar
          done={b.decided_count}
          total={b.scan_count}
          label={`${b.decided_count} of ${b.scan_count} reviewed`}
        />
      ),
    },
    { header: 'Delegated', width: 0.9, cell: (b) => timeAgo(b.created_at) },
    {
      header: 'Status',
      width: 1.3,
      cell: (b) => {
        const status = batchStatus(b)
        return <Badge tone={status.tone}>{status.label}</Badge>
      },
    },
    {
      header: 'Actions',
      width: 2.4,
      align: 'right',
      cell: (b) => (
        <BatchActions
          batch={b}
          onOpen={setOpen}
          onSeeDecisions={() => setTab('decided')}
          onNotice={setNotice}
        />
      ),
    },
  ]

  return (
    <>
      <PageHeader
        title="Delegations"
        subtitle="Batches you handed to technicians, and what they decided"
      />
      <div className="flex grow flex-col gap-4 overflow-y-auto px-8 pt-6 pb-8">
        {notice && (
          <Alert tone="info" role="status">
            {notice}
          </Alert>
        )}
        <Tabs
          label="Delegations"
          tabs={[
            { key: 'batches', label: 'Batches', count: batches.data?.length },
            { key: 'decided', label: 'Decided by technicians' },
          ]}
          current={tab}
          onChange={setTab}
        />
        {tab === 'decided' ? (
          <TechnicianDecisionsTable buId={buId} scanPath={(id) => `/review-queue/${id}`} />
        ) : batches.isPending ? (
          <Card>Loading batches…</Card>
        ) : batches.isError ? (
          <Card>We couldn't load the batches. Please refresh.</Card>
        ) : (
          <DataTable
            label="Delegated batches"
            columns={columns}
            rows={batches.data}
            rowKey={(b) => b.batch_id}
            empty="No batches yet. Select scans in the review queue to delegate them."
          />
        )}
        <Alert tone="info">
          No progress alerts you after 1 day and again after 1 week (dashboard + email).{' '}
          <b>Reassign</b> moves the unreviewed scans to another technician; <b>Take back</b> returns
          them to your queue. Decisions already made stay. You can approve or reject any delegated
          scan yourself at any time.
        </Alert>
      </div>

      {open?.kind === 'reassign' && (
        <ReassignDialog
          buId={buId}
          batch={open.batch}
          onClose={() => setOpen(null)}
          onDone={done}
        />
      )}
      {open?.kind === 'take-back' && (
        <TakeBackDialog batch={open.batch} onClose={() => setOpen(null)} onDone={done} />
      )}
    </>
  )
}

function BatchActions({
  batch,
  onOpen,
  onSeeDecisions,
  onNotice,
}: {
  batch: Batch
  onOpen: (o: Open) => void
  onSeeDecisions: () => void
  onNotice: (t: string) => void
}) {
  const remind = useRemindBatch(batch.batch_id)
  const status = batchStatus(batch)
  if (status.label === 'Done' || batch.status === 'taken_back') {
    return (
      <Button variant="secondary" onClick={onSeeDecisions}>
        See decisions
      </Button>
    )
  }
  return (
    <div className="flex justify-end gap-2">
      {status.tone === 'warning' && (
        <Button
          variant="secondary"
          disabled={remind.isPending}
          onClick={() =>
            remind
              .mutateAsync(undefined)
              .then(() => onNotice(`Reminder sent to ${batch.assigned_to_name}.`))
              .catch((err: unknown) => onNotice(errorMessage(err)))
          }
        >
          Send reminder
        </Button>
      )}
      <Button variant="secondary" onClick={() => onOpen({ kind: 'reassign', batch })}>
        Reassign
      </Button>
      <Button variant="secondary" onClick={() => onOpen({ kind: 'take-back', batch })}>
        Take back
      </Button>
    </div>
  )
}

function ReassignDialog({
  buId,
  batch,
  onClose,
  onDone,
}: {
  buId: string
  batch: Batch
  onClose: () => void
  onDone: (t: string) => void
}) {
  const detail = useBatch(batch.batch_id)
  const reassign = useReassignBatch(batch.batch_id)
  const open = (detail.data?.assignments ?? [])
    .filter((a) => a.status === 'assigned')
    .map((a) => a.scan_id)
  if (detail.isPending) return null
  return (
    <DelegateDialog
      buId={buId}
      scanIds={open}
      title={`Reassign batch ${batch.batch_no}`}
      intro={`${open.length} scans not reviewed by ${batch.assigned_to_name}. Pick who gets them instead. ${batch.assigned_to_name} is told the batch moved and the scans leave their app.`}
      confirmText={(name, count) =>
        `Reassign ${count} ${count === 1 ? 'scan' : 'scans'} to ${name}`
      }
      onClose={onClose}
      onSubmit={async (delegate) => {
        await reassign.mutateAsync(delegate.user_id)
        onDone(`Batch ${batch.batch_no} moved to ${delegate.full_name}.`)
      }}
    />
  )
}

function TakeBackDialog({
  batch,
  onClose,
  onDone,
}: {
  batch: Batch
  onClose: () => void
  onDone: (t: string) => void
}) {
  const takeBack = useTakeBackBatch(batch.batch_id)
  const [message, setMessage] = useState('')
  const left = batch.scan_count - batch.decided_count
  return (
    <ConfirmDialog
      title={`Take back batch ${batch.batch_no}?`}
      confirmLabel={`Take back ${left} ${left === 1 ? 'scan' : 'scans'}`}
      onClose={onClose}
      onConfirm={async () => {
        await takeBack.mutateAsync(message.trim())
        onDone(`Batch ${batch.batch_no} was taken back. Its open scans are in your review queue.`)
      }}
    >
      <ul className="mb-3 flex list-inside list-disc flex-col gap-2">
        <li>
          The <b className="text-ink">{left} scans not reviewed yet</b> go back to your review queue
          as Unassigned.
        </li>
        <li>
          They disappear from {batch.assigned_to_name}'s app straight away. {batch.assigned_to_name}{' '}
          is told the batch was taken back.
        </li>
        <li>Decisions already made in this batch stay as they are.</li>
      </ul>
      <TextAreaField
        label={`Message to ${batch.assigned_to_name} (optional)`}
        value={message}
        onChange={(e) => setMessage(e.target.value)}
      />
    </ConfirmDialog>
  )
}
