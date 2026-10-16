import { useState } from 'react'
import { Link } from 'react-router'
import { useTechnicianDecisions, type TechnicianDecision } from '../../api/review'
import { Badge } from '../../components/Badge'
import { buttonClasses } from '../../components/buttonClasses'
import { DataTable, type Column } from '../../components/DataTable'
import { Tabs } from '../../components/Tabs'
import { timeAgo } from '../../lib/time'
import { technicianDecisionStatus } from './reviewRules'

type Filter = 'all' | 'approved' | 'rejected'

/**
 * Decisions technicians made in delegated batches, to check or override
 * (canvas BU 19; contract 3.6). Each row opens the scan.
 */
export function TechnicianDecisionsTable({
  buId,
  scanPath,
}: {
  buId: string
  scanPath: (scanId: string) => string
}) {
  const [filter, setFilter] = useState<Filter>('all')
  const decisions = useTechnicianDecisions(buId, filter === 'all' ? undefined : filter)

  const columns: Column<TechnicianDecision>[] = [
    {
      header: 'Scan',
      width: 1.2,
      cell: (d) => <span className="font-mono font-semibold">{d.record_no}</span>,
    },
    {
      header: 'Decision',
      width: 1.6,
      cell: (d) => {
        const status = technicianDecisionStatus(d)
        return <Badge tone={status.tone}>{status.label}</Badge>
      },
    },
    { header: 'Reviewed by', width: 1.2, cell: (d) => d.decided_by_name },
    { header: 'When', width: 1, cell: (d) => timeAgo(d.decided_at) },
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
      <Tabs<Filter>
        label="Decision filter"
        tabs={[
          { key: 'all', label: 'All decisions' },
          { key: 'approved', label: 'Approved' },
          { key: 'rejected', label: 'Rejected' },
        ]}
        current={filter}
        onChange={setFilter}
      />
      {decisions.isPending ? (
        <p className="text-body text-ink-muted">Loading decisions…</p>
      ) : (
        <DataTable
          label="Decisions by technicians"
          columns={columns}
          rows={decisions.data ?? []}
          rowKey={(d) => d.decision_id}
          empty="No decisions by technicians yet."
        />
      )}
    </div>
  )
}
