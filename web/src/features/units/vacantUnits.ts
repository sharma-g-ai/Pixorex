import type { BusinessUnit } from '../../api/businessUnits'
import type { Invite } from '../../api/invites'

/** A unit without a BU Admin and the latest BU Admin invite for it (canvas EA "Needs you"). */
export interface VacantUnit {
  unit: BusinessUnit
  /** Latest pending or expired invite; cancelled and accepted ones are history. */
  invite: Invite | null
}

/** Units with no BU Admin, most waiting scans first. */
export function vacantUnits(units: BusinessUnit[], invites: Invite[]): VacantUnit[] {
  return units
    .filter((u) => !u.bu_admin?.user_id)
    .map((unit) => {
      const invite =
        invites
          .filter(
            (i) =>
              i.role === 'bu_admin' &&
              (i.status === 'pending' || i.status === 'expired') &&
              i.units.some((u) => u.bu_id === unit.bu_id),
          )
          .sort((a, b) => b.created_at.localeCompare(a.created_at))[0] ?? null
      return { unit, invite }
    })
    .sort((a, b) => (b.unit.waiting_count ?? 0) - (a.unit.waiting_count ?? 0))
}
