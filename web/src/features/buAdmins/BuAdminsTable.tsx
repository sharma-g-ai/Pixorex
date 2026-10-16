import type { BuAdmin } from '../../api/buAdmins'
import { Badge } from '../../components/Badge'
import { buttonClasses } from '../../components/buttonClasses'
import { DataTable, type Column } from '../../components/DataTable'
import { Person } from '../../components/Person'
import { UnitBadges } from '../../components/UnitBadges'
import { timeAgo } from '../../lib/time'
import { accountStatus } from '../invites/inviteStatus'

interface BuAdminsTableProps {
  admins: BuAdmin[]
  onEdit: (admin: BuAdmin) => void
  onRemove: (admin: BuAdmin) => void
}

/** BU Admins and the units they run (canvas EA 13). */
export function BuAdminsTable({ admins, onEdit, onRemove }: BuAdminsTableProps) {
  const columns: Column<BuAdmin>[] = [
    { header: 'BU Admin', width: 2, cell: (a) => <Person name={a.full_name} detail={a.email} /> },
    { header: 'Units', width: 1.1, cell: (a) => <UnitBadges names={a.units.map((u) => u.name)} /> },
    {
      header: 'Status',
      width: 1.1,
      cell: (a) => {
        const status = accountStatus(a.status)
        return <Badge tone={status.tone}>{status.label}</Badge>
      },
    },
    {
      header: 'Last active',
      width: 0.9,
      cell: (a) => (
        <span className="text-ink-muted">
          {a.last_active_at ? timeAgo(a.last_active_at) : 'Never'}
        </span>
      ),
    },
    {
      header: 'Actions',
      width: 1.9,
      align: 'right',
      cell: (a) => (
        <div className="flex justify-end gap-3.5">
          <button
            type="button"
            className={buttonClasses('link')}
            aria-label={`Edit units of ${a.full_name}`}
            onClick={() => onEdit(a)}
          >
            Edit units
          </button>
          <button
            type="button"
            className={buttonClasses('danger-link')}
            aria-label={`Remove ${a.full_name}`}
            onClick={() => onRemove(a)}
          >
            Remove
          </button>
        </div>
      ),
    },
  ]

  return (
    <DataTable
      label="BU Admins"
      columns={columns}
      rows={admins.filter((a) => a.status !== 'removed')}
      rowKey={(a) => a.user_id}
      empty="No BU Admins yet. Invite one to run a unit."
    />
  )
}
