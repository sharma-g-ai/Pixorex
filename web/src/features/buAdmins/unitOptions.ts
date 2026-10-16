import type { BuAdmin } from '../../api/buAdmins'
import type { BusinessUnit } from '../../api/businessUnits'
import type { Invite } from '../../api/invites'
import type { UnitOption } from '../../components/UnitChecklist'

/** "No BU Admin", plus who has a pending invite for it. */
function vacantNote(unit: BusinessUnit, pendingInvites: Invite[], adding = false): string {
  const invite = pendingInvites.find(
    (i) => i.status === 'pending' && i.units.some((u) => u.bu_id === unit.bu_id),
  )
  if (!invite) return 'No BU Admin'
  return adding
    ? `No BU Admin — adding it cancels the pending invite to ${invite.email}`
    : `No BU Admin · invite pending for ${invite.email}`
}

/** Invite a BU Admin: only units without one can be picked (contract 1.8). */
export function inviteOptions(units: BusinessUnit[], pendingInvites: Invite[]): UnitOption[] {
  return units.map((unit) =>
    unit.bu_admin?.user_id
      ? {
          bu_id: unit.bu_id,
          name: unit.name,
          disabledReason: `Already run by ${unit.bu_admin.full_name}`,
        }
      : { bu_id: unit.bu_id, name: unit.name, note: vacantNote(unit, pendingInvites) },
  )
}

/** Edit units: their own units and vacant ones can be ticked; others' units can't (contract 1.16). */
export function editOptions(
  admin: BuAdmin,
  units: BusinessUnit[],
  pendingInvites: Invite[],
): UnitOption[] {
  return units.map((unit) => {
    const runner = unit.bu_admin?.user_id
    if (runner === admin.user_id) return { bu_id: unit.bu_id, name: unit.name }
    if (runner) {
      return {
        bu_id: unit.bu_id,
        name: unit.name,
        disabledReason: `Already run by ${unit.bu_admin?.full_name}`,
      }
    }
    return { bu_id: unit.bu_id, name: unit.name, note: vacantNote(unit, pendingInvites, true) }
  })
}

/** Remove: the units this BU Admin runs, with what is waiting there. */
export function removeOptions(admin: BuAdmin, units: BusinessUnit[]): UnitOption[] {
  return admin.units.map((own) => {
    const unit = units.find((u) => u.bu_id === own.bu_id)
    const waiting = unit?.waiting_count ?? 0
    const delegated = unit?.delegated_count ?? 0
    const parts = [`${waiting} waiting ${waiting === 1 ? 'scan' : 'scans'}`]
    if (delegated > 0) parts.push(`${delegated} delegated`)
    return { bu_id: own.bu_id, name: own.name, note: parts.join(' · ') }
  })
}
