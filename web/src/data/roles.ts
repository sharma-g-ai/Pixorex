import type { Level, RoleKey, Scope } from './model'

export interface RoleInfo {
  key: RoleKey
  label: string
  level: Level
  /** Who holds it, from open item D-04. */
  heldBy: string
  sees: string
}

/**
 * Three roles, one per level, with the names from the reference screens (FR-23; D-13: one role
 * on the vessel). D-04's sales team are PPG Admins limited to some regions or customers;
 * Fleet Managers and Procurement are both Customer Admins.
 */
export const roles: RoleInfo[] = [
  { key: 'ppg-admin', label: 'PPG Admin', level: 'PPG', heldBy: 'PPG Sea Stock admin, PPG sales team', sees: 'All customers, or only their regions or customers' },
  { key: 'customer-admin', label: 'Customer Admin', level: 'Customer', heldBy: 'Fleet Manager, Procurement', sees: "Their customer's vessels" },
  { key: 'ship-admin', label: 'Ship Admin', level: 'Vessel', heldBy: 'Chief Officer', sees: 'Their own vessel' },
]

export function roleInfo(key: RoleKey): RoleInfo {
  const info = roles.find((r) => r.key === key)
  if (!info) throw new Error(`Unknown role ${key}`)
  return info
}

export type Permission =
  | 'view-overview'
  | 'view-stock'
  | 'export'
  | 'view-review'
  | 'resolve-unrecognised'
  | 'manage-customers'
  | 'manage-vessels'
  | 'manage-users'
  | 'manage-items'
  | 'manage-label-schema'
  | 'manage-geography'
  | 'capture-on-device'

export const permissionLabels: { key: Permission; label: string; note?: string }[] = [
  { key: 'view-overview', label: 'See the overview across vessels' },
  { key: 'view-stock', label: 'See Sea Stock, consumption, receipts and activity', note: 'Within the role’s scope' },
  { key: 'export', label: 'Roll up and export CSV' },
  { key: 'view-review', label: 'See items that need review' },
  { key: 'resolve-unrecognised', label: 'Match unrecognised scans to the master item list' },
  { key: 'manage-customers', label: 'Create and edit customers' },
  { key: 'manage-vessels', label: 'Create and edit vessels' },
  { key: 'manage-users', label: 'Create and edit users', note: 'Customer Admin: own customer only (to confirm)' },
  { key: 'manage-items', label: 'Maintain the master item list' },
  { key: 'manage-label-schema', label: 'Maintain the label schema' },
  { key: 'manage-geography', label: 'Maintain regions' },
  { key: 'capture-on-device', label: 'Receive, consume, baseline and adjust on the tablet' },
]

/**
 * What a user may do depends on the role and, for a PPG Admin, on the scope: only a PPG Admin
 * with access to all customers runs administration (proposal, to confirm with PPG).
 */
export type Access = 'ppg-all' | 'ppg-limited' | 'customer-admin' | 'ship-admin'

export const accessLabels: { key: Access; label: string; detail: string }[] = [
  { key: 'ppg-all', label: 'PPG Admin', detail: 'All customers' },
  { key: 'ppg-limited', label: 'PPG Admin', detail: 'Some regions or customers' },
  { key: 'customer-admin', label: 'Customer Admin', detail: 'Own customer' },
  { key: 'ship-admin', label: 'Ship Admin', detail: 'Own vessel' },
]

export function accessOf(user: { role: RoleKey; scope: Scope }): Access {
  if (user.role === 'ppg-admin') return user.scope.kind === 'all' ? 'ppg-all' : 'ppg-limited'
  return user.role
}

const grants: Record<Access, Permission[]> = {
  'ppg-all': [
    'view-overview', 'view-stock', 'export', 'view-review', 'resolve-unrecognised', 'manage-customers',
    'manage-vessels', 'manage-users', 'manage-items', 'manage-label-schema', 'manage-geography',
  ],
  'ppg-limited': ['view-overview', 'view-stock', 'export', 'view-review'],
  'customer-admin': ['view-overview', 'view-stock', 'export', 'view-review', 'manage-users'],
  'ship-admin': ['view-stock', 'export', 'capture-on-device'],
}

export function can(who: { role: RoleKey; scope: Scope } | Access, permission: Permission): boolean {
  return grants[typeof who === 'string' ? who : accessOf(who)].includes(permission)
}
