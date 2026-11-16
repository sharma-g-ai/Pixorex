import { useState } from 'react'
import { Link } from 'react-router'
import { useTechnicianDecisions, type QueueItem } from '../../api/review'
import { Badge, type BadgeStatus } from '../../components/Badge'
import { buttonClasses } from '../../components/buttonClasses'
import { DataTable, type Column } from '../../components/DataTable'
import { Tabs } from '../../components/Tabs'
import { dateTime } from '../../lib/time'
import { formatScanId } from '../../lib/scanId'
import {
  decisionOutcome,
  oldestWaitingFirst,
  technicianDecisionStatus,
  timeOf,
} from './reviewRules'

type Filter = 'all' | 'waiting' | 'approved' | 'rejected'

interface Row {
  key: string
  scanId: string
  recordNo: string
  typeName: string | null
  technician: string
  status: BadgeStatus
  /** "Waiting since" for a scan still with a technician, "Decided" once they decided. */
  whenLabel: string
  at: string
  action: string
}

/**
 * Everything delegated to technicians in one table (was two tabs: "Delegated" and "Decided by
 * technicians"): scans still with a technician first, longest waiting on top, then what
 * technicians decided, newest first. Each row opens the scan, where a technician's approval
 * can be overridden.
 */
export function DelegatedTable({
  waiting,
  buId,
  scanPath,
}: {
  /** The queue's delegated scans (still waiting for the technician's decision). */
  waiting: readonly QueueItem[]
  buId: string
  scanPath: (scanId: string) => string
}) {
  const [filter, setFilter] = useState<Filter>('all')
  // All of them, filtered here by where the scan ended up: asking the API for "approved"
  // returns what the technician decided, so a technician approval you overrode to rejected
  // would show under Approved.
  const decisions = useTechnicianDecisions(buId)

  const pending: Row[] =
    filter === 'all' || filter === 'waiting'
      ? oldestWaitingFirst(waiting).map((item) => ({
          key: `w-${item.scan_id}`,
          scanId: item.scan_id,
          recordNo: item.record_no,
          typeName: item.equipment_type_name,
          technician: item.assigned_to_name ?? '—',
          status: {
            label: item.batch_no ? `Waiting · ${item.batch_no}` : 'Waiting',
            tone: 'warning',
          },
          whenLabel: 'Waiting since',
          at: item.waiting_since,
          action: 'Open',
        }))
      : []
  const decided: Row[] =
    filter === 'waiting'
      ? []
      : [...(decisions.data ?? [])]
          .filter((d) => filter === 'all' || decisionOutcome(d) === filter)
          .sort((a, b) => (timeOf(b.decided_at) ?? 0) - (timeOf(a.decided_at) ?? 0))
          .map((d) => ({
            key: `d-${d.decision_id}`,
            scanId: d.scan_id,
            recordNo: d.record_no,
            typeName: null,
            technician: d.decided_by_name,
            status: technicianDecisionStatus(d),
            whenLabel: 'Decided',
            at: d.decided_at,
            action: 'Check',
          }))

  const columns: Column<Row>[] = [
    {
      header: 'Scan',
      width: 1.6,
      cell: (r) => (
        <span className="block min-w-0">
          {r.typeName && <span className="block truncate font-semibold">{r.typeName}</span>}
          <span className="font-mono text-meta text-ink-subtle">{formatScanId(r.recordNo)}</span>
        </span>
      ),
    },
    { header: 'Technician', width: 1.2, cell: (r) => r.technician },
    {
      header: 'Status',
      width: 1.6,
      cell: (r) => <Badge tone={r.status.tone}>{r.status.label}</Badge>,
    },
    {
      header: 'When',
      width: 1.3,
      cell: (r) => (
        <span className="flex flex-col">
          <span className="text-meta text-ink-subtle">{r.whenLabel}</span>
          <span className="font-mono text-meta">
            {timeOf(r.at) === null ? '—' : dateTime(r.at)}
          </span>
        </span>
      ),
    },
    {
      header: 'Actions',
      width: 0.8,
      align: 'right',
      cell: (r) => (
        <Link
          to={scanPath(r.scanId)}
          className={buttonClasses('link')}
          aria-label={`${r.action} ${r.recordNo}`}
        >
          {r.action} →
        </Link>
      ),
    },
  ]

  return (
    <div className="flex flex-col gap-3">
      <Tabs<Filter>
        label="Delegated filter"
        tabs={[
          { key: 'all', label: 'All' },
          { key: 'waiting', label: 'Waiting', count: waiting.length },
          { key: 'approved', label: 'Approved' },
          { key: 'rejected', label: 'Rejected' },
        ]}
        current={filter}
        onChange={setFilter}
      />
      {filter !== 'waiting' && decisions.isPending ? (
        <p className="text-body text-ink-muted">Loading decisions…</p>
      ) : (
        <DataTable
          label="Delegated scans"
          columns={columns}
          rows={[...pending, ...decided]}
          rowKey={(r) => r.key}
          empty="Nothing delegated to technicians."
        />
      )}
    </div>
  )
}
