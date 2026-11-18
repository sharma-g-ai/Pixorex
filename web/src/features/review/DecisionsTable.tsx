import { useState } from 'react'
import { Link } from 'react-router'
import { useDecisionList, type DecisionFilters, type TechnicianDecision } from '../../api/review'
import { useTechnicians } from '../../api/technicians'
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
import { formatScanId } from '../../lib/scanId'
import { dateTime, istDay } from '../../lib/time'
import { decisionOutcome, rejectCategoryLabels } from './reviewRules'

const choices = [
  { value: 'approved', label: 'Approved' },
  { value: 'rejected', label: 'Rejected' },
]

/**
 * Every decision technicians made in delegated batches, to check or override (canvas BU 19;
 * contract 3.6). Filters sit in the column headers; each row opens the scan.
 */
export function DecisionsTable({
  buId,
  scanPath,
}: {
  buId: string
  scanPath: (scanId: string) => string
}) {
  const [decisions, setDecisions] = useState<string[]>([])
  const [decidedBy, setDecidedBy] = useState<string[]>([])
  const [range, setRange] = useState({ from: '', to: '' })
  const [sort, setSort] = useState<DecisionFilters['sort']>('newest_first')
  const technicians = useTechnicians(buId)

  // The API takes one decision; both ticked, or none, means no filter.
  const only = decisions.length === 1 ? (decisions[0] as 'approved' | 'rejected') : ''
  const list = useDecisionList(buId, { decision: only, decidedBy, ...range, sort })

  const nameOf = (id: string) =>
    technicians.data?.find((t) => t.user_id === id)?.full_name ?? 'Unknown'
  const chips: Chip[] = []
  if (decisions.length)
    chips.push({
      key: 'decision',
      text: listChip(
        'Decision',
        decisions.map((d) => choices.find((c) => c.value === d)?.label ?? d),
      ),
      onRemove: () => setDecisions([]),
    })
  if (decidedBy.length)
    chips.push({
      key: 'by',
      text: listChip('Reviewed by', decidedBy.map(nameOf)),
      onRemove: () => setDecidedBy([]),
    })
  if (range.from || range.to)
    chips.push({
      key: 'when',
      text: rangeChip('When', range),
      onRemove: () => setRange({ from: '', to: '' }),
    })
  const clearAll = () => {
    setDecisions([])
    setDecidedBy([])
    setRange({ from: '', to: '' })
  }

  const columns: Column<TechnicianDecision>[] = [
    {
      header: 'Scan',
      width: 1.2,
      cell: (d) => <span className="font-mono font-semibold">{formatScanId(d.record_no)}</span>,
    },
    {
      header: 'Batch',
      width: 0.8,
      cell: (d) =>
        d.batch_id ? (
          <Link
            to={`/delegations/${d.batch_id}`}
            className="font-mono font-semibold text-brand-navy hover:underline"
          >
            {d.batch_no}
          </Link>
        ) : (
          <span className="text-ink-subtle">—</span>
        ),
    },
    {
      header: (
        <ColumnHeader label="Decision">
          <ColumnFilter label="Decision" active={decisions.length > 0}>
            {(close) => (
              <CheckListFilter
                title="Decision"
                options={choices}
                selected={decisions}
                onChange={setDecisions}
                onDone={close}
              />
            )}
          </ColumnFilter>
        </ColumnHeader>
      ),
      width: 1.5,
      cell: (d) => {
        const approved = decisionOutcome(d) === 'approved'
        const detail = d.overridden
          ? 'Changed by you'
          : d.reject_category
            ? rejectCategoryLabels[d.reject_category as keyof typeof rejectCategoryLabels]
            : null
        return (
          <span className="flex flex-col items-start gap-1">
            <Badge tone={approved ? 'success' : 'danger'}>
              {approved ? 'Approved' : 'Rejected'}
            </Badge>
            {detail && <span className="text-meta text-ink-subtle">{detail}</span>}
          </span>
        )
      },
    },
    {
      header: (
        <ColumnHeader label="Reviewed by">
          <ColumnFilter label="Reviewed by" active={decidedBy.length > 0}>
            {(close) => (
              <CheckListFilter
                title="Reviewed by"
                searchable
                options={(technicians.data ?? []).map((t) => ({
                  value: t.user_id,
                  label: t.full_name,
                }))}
                selected={decidedBy}
                onChange={setDecidedBy}
                onDone={close}
              />
            )}
          </ColumnFilter>
        </ColumnHeader>
      ),
      width: 1.2,
      cell: (d) => d.decided_by_name,
    },
    {
      header: (
        <ColumnHeader label="When">
          <SortToggle
            label="When"
            direction={sort}
            onToggle={() =>
              setSort((s) => (s === 'newest_first' ? 'oldest_first' : 'newest_first'))
            }
          />
          <ColumnFilter label="When" align="right" active={Boolean(range.from || range.to)}>
            {(close) => (
              <DateRangeFilter
                title="When"
                value={range}
                onChange={setRange}
                onDone={close}
                max={istDay()}
                hint="The day the technician decided. Leave a side empty for no limit."
              />
            )}
          </ColumnFilter>
        </ColumnHeader>
      ),
      width: 1.2,
      cell: (d) => <span className="font-mono text-meta">{dateTime(d.decided_at)}</span>,
    },
    {
      header: 'Actions',
      width: 0.8,
      align: 'right',
      cell: (d) => (
        <Link
          to={scanPath(d.scan_id)}
          className={buttonClasses('link')}
          aria-label={`Check ${d.record_no}`}
        >
          Check →
        </Link>
      ),
    },
  ]

  return (
    <div className="flex flex-col gap-3">
      <FilterChips chips={chips} onClearAll={clearAll} />
      {list.isPending ? (
        <Card>Loading decisions…</Card>
      ) : list.isError ? (
        <Card>We couldn't load the decisions. Please refresh.</Card>
      ) : (
        <>
          <DataTable
            label="Decisions by technicians"
            columns={columns}
            rows={list.items}
            rowKey={(d) => d.decision_id}
            empty={
              chips.length
                ? 'No decisions match these filters.'
                : 'No decisions by technicians yet.'
            }
          />
          <LoadMore
            hasNextPage={list.hasNextPage}
            isFetchingNextPage={list.isFetchingNextPage}
            fetchNextPage={list.fetchNextPage}
          />
        </>
      )}
    </div>
  )
}
