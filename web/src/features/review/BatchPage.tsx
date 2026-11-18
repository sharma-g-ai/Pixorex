import { useMemo, useState } from 'react'
import { Link, useParams } from 'react-router'
import { errorMessage } from '../../api/client'
import { useBatch, useRemindBatch, type Assignment } from '../../api/review'
import { useDashboard } from '../../app/DashboardContext'
import { Alert } from '../../components/Alert'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { buttonClasses } from '../../components/buttonClasses'
import { Card } from '../../components/Card'
import {
  CheckListFilter,
  ColumnFilter,
  ColumnHeader,
  FilterChips,
  type Chip,
} from '../../components/ColumnFilter'
import { listChip } from '../../components/filterChips'
import { DataTable, type Column } from '../../components/DataTable'
import { PageHeader } from '../../components/layout/PageHeader'
import { ProgressBar } from '../../components/ProgressBar'
import { dateTime } from '../../lib/time'
import { formatScanId } from '../../lib/scanId'
import { ReassignDialog, TakeBackDialog } from './batchDialogs'
import { assignmentStatus, batchStatus, type AssignmentStatus } from './reviewRules'

const statusOptions: { value: AssignmentStatus['key']; label: string }[] = [
  { value: 'delegated', label: 'Delegated' },
  { value: 'approved', label: 'Approved' },
  { value: 'rejected', label: 'Rejected' },
  { value: 'removed', label: 'Left the batch' },
]

/**
 * One batch (contracts 3.11-3.14): how far it is, each scan with where it stands, and what an
 * admin can do with it: remind the technician, give it to someone else, or take it back.
 */
export function BatchPage() {
  const { batchId = '' } = useParams()
  const { unit, me } = useDashboard()
  const detail = useBatch(batchId)
  const remind = useRemindBatch(batchId)
  const [open, setOpen] = useState<'reassign' | 'take-back' | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [statuses, setStatuses] = useState<string[]>([])
  const [schemas, setSchemas] = useState<string[]>([])

  const rows = useMemo(() => detail.data?.assignments ?? [], [detail.data])
  const withStatus = useMemo(
    () => rows.map((a) => ({ a, status: assignmentStatus(a, me.full_name) })),
    [rows, me.full_name],
  )
  const shown = withStatus.filter(
    ({ a, status }) =>
      (statuses.length === 0 || statuses.includes(status.key)) &&
      (schemas.length === 0 || schemas.includes(a.equipment_type_name)),
  )

  if (detail.isPending) {
    return (
      <>
        <PageHeader title="Batch" actions={<BackLink />} />
        <div className="px-8 pt-6">
          <Card>Loading the batch…</Card>
        </div>
      </>
    )
  }
  if (detail.isError) {
    return (
      <>
        <PageHeader title="Batch" actions={<BackLink />} />
        <div className="px-8 pt-6">
          <Card>We couldn't load this batch. It may not exist, or it is not in your unit.</Card>
        </div>
      </>
    )
  }

  const { batch } = detail.data
  const status = batchStatus(batch)
  const active = batch.status === 'active'
  const stuck = active && status.tone === 'warning'
  const approved = withStatus.filter((w) => w.status.key === 'approved').length
  const rejected = withStatus.filter((w) => w.status.key === 'rejected').length
  const withTech = withStatus.filter((w) => w.status.key === 'delegated').length

  const schemaNames = [...new Set(rows.map((a) => a.equipment_type_name))].sort()
  const chips: Chip[] = []
  if (statuses.length)
    chips.push({
      key: 'status',
      text: listChip(
        'Status',
        statuses.map((s) => statusOptions.find((o) => o.value === s)?.label ?? s),
      ),
      onRemove: () => setStatuses([]),
    })
  if (schemas.length)
    chips.push({ key: 'schema', text: listChip('Schema', schemas), onRemove: () => setSchemas([]) })

  const columns: Column<{ a: Assignment; status: AssignmentStatus }>[] = [
    {
      header: 'Scan',
      width: 1.2,
      cell: ({ a }) => <span className="font-mono font-semibold">{formatScanId(a.record_no)}</span>,
    },
    {
      header: (
        <ColumnHeader label="Schema">
          <ColumnFilter label="Schema" active={schemas.length > 0}>
            {(close) => (
              <CheckListFilter
                title="Schema"
                options={schemaNames.map((n) => ({ value: n, label: n }))}
                selected={schemas}
                onChange={setSchemas}
                onDone={close}
              />
            )}
          </ColumnFilter>
        </ColumnHeader>
      ),
      width: 1.3,
      cell: ({ a }) => a.equipment_type_name,
    },
    { header: 'Location', width: 1.8, cell: ({ a }) => a.location_path },
    { header: 'Captured by', width: 1.1, cell: ({ a }) => a.captured_by_name },
    {
      header: (
        <ColumnHeader label="Status">
          <ColumnFilter label="Status" align="right" active={statuses.length > 0}>
            {(close) => (
              <CheckListFilter
                title="Status"
                options={statusOptions}
                selected={statuses}
                onChange={setStatuses}
                onDone={close}
              />
            )}
          </ColumnFilter>
        </ColumnHeader>
      ),
      width: 1.4,
      cell: ({ status: s }) => (
        <span className="flex flex-col items-start gap-1">
          <Badge tone={s.tone}>{s.label}</Badge>
          {s.detail && <span className="text-meta text-ink-subtle">{s.detail}</span>}
        </span>
      ),
    },
    {
      header: 'Decided',
      width: 1.2,
      cell: ({ a }) =>
        a.outcome ? (
          <span className="font-mono text-meta">{dateTime(a.outcome.decided_at)}</span>
        ) : (
          <span className="text-ink-subtle">—</span>
        ),
    },
    {
      header: 'Actions',
      width: 0.8,
      align: 'right',
      cell: ({ a, status: s }) => (
        <Link
          to={`/review-queue/${a.scan_id}`}
          className={buttonClasses('link')}
          aria-label={`${s.key === 'approved' || s.key === 'rejected' ? 'Check' : 'Open'} ${a.record_no}`}
        >
          {s.key === 'approved' || s.key === 'rejected' ? 'Check' : 'Open'} →
        </Link>
      ),
    },
  ]

  return (
    <>
      <PageHeader
        title={`Batch ${batch.batch_no}`}
        subtitle={`Delegated to ${batch.assigned_to_name} · ${dateTime(batch.created_at)} · by ${batch.created_by_name}`}
        actions={
          <>
            <BackLink />
            {stuck && (
              <Button
                variant="secondary"
                disabled={remind.isPending}
                onClick={() =>
                  remind
                    .mutateAsync(undefined)
                    .then(() => setNotice(`Reminder sent to ${batch.assigned_to_name}.`))
                    .catch((err: unknown) => setNotice(errorMessage(err)))
                }
              >
                Send reminder
              </Button>
            )}
            {active && (
              <>
                <Button variant="secondary" onClick={() => setOpen('reassign')}>
                  Reassign
                </Button>
                <Button variant="secondary" onClick={() => setOpen('take-back')}>
                  Take back
                </Button>
              </>
            )}
          </>
        }
      />
      <div className="flex grow flex-col gap-4 overflow-y-auto px-8 pt-6 pb-8 *:shrink-0">
        {notice && (
          <Alert tone="info" role="status">
            {notice}
          </Alert>
        )}
        <Card>
          <div className="flex flex-wrap items-center gap-x-6 gap-y-3">
            <div className="w-72 max-w-full">
              <ProgressBar
                done={batch.decided_count}
                total={batch.scan_count}
                label={`${batch.decided_count} of ${batch.scan_count} reviewed`}
              />
            </div>
            <Badge tone={status.tone}>{status.label}</Badge>
            <p className="text-small text-ink-muted">
              {approved} approved · {rejected} rejected · {withTech} still with the technician
            </p>
          </div>
        </Card>
        <FilterChips
          chips={chips}
          onClearAll={() => {
            setStatuses([])
            setSchemas([])
          }}
        />
        <DataTable
          label={`Scans in batch ${batch.batch_no}`}
          columns={columns}
          rows={shown}
          rowKey={({ a }) => a.scan_id}
          empty="No scans match these filters."
        />
      </div>

      {open === 'reassign' && unit?.bu_id && (
        <ReassignDialog
          buId={unit.bu_id}
          batch={batch}
          onClose={() => setOpen(null)}
          onDone={() => setOpen(null)}
        />
      )}
      {open === 'take-back' && (
        <TakeBackDialog batch={batch} onClose={() => setOpen(null)} onDone={() => setOpen(null)} />
      )}
    </>
  )
}

function BackLink() {
  return (
    <Link to="/delegations" className={buttonClasses('link')}>
      ← Delegations
    </Link>
  )
}
