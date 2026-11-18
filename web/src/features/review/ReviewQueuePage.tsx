import { useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router'
import { useEquipmentTypes } from '../../api/equipmentTypes'
import type { ExportJob } from '../../api/exports'
import {
  useQueueCounts,
  useReviewQueue,
  type QueueFilters,
  type QueueItem,
  type QueueStatus,
} from '../../api/review'
import { useTechnicians } from '../../api/technicians'
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
  DateRangeFilter,
  FilterChips,
  SortToggle,
  TextSearchFilter,
  type Chip,
} from '../../components/ColumnFilter'
import { listChip, rangeChip } from '../../components/filterChips'
import { DataTable, type Column } from '../../components/DataTable'
import { PageHeader } from '../../components/layout/PageHeader'
import { LoadMore } from '../../components/LoadMore'
import { formatScanId } from '../../lib/scanId'
import { dateTime, dayLabel, istDay } from '../../lib/time'
import { ExportDialog } from '../exports/ExportDialog'
import { ExportJobNotice } from '../exports/ExportJobNotice'
import { DOWNLOADED_NOTICE } from '../exports/exportText'
import { DelegateBatchDialog } from './DelegateBatchDialog'
import {
  ALL_STATUSES,
  filtersFromParams,
  isFiltered,
  paramsFromFilters,
  requestFilters,
  statusLabels,
} from './queueFilters'
import { waitingStatus } from './reviewRules'
import { MAX_BATCH, SelectionBar } from './SelectionBar'

/**
 * BU-03 Review queue of the current unit (canvas BU 05, 08, 10; contract 3.3): one table of
 * scans. Waiting is what still needs a decision (also while a technician has it); Approved and
 * Rejected are reached with the Status filter. Each column header filters its own column.
 */
export function ReviewQueuePage() {
  const { unit } = useDashboard()
  if (!unit?.bu_id) return null
  return <QueueOfUnit key={unit.bu_id} buId={unit.bu_id} unitName={unit.name ?? ''} />
}

/** Only a waiting scan nobody has been given can be picked to delegate. */
const canSelect = (item: QueueItem) => item.status === 'waiting' && !item.batch_id

function QueueOfUnit({ buId, unitName }: { buId: string; unitName: string }) {
  const [params, setParams] = useSearchParams()
  const filters = useMemo(() => filtersFromParams(params), [params])
  const patch = (change: Partial<QueueFilters>) =>
    setParams(paramsFromFilters({ ...filters, ...change }), { replace: true })

  const queue = useReviewQueue(buId, requestFilters(filters))
  const counts = useQueueCounts(buId)
  const types = useEquipmentTypes(buId)
  const technicians = useTechnicians(buId)

  const [picked, setPicked] = useState<string[]>([])
  const [delegating, setDelegating] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)
  const [exporting, setExporting] = useState(false)
  const [exportJob, setExportJob] = useState<ExportJob | null>(null)

  const items = queue.items
  const selectable = items.filter(canSelect).map((i) => i.scan_id)
  // Only scans still shown and still free can stay picked, whatever the filters did meanwhile.
  const chosen = picked.filter((id) => selectable.includes(id))
  const allChosen =
    selectable.length > 0 && chosen.length === Math.min(selectable.length, MAX_BATCH)
  const someChosen = chosen.length > 0 && !allChosen
  const toggle = (scanId: string, on: boolean) =>
    setPicked((s) => (on ? [...s, scanId].slice(0, MAX_BATCH) : s.filter((id) => id !== scanId)))

  const clearAll = () =>
    patch({
      status: [],
      schemas: [],
      capturedBy: [],
      from: '',
      to: '',
      search: '',
      decidedFrom: '',
    })
  const dateRange = { from: filters.from, to: filters.to }
  const nameOf = <T,>(list: T[] | undefined, id: string, key: (t: T) => [string, string]) =>
    list?.map(key).find(([value]) => value === id)?.[1]

  const chips: Chip[] = []
  if (filters.status.length)
    chips.push({
      key: 'status',
      text: listChip(
        'Status',
        filters.status.map((s) => statusLabels[s]),
      ),
      onRemove: () => patch({ status: [] }),
    })
  if (filters.schemas.length)
    chips.push({
      key: 'schema',
      text: listChip(
        'Schema',
        filters.schemas.map(
          (id) => nameOf(types.data, id, (t) => [t.type_id, t.name]) ?? 'Unknown',
        ),
      ),
      onRemove: () => patch({ schemas: [] }),
    })
  if (filters.capturedBy.length)
    chips.push({
      key: 'by',
      text: listChip(
        'Captured by',
        filters.capturedBy.map(
          (id) => nameOf(technicians.data, id, (t) => [t.user_id, t.full_name]) ?? 'Unknown',
        ),
      ),
      onRemove: () => patch({ capturedBy: [] }),
    })
  if (filters.search)
    chips.push({
      key: 'search',
      text: `Scan ID: ${filters.search}`,
      onRemove: () => patch({ search: '' }),
    })
  if (filters.decidedFrom)
    chips.push({
      key: 'decided',
      text: `Decided from ${dayLabel(filters.decidedFrom)}`,
      onRemove: () => patch({ decidedFrom: '' }),
    })
  if (filters.from || filters.to)
    chips.push({
      key: 'date',
      text: rangeChip('Date', dateRange),
      onRemove: () => patch({ from: '', to: '' }),
    })

  const columns: Column<QueueItem>[] = [
    {
      header: (
        <label className="inline-flex cursor-pointer items-center gap-2">
          <input
            type="checkbox"
            className="size-4.5 accent-brand-navy"
            aria-label="Select all waiting scans shown"
            disabled={selectable.length === 0}
            checked={allChosen}
            ref={(el) => {
              if (el) el.indeterminate = someChosen
            }}
            onChange={(e) => setPicked(e.target.checked ? selectable.slice(0, MAX_BATCH) : [])}
          />
        </label>
      ),
      width: '1.5rem', // just the checkbox: a share of the width would leave blank room beside it
      align: 'right',
      cell: (item) =>
        canSelect(item) ? (
          <input
            type="checkbox"
            className="size-4.5 accent-brand-navy"
            aria-label={`Select ${item.record_no}`}
            checked={chosen.includes(item.scan_id)}
            disabled={!chosen.includes(item.scan_id) && chosen.length >= MAX_BATCH}
            onChange={(e) => toggle(item.scan_id, e.target.checked)}
          />
        ) : null,
    },
    {
      header: (
        <ColumnHeader label="Scan ID">
          <ColumnFilter label="Scan ID" active={filters.search !== ''}>
            {(close) => (
              <TextSearchFilter
                title="Scan ID"
                value={filters.search}
                onChange={(search) => patch({ search })}
                onDone={close}
                placeholder="For example 100 000 039 6"
                hint="Spaces don't matter, and part of an ID is enough."
              />
            )}
          </ColumnFilter>
        </ColumnHeader>
      ),
      width: 1.6,
      cell: (item) => (
        <Link to={`/review-queue/${item.scan_id}`} className="block min-w-0 hover:underline">
          <span className="font-mono font-semibold">{formatScanId(item.record_no)}</span>
          {item.resubmitted && (
            <span className="mt-1 block">
              <Badge tone="warning">Resubmitted · rev {item.revision_no}</Badge>
            </span>
          )}
        </Link>
      ),
    },
    {
      header: (
        <ColumnHeader label="Schema">
          <ColumnFilter label="Schema" active={filters.schemas.length > 0}>
            {(close) => (
              <CheckListFilter
                title="Schema"
                options={(types.data ?? []).map((t) => ({ value: t.type_id, label: t.name }))}
                selected={filters.schemas}
                onChange={(schemas) => patch({ schemas })}
                onDone={close}
              />
            )}
          </ColumnFilter>
        </ColumnHeader>
      ),
      width: 1.4,
      cell: (item) => (
        <span className="block truncate" title={item.equipment_type_name}>
          {item.equipment_type_name}
        </span>
      ),
    },
    {
      header: (
        <ColumnHeader label="Captured by">
          <ColumnFilter label="Captured by" active={filters.capturedBy.length > 0}>
            {(close) => (
              <CheckListFilter
                title="Captured by"
                searchable
                options={(technicians.data ?? []).map((t) => ({
                  value: t.user_id,
                  label: t.full_name,
                }))}
                selected={filters.capturedBy}
                onChange={(capturedBy) => patch({ capturedBy })}
                onDone={close}
              />
            )}
          </ColumnFilter>
        </ColumnHeader>
      ),
      width: 1.1,
      cell: (item) => item.captured_by_name,
    },
    {
      // Flags and technician edits are not columns here: the scan page shows them in full.
      header: 'Location',
      width: 1.8,
      cell: (item) => (
        <span className="block truncate" title={item.location_path}>
          {item.location_path}
        </span>
      ),
    },
    {
      header: (
        <ColumnHeader label="Date">
          <SortToggle
            label="Date"
            direction={filters.sort === 'newest_first' ? 'newest_first' : 'oldest_first'}
            // Default order (oldest first, scans a technician holds last) or newest first.
            onToggle={() => patch({ sort: filters.sort === 'newest_first' ? '' : 'newest_first' })}
          />
          <ColumnFilter label="Date" align="right" active={Boolean(filters.from || filters.to)}>
            {(close) => (
              <DateRangeFilter
                title="Date"
                value={dateRange}
                onChange={(range) => patch(range)}
                onDone={close}
                max={istDay()}
                hint="The day the scan was captured. Leave a side empty for no limit."
              />
            )}
          </ColumnFilter>
        </ColumnHeader>
      ),
      width: 1.3,
      cell: (item) => <span className="font-mono text-meta">{dateTime(item.date)}</span>,
    },
    {
      header: (
        <ColumnHeader label="Status">
          <ColumnFilter label="Status" align="right" active={filters.status.length > 0}>
            {(close) => (
              <CheckListFilter
                title="Status"
                options={ALL_STATUSES.map((s) => ({ value: s, label: statusLabels[s] }))}
                selected={filters.status}
                onChange={(status) => patch({ status: status as QueueStatus[] })}
                onDone={close}
              />
            )}
          </ColumnFilter>
        </ColumnHeader>
      ),
      width: 1.5,
      cell: (item) => <StatusCell item={item} />,
    },
  ]

  const count = `${items.length}${queue.hasNextPage ? '+' : ''} ${items.length === 1 ? 'scan' : 'scans'}`
  const filtered = isFiltered(filters)
  const allScope = { key: 'all', label: `All scans in ${unitName}`, filters: { bu_id: buId } }
  const approvedScope = {
    key: 'approved',
    label: 'Approved scans only',
    filters: { bu_id: buId, review_status: 'approved' },
  }

  return (
    <>
      <PageHeader
        title="Review queue"
        actions={
          <Button variant="secondary" onClick={() => setExporting(true)}>
            Export CSV
          </Button>
        }
      />
      <div className="flex grow flex-col gap-4 overflow-y-auto px-8 pt-6 pb-8 *:shrink-0">
        {notice && (
          <Alert tone="info" role="status">
            {notice}
          </Alert>
        )}
        {exportJob && <ExportJobNotice key={exportJob.export_id} job={exportJob} />}
        <SelectionBar
          count={chosen.length}
          hint={`Select up to ${MAX_BATCH} to delegate as one batch`}
          onClear={() => setPicked([])}
          onDelegate={() => setDelegating(true)}
        />
        <div className="flex flex-wrap items-center justify-between gap-3">
          <FilterChips chips={chips} onClearAll={clearAll} />
          <p role="status" className="ml-auto text-small text-ink-muted">
            {queue.isPending ? '' : count}
          </p>
        </div>
        {queue.isPending ? (
          <Card>Loading the review queue…</Card>
        ) : queue.isError ? (
          <Card>We couldn't load the review queue. Please refresh.</Card>
        ) : (
          <>
            <DataTable
              label="Review queue scans"
              columns={columns}
              rows={items}
              rowKey={(item) => item.scan_id}
              empty={
                filtered ? (
                  <>
                    No scans match these filters.{' '}
                    <button
                      type="button"
                      className={buttonClasses('link')}
                      onClick={() => clearAll()}
                    >
                      Clear all filters
                    </button>
                  </>
                ) : (
                  'Nothing under review here.'
                )
              }
            />
            <LoadMore
              hasNextPage={queue.hasNextPage}
              isFetchingNextPage={queue.isFetchingNextPage}
              fetchNextPage={queue.fetchNextPage}
            />
          </>
        )}
      </div>

      {delegating && (
        <DelegateBatchDialog
          buId={buId}
          scanIds={chosen}
          onClose={() => setDelegating(false)}
          onDone={() => {
            setDelegating(false)
            setPicked([])
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
              label: `Scans under review · ${counts.data?.waiting ?? 0}`,
              filters: { bu_id: buId, review_status: 'waiting_for_approval' },
            },
            allScope,
            approvedScope,
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

/** One status, with who is behind it: the technician holding a waiting scan, or who decided. */
function StatusCell({ item }: { item: QueueItem }) {
  if (item.status === 'waiting') {
    const wait = waitingStatus(item.waiting_since)
    return (
      <span className="flex flex-col items-start gap-1">
        <Badge
          tone={wait.tone}
          title={`Under review for ${wait.label === 'under 1 h' ? 'less than 1 h' : wait.label}`}
        >
          {statusLabels.waiting}
        </Badge>
        {item.batch_id && (
          <span className="text-meta text-ink-subtle">
            With {item.assigned_to_name} ·{' '}
            <Link
              to={`/delegations/${item.batch_id}`}
              className="font-semibold text-brand-navy hover:underline"
            >
              {item.batch_no}
            </Link>
          </span>
        )}
      </span>
    )
  }
  const approved = item.status === 'approved'
  return (
    <span className="flex flex-col items-start gap-1">
      <Badge tone={approved ? 'success' : 'danger'}>{approved ? 'Approved' : 'Rejected'}</Badge>
      {item.decided_by_name && (
        <span className="text-meta text-ink-subtle">{item.decided_by_name}</span>
      )}
    </span>
  )
}
