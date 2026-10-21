import { useState } from 'react'
import { Link } from 'react-router'
import type { ExportJob } from '../../api/exports'
import { useReviewQueue, type QueueFilter, type QueueItem } from '../../api/review'
import { useDashboard } from '../../app/DashboardContext'
import { Alert } from '../../components/Alert'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { Card } from '../../components/Card'
import { DataTable, type Column } from '../../components/DataTable'
import { PageHeader } from '../../components/layout/PageHeader'
import { Tabs } from '../../components/Tabs'
import { ExportDialog } from '../exports/ExportDialog'
import { ExportJobNotice } from '../exports/ExportJobNotice'
import { DOWNLOADED_NOTICE } from '../exports/exportText'
import { DelegateBatchDialog } from './DelegateBatchDialog'
import { MAX_BATCH, SelectionBar } from './SelectionBar'
import { editsSummary, waitingStatus } from './reviewRules'
import { TechnicianDecisionsTable } from './TechnicianDecisionsTable'

/** BU-03 Review queue of the current unit: review or delegate (canvas BU 05, 08, 10; contract 3.3). */
export function ReviewQueuePage() {
  const { unit } = useDashboard()
  if (!unit?.bu_id) return null
  return <QueueOfUnit key={unit.bu_id} buId={unit.bu_id} unitName={unit.name ?? ''} />
}

function QueueOfUnit({ buId, unitName }: { buId: string; unitName: string }) {
  const [filter, setFilter] = useState<QueueFilter>('waiting')
  const queue = useReviewQueue(buId, filter === 'decided_by_technicians' ? 'waiting' : filter)
  const [selected, setSelected] = useState<string[]>([])
  const [delegating, setDelegating] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)
  const [exporting, setExporting] = useState(false)
  const [exportJob, setExportJob] = useState<ExportJob | null>(null)

  const counts = queue.data?.counts
  const toggle = (scanId: string, on: boolean) =>
    setSelected((s) => (on ? [...s, scanId].slice(0, MAX_BATCH) : s.filter((id) => id !== scanId)))

  const columns: Column<QueueItem>[] = [
    {
      header: 'Select',
      width: 0.3,
      cell: (item) =>
        item.batch_no ? null : (
          <input
            type="checkbox"
            className="size-4.5 accent-brand-navy"
            aria-label={`Select ${item.record_no}`}
            checked={selected.includes(item.scan_id)}
            disabled={!selected.includes(item.scan_id) && selected.length >= MAX_BATCH}
            onChange={(e) => toggle(item.scan_id, e.target.checked)}
          />
        ),
    },
    {
      header: 'Scan',
      width: 2,
      cell: (item) => (
        <Link to={`/review-queue/${item.scan_id}`} className="block min-w-0 hover:underline">
          <span className="block truncate font-semibold">{item.equipment_type_name}</span>
          <span className="font-mono text-meta text-ink-subtle">{item.record_no}</span>
        </Link>
      ),
    },
    { header: 'Captured by', width: 1, cell: (item) => item.captured_by_name },
    {
      header: 'Location',
      width: 1.4,
      cell: (item) => <span className="truncate">{item.location_path}</span>,
    },
    {
      header: 'Flags',
      width: 0.8,
      cell: (item) => (item.flag_count ? `${item.flag_count} flagged` : '—'),
    },
    { header: 'Technician edits', width: 1.4, cell: (item) => editsSummary(item) },
    {
      header: 'Waiting',
      width: 0.8,
      cell: (item) => {
        const status = waitingStatus(item.waiting_since)
        return <Badge tone={status.tone}>{status.label}</Badge>
      },
    },
    {
      header: 'Assigned',
      width: 1.1,
      cell: (item) =>
        item.batch_no ? (
          <span className="font-semibold text-brand-navy">
            {item.assigned_to_name} · {item.batch_no}
          </span>
        ) : (
          'Unassigned'
        ),
    },
  ]

  return (
    <>
      <PageHeader
        title="Review queue"
        subtitle={`${unitName} · nobody can approve their own scan`}
        actions={
          <Button variant="secondary" onClick={() => setExporting(true)}>
            Export CSV
          </Button>
        }
      />
      <div className="flex grow flex-col gap-4 overflow-y-auto px-8 pt-6 pb-8">
        {notice && (
          <Alert tone="info" role="status">
            {notice}
          </Alert>
        )}
        {exportJob && <ExportJobNotice key={exportJob.export_id} job={exportJob} />}
        <Tabs<QueueFilter>
          label="Review queue"
          tabs={[
            { key: 'waiting', label: 'Waiting', count: counts?.waiting },
            { key: 'over_1d', label: 'Over 1 day', count: counts?.over_1d },
            { key: 'over_1w', label: 'Over 1 week', count: counts?.over_1w },
            { key: 'delegated', label: 'Delegated', count: counts?.delegated },
            {
              key: 'decided_by_technicians',
              label: 'Decided by technicians',
              count: counts?.decided_by_technicians,
            },
          ]}
          current={filter}
          onChange={(key) => {
            setFilter(key)
            setSelected([])
          }}
        />

        {filter === 'decided_by_technicians' ? (
          <TechnicianDecisionsTable buId={buId} scanPath={(id) => `/review-queue/${id}`} />
        ) : (
          <>
            <SelectionBar
              count={selected.length}
              hint={`Select up to ${MAX_BATCH} to delegate as one batch`}
              onClear={() => setSelected([])}
              onDelegate={() => setDelegating(true)}
            />
            {queue.isPending ? (
              <Card>Loading the review queue…</Card>
            ) : queue.isError ? (
              <Card>We couldn't load the review queue. Please refresh.</Card>
            ) : (
              <DataTable
                label="Scans waiting for review"
                columns={columns}
                rows={queue.data.items}
                rowKey={(item) => item.scan_id}
                empty="Nothing waiting here."
              />
            )}
          </>
        )}
      </div>

      {delegating && (
        <DelegateBatchDialog
          buId={buId}
          scanIds={selected}
          onClose={() => setDelegating(false)}
          onDone={(message) => {
            setDelegating(false)
            setSelected([])
            setNotice(message)
          }}
        />
      )}
      {exporting && (
        <ExportDialog
          kind="scans"
          title="Export scans to CSV"
          scopes={[
            {
              key: 'view',
              label: `What you're looking at · ${counts?.waiting ?? 0} waiting scans`,
              filters: { bu_id: buId, review_status: 'waiting_for_approval' },
            },
            { key: 'all', label: `All scans in ${unitName}`, filters: { bu_id: buId } },
            {
              key: 'approved',
              label: 'Approved scans only',
              filters: { bu_id: buId, review_status: 'approved' },
            },
          ]}
          note="Only scans from your units are included. Up to 1,000 rows download straight away; bigger exports arrive as a dashboard notice and an email with a link valid for 1 hour. Recorded in the audit log."
          onClose={() => setExporting(false)}
          onDownloaded={() => {
            setExporting(false)
            setNotice(DOWNLOADED_NOTICE)
          }}
          onQueued={(job) => {
            setExporting(false)
            setExportJob(job)
          }}
        />
      )}
    </>
  )
}
