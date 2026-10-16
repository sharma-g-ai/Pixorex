import type { Me, UnitRole } from '../api/me'

/** The two roles that use the web dashboard. Technicians use the mobile app only. */
export type DashboardRole = 'enterprise_admin' | 'bu_admin'

/** Which dashboard a user gets: EA wins over BU Admin; anyone else gets none. */
export function dashboardRole(me: Pick<Me, 'units'>): DashboardRole | null {
  if (me.units.some((u) => u.role === 'enterprise_admin')) return 'enterprise_admin'
  if (me.units.some((u) => u.role === 'bu_admin')) return 'bu_admin'
  return null
}

/** Units the user runs as BU Admin, in the order the API returns them. */
export function adminUnits(me: Pick<Me, 'units'>): UnitRole[] {
  return me.units.filter((u) => u.role === 'bu_admin' && u.bu_id !== null)
}

/**
 * The BU Admin's current unit: the active unit if they run it, else their
 * primary unit, else the first one. Null when they run no unit.
 */
export function currentAdminUnit(me: Pick<Me, 'units' | 'active_bu_id'>): UnitRole | null {
  const units = adminUnits(me)
  return (
    units.find((u) => u.bu_id === me.active_bu_id) ??
    units.find((u) => u.is_primary) ??
    units[0] ??
    null
  )
}
