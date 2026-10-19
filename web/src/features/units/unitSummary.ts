import type { BusinessUnit } from '../../api/businessUnits'

/** "1 technician", "14 technicians". */
export function technicianCount(unit: BusinessUnit): string {
  const n = unit.technician_count ?? 0
  return `${n} ${n === 1 ? 'technician' : 'technicians'}`
}

/** Names of the other units run by this unit's BU Admin ("Also runs ..."). */
export function otherUnitsOfAdmin(units: BusinessUnit[], unit: BusinessUnit): string[] {
  const adminId = unit.bu_admin?.user_id
  if (!adminId) return []
  return units
    .filter((u) => u.bu_id !== unit.bu_id && u.bu_admin?.user_id === adminId)
    .map((u) => u.name)
}

export interface NeedsYou {
  /** Scans not approved within 24 hours, across all units. */
  escalated: number
  /** Units whose BU Admin seat is vacant. */
  withoutBuAdmin: number
}

/** Totals for the EA "Needs you" panel. */
export function needsYou(units: BusinessUnit[]): NeedsYou {
  return {
    escalated: units.reduce((sum, u) => sum + (u.escalated_count ?? 0), 0),
    withoutBuAdmin: units.filter((u) => !u.bu_admin?.user_id).length,
  }
}
