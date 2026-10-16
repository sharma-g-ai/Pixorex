import { Link } from 'react-router'
import type { BusinessUnit } from '../../api/businessUnits'
import { Person } from '../../components/Person'

interface UnitCardProps {
  unit: BusinessUnit
  /** Other units the same BU Admin runs. */
  alsoRuns: string[]
}

/** One unit on the EA overview (canvas: EA 03 unit cards). */
export function UnitCard({ unit, alsoRuns }: UnitCardProps) {
  const admin = unit.bu_admin?.user_id ? unit.bu_admin : null

  return (
    <article
      aria-label={unit.name}
      className="flex min-w-0 flex-col gap-3.5 rounded-xl border border-line bg-surface px-5 py-4.5"
    >
      <div>
        <h3 className="text-unit-title font-bold">{unit.name}</h3>
        <p className="truncate text-small text-ink-subtle">{unit.facility_name}</p>
      </div>

      {admin ? (
        <div>
          <div className="mb-1.5 text-caption font-bold tracking-wider text-ink-subtle uppercase">
            BU Admin
          </div>
          <Person
            name={admin.full_name ?? ''}
            detail={alsoRuns.length > 0 ? `Also runs ${alsoRuns.join(', ')}` : undefined}
          />
        </div>
      ) : (
        <div className="rounded-lg bg-danger-soft px-3 py-2.5 text-small text-danger-strong">
          <b>No BU Admin.</b> Its scans that wait over 24 hours come to you.
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
