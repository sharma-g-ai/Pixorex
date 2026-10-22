import type { Level, RoleKey } from './model'

export interface RoleInfo {
  key: RoleKey
  label: string
  level: Level
  /** Who holds it, from open item D-04. */
  heldBy: string
  sees: string
}

/** FR-23: administrator and user roles at PPG and customer level; one role at vessel level (D-13). */
export const roles: RoleInfo[] = [
  { key: 'ppg-admin', label: 'PPG Administrator', level: 'PPG', heldBy: 'PPG Sea Stock admin', sees: 'All customers and vessels' },
  { key: 'ppg-user', label: 'PPG User', level: 'PPG', heldBy: 'PPG sales team', sees: 'Customers in their regions, or the customers assigned to them' },
  { key: 'customer-admin', label: 'Customer Administrator', level: 'Customer', heldBy: 'Fleet Manager', sees: "Their customer's vessels" },
  { key: 'customer-user', label: 'Customer User', level: 'Customer', heldBy: 'Procurement', sees: "Their customer's vessels" },
  { key: 'vessel-user', label: 'Vessel User', level: 'Vessel', heldBy: 'Chief Officer', sees: 'Their own vessel' },
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
  { key: 'manage-users', label: 'Create and edit users', note: 'Customer Administrator: own customer only (to confirm)' },
  { key: 'manage-items', label: 'Maintain the master item list' },
  { key: 'manage-label-schema', label: 'Maintain the label schema' },
  { key: 'manage-geography', label: 'Maintain regions' },
  { key: 'capture-on-device', label: 'Receive, consume, baseline and adjust on the tablet' },
]

const grants: Record<RoleKey, Permission[]> = {
  'ppg-admin': [
    'view-overview', 'view-stock', 'export', 'view-review', 'resolve-unrecognised', 'manage-customers',
    'manage-vessels', 'manage-users', 'manage-items', 'manage-label-schema', 'manage-geography',
  ],
  'ppg-user': ['view-overview', 'view-stock', 'export', 'view-review'],
  'customer-admin': ['view-overview', 'view-stock', 'export', 'view-review', 'manage-users'],
  'customer-user': ['view-overview', 'view-stock', 'export'],
  'vessel-user': ['view-stock', 'export', 'capture-on-device'],
}

export function can(role: RoleKey, permission: Permission): boolean {
  return grants[role].includes(permission)
}
