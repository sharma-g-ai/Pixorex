import { useState } from 'react'
import { Link, useSearchParams } from 'react-router'
import { useBatchList, type Batch, type BatchFilters } from '../../api/review'
import { useTechnicians } from '../../api/technicians'
import { useDashboard } from '../../app/DashboardContext'
import { Badge } from '../../components/Badge'
import { buttonClasses } from '../../components/buttonClasses'
import { Card } from '../../components/Card'
import {
  CheckListFilter,
  ColumnFilter,
  ColumnHeader,
  DateRangeFilter,
  FilterChips,
  SortToggle,
  type Chip,
} from '../../components/ColumnFilter'
import { listChip, rangeChip } from '../../components/filterChips'
import { DataTable, type Column } from '../../components/DataTable'
import { LoadMore } from '../../components/LoadMore'
import { PageHeader } from '../../components/layout/PageHeader'
import { ProgressBar } from '../../components/ProgressBar'
import { Tabs } from '../../components/Tabs'
import { dateTime, istDay } from '../../lib/time'
import { DecisionsTable } from './DecisionsTable'
import { batchState, batchStateLabels, batchStatus, type BatchState } from './reviewRules'

/** BU-04 Delegation console: batches, and what technicians decided (canvas BU 13-19; contracts 3.10-3.14). */
export function DelegationsPage() {
  const { unit } = useDashboard()
  if (!unit?.bu_id) return null
  return <DelegationsOfUnit key={unit.bu_id} buId={unit.bu_id} />
}

const stateOptions = (Object.keys(batchStateLabels) as BatchState[]).map((value) => ({
  value,
  label: batchStateLabels[value],
}))

function DelegationsOfUnit({ buId }: { buId: string }) {
  const [params] = useSearchParams()
  const [tab, setTab] = useState<'batches' | 'decisions'>(
    params.get('tab') === 'decided' ? 'decisions' : 'batches',
  )

  return (
    <>
      <PageHeader
        title="Delegations"
        subtitle="Batches you handed to technicians, and what they decided"
      />
      <div className="flex grow flex-col gap-4 overflow-y-auto px-8 pt-6 pb-8 *:shrink-0">
        <Tabs
          label="Delegations"
          tabs={[
            { key: 'batches', label: 'Batches' },
            { key: 'decisions', label: 'All decisions' },
          ]}
          current={tab}
          onChange={setTab}
        />
        {tab === 'decisions' ? (
          <DecisionsTable buId={buId} scanPath={(id) => `/review-queue/${id}`} />
        ) : (
          <BatchList buId={buId} />
        )}
      </div>
    </>
  )
}

/** The unit's batches with the filters of their column headers. One way in: Open. */
function BatchList({ buId }: { buId: string }) {
  const [assignedTo, setAssignedTo] = useState<string[]>([])
  const [states, setStates] = useState<string[]>([])
  const [range, setRange] = useState({ from: '', to: '' })
  const [sort, setSort] = useState<BatchFilters['sort']>('newest_first')
  const technicians = useTechnicians(buId)
  const list = useBatchList(buId, { assignedTo, ...range, sort })

  // Status is read from each batch (no progress is worked out from its age), so it is
  // filtered here on the batches loaded.
  const shown = states.length
    ? list.items.filter((b) => states.includes(batchState(b)))
    : list.items

  const nameOf = (id: string) =>
    technicians.data?.find((t) => t.user_id === id)?.full_name ?? 'Unknown'
  const chips: Chip[] = []
  if (assignedTo.length)
    chips.push({
      key: 'to',
      text: listChip('Delegated to', assignedTo.map(nameOf)),
      onRemove: () => setAssignedTo([]),
    })
  if (range.from || range.to)
    chips.push({
      key: 'date',
      text: rangeChip('Delegated', range),
      onRemove: () => setRange({ from: '', to: '' }),
    })
  if (states.length)
    chips.push({
      key: 'status',
      text: listChip(
        'Status',
        states.map((s) => batchStateLabels[s as BatchState]),
      ),
      onRemove: () => setStates([]),
    })
  const clearAll = () => {
    setAssignedTo([])
    setStates([])
    setRange({ from: '', to: '' })
  }

  const columns: Column<Batch>[] = [
    {
      header: 'Batch',
      width: 0.6,
      cell: (b) => (
        <Link to={`/delegations/${b.batch_id}`} className="font-mono font-semibold hover:underline">
          {b.batch_no}
        </Link>
      ),
    },
    {
      header: (
        <ColumnHeader label="Delegated to">
          <ColumnFilter label="Delegated to" active={assignedTo.length > 0}>
            {(close) => (
              <CheckListFilter
                title="Delegated to"
                searchable
                options={(technicians.data ?? []).map((t) => ({
                  value: t.user_id,
                  label: t.full_name,
                }))}
                selected={assignedTo}
                onChange={setAssignedTo}
                onDone={close}
              />
            )}
          </ColumnFilter>
        </ColumnHeader>
      ),
      width: 1.3,
      cell: (b) => b.assigned_to_name,
    },
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
    {
      header: (
        <ColumnHeader label="Delegated">
          <SortToggle
            label="Delegated"
            direction={sort}
            onToggle={() =>
              setSort((s) => (s === 'newest_first' ? 'oldest_first' : 'newest_first'))
            }
          />
          <ColumnFilter label="Delegated" align="right" active={Boolean(range.from || range.to)}>
            {(close) => (
              <DateRangeFilter
                title="Delegated"
                value={range}
                onChange={setRange}
                onDone={close}
                max={istDay()}
                hint="The day the batch was made. Leave a side empty for no limit."
              />
            )}
          </ColumnFilter>
        </ColumnHeader>
      ),
      width: 1.1,
      cell: (b) => dateTime(b.created_at),
    },
    {
      header: (
        <ColumnHeader label="Status">
          <ColumnFilter label="Status" align="right" active={states.length > 0}>
            {(close) => (
              <CheckListFilter
                title="Status"
                options={stateOptions}
                selected={states}
                onChange={setStates}
                onDone={close}
              />
            )}
          </ColumnFilter>
        </ColumnHeader>
      ),
      width: 1.3,
      cell: (b) => {
        const status = batchStatus(b)
        return <Badge tone={status.tone}>{status.label}</Badge>
      },
    },
    {
      header: 'Actions',
      width: 0.8,
      align: 'right',
      cell: (b) => (
        <Link
          to={`/delegations/${b.batch_id}`}
          className={buttonClasses('link')}
          aria-label={`Open batch ${b.batch_no}`}
        >
          Open →
        </Link>
      ),
    },
  ]

  if (list.isPending) return <Card>Loading batches…</Card>
  if (list.isError) return <Card>We couldn't load the batches. Please refresh.</Card>
  return (
    <div className="flex flex-col gap-3">
      <FilterChips chips={chips} onClearAll={clearAll} />
      <DataTable
        label="Delegated batches"
        columns={columns}
        rows={shown}
        rowKey={(b) => b.batch_id}
        empty={
          chips.length
            ? 'No batches match these filters.'
            : 'No batches yet. Select scans in the review queue to delegate them.'
        }
      />
      <LoadMore
        hasNextPage={list.hasNextPage}
        isFetchingNextPage={list.isFetchingNextPage}
        fetchNextPage={list.fetchNextPage}
      />
    </div>
  )
}
