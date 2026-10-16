import type { Technician } from '../../api/technicians'
import { Badge } from '../../components/Badge'
import { buttonClasses } from '../../components/buttonClasses'
import { DataTable, type Column } from '../../components/DataTable'
import { Person } from '../../components/Person'
import { timeAgo } from '../../lib/time'
import { isLocked, technicianStatus } from './staffStatus'

interface TechniciansTableProps {
  technicians: Technician[]
  onRemove: (technician: Technician) => void
}

/** Technicians working in the unit (canvas BU 25, first table). */
export function TechniciansTable({ technicians, onRemove }: TechniciansTableProps) {
  const columns: Column<Technician>[] = [
    { header: 'Technician', width: 2, cell: (t) => <Person name={t.full_name} detail={t.email} /> },
    {
      header: 'Status',
      width: 1.5,
      cell: (t) => {
        const status = technicianStatus(t)
        return <Badge tone={status.tone}>{status.label}</Badge>
      },
    },
    { header: 'Units', width: 0.8, cell: (t) => t.units.map((u) => u.name).join(', ') || '—' },
    { header: 'Scans this month', width: 0.9, cell: (t) => t.scans_this_month },
    { header: 'Review batches', width: 1, cell: (t) => t.active_batch_no ?? '—' },
    {
      header: 'Last active',
      width: 0.9,
      cell: (t) => (t.last_active_at ? timeAgo(t.last_active_at) : 'Never'),
    },
    {
      header: 'Actions',
      width: 0.8,
      align: 'right',
      cell: (t) =>
        isLocked(t) ? (
          <span className="text-xs text-ink-subtle">Unlocks on its own</span>
        ) : (
          <button
            type="button"
            className={buttonClasses('danger-link')}
            aria-label={`Remove ${t.full_name}`}
            onClick={() => onRemove(t)}
          >
            Remove
          </button>
        ),
    },
  ]

  return (
    <DataTable
      label="Technicians"
      columns={columns}
      rows={technicians}
      rowKey={(t) => t.user_id}
      empty="No technicians yet. Invite the first one."
    />
  )
}
