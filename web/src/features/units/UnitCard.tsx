import { Link } from 'react-router'
import type { BusinessUnit } from '../../api/businessUnits'
import type { Invite } from '../../api/invites'
import { Person } from '../../components/Person'
import { timeAgo } from '../../lib/time'
import { technicianCount } from './unitSummary'

interface UnitCardProps {
  unit: BusinessUnit
  /** Other units the same BU Admin runs. */
  alsoRuns: string[]
  /** When the BU Admin was last active, if known. */
  adminLastActive?: string | null
  /** No BU Admin: the latest invite for the seat, if any. */
  invite?: Invite | null
}

/** One unit on the EA overview (canvas: EA 03 unit cards). */
export function UnitCard({ unit, alsoRuns, adminLastActive, invite }: UnitCardProps) {
  const admin = unit.bu_admin?.user_id ? unit.bu_admin : null
  const adminDetail =
    alsoRuns.length > 0
      ? `Also runs ${alsoRuns.join(', ')}`
      : adminLastActive
        ? `Active ${timeAgo(adminLastActive)}`
        : undefined

  return (
    <article
      aria-label={unit.name}
      className="flex min-w-0 flex-col gap-3.5 rounded-xl border border-line bg-surface px-5 py-4.5"
    >
      <div>
        <h3 className="text-unit-title font-bold">{unit.name}</h3>
        <p className="truncate text-small text-ink-subtle">{technicianCount(unit)}</p>
      </div>

      {admin ? (
        <div>
          <div className="mb-1.5 text-caption font-bold tracking-wider text-ink-subtle uppercase">
            BU Admin
          </div>
          <Person name={admin.full_name ?? ''} detail={adminDetail} />
        </div>
      ) : (
        <div className="rounded-lg bg-danger-soft px-3 py-2.5 text-small text-danger-strong">
          <b>No BU Admin.</b>{' '}
          {invite?.status === 'pending'
            ? `Invite to ${invite.email} pending`
            : 'Its scans that wait over 24 hours come to you.'}
        </div>
      )}

      <div className="mt-auto flex items-end justify-between rounded-lg bg-page px-3 py-2.5">
        <div>
          <div className="text-xl font-bold">{unit.waiting_count ?? 0}</div>
          <div className="text-meta text-ink-muted">waiting review</div>
        </div>
        <Link
          to={`/overview/units/${unit.bu_id}`}
          className="text-body-sm font-bold text-brand-navy"
          aria-label={`Open ${unit.name}`}
        >
          Open unit →
        </Link>
      </div>
    </article>
  )
}
