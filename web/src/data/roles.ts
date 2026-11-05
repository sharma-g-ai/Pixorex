import type { RoleKey } from './model'

export interface RoleInfo {
  key: RoleKey
  label: string
  /** Who holds it (BRD v1.3 FR-22, D-04). */
  heldBy: string
  sees: string
}

/**
 * Two portal roles (data model Domain 1). The vessel is the tablet's user and signs in only on
 * the tablet; crew have no personal accounts (D-13: one role at vessel level).
 */
export const roles: RoleInfo[] = [
  { key: 'ppg-admin', label: 'PPG Admin', heldBy: 'PPG Sea Stock admin, PPG sales team', sees: 'Every customer and vessel' },
  { key: 'customer-admin', label: 'Customer Admin', heldBy: 'Fleet Manager, Procurement', sees: "Their own customer's vessels" },
]

export function roleInfo(key: RoleKey): RoleInfo {
  const info = roles.find((r) => r.key === key)
  if (!info) throw new Error(`Unknown role ${key}`)
  return info
}

export type Permission =
  | 'view-stock'
  | 'export'
  | 'view-review'
  | 'adjust-stock'
  | 'match-scans'
  | 'close-held-events'
  | 'manage-customers'
  | 'import-customers'
  | 'manage-vessels'
  | 'import-vessels'
  | 'manage-tablets'
  | 'reset-vessel-password'
  | 'manage-users'
  | 'manage-items'
  | 'view-audit'

export const permissionLabels: { key: Permission; label: string; note?: string }[] = [
  { key: 'view-stock', label: 'See Sea Stock, consumption, delivery notes and transactions', note: 'Customer Admin: own customer only' },
  { key: 'export', label: 'Roll up and export CSV' },
  { key: 'view-review', label: 'See items that need review' },
  { key: 'adjust-stock', label: 'Adjust a vessel’s stock from the portal, with a reason', note: 'Who may is not stated in the BRD (to confirm)' },
  { key: 'match-scans', label: 'Match unrecognised scans to an article' },
  { key: 'close-held-events', label: 'Resolve or dismiss held sync events', note: 'To confirm' },
  { key: 'manage-customers', label: 'Add and edit customers' },
  { key: 'import-customers', label: 'Import customers from Excel' },
  { key: 'manage-vessels', label: 'Add and edit vessels' },
  { key: 'import-vessels', label: 'Import vessels from Excel', note: 'Customer Admin: own customer only' },
  { key: 'manage-tablets', label: 'Pair tablets (enrolment code); prepare to retire, retire now or revoke a tablet', note: 'Customer Admin: own vessels only' },
  { key: 'reset-vessel-password', label: 'Reset a vessel’s sign-in password, e.g. at crew change', note: 'Customer Admin: own vessels only' },
  { key: 'manage-users', label: 'Invite and edit users', note: 'Customer Admin: Customer Admins of their own customer only (to confirm)' },
  { key: 'manage-items', label: 'Maintain the master item list' },
  { key: 'view-audit', label: 'See the audit log', note: 'Customer Admin: own customer only (to confirm)' },
]

const grants: Record<RoleKey, Permission[]> = {
  'ppg-admin': [
    'view-stock', 'export', 'view-review', 'adjust-stock', 'match-scans', 'close-held-events',
    'manage-customers', 'import-customers', 'manage-vessels', 'import-vessels', 'manage-tablets',
    'reset-vessel-password', 'manage-users', 'manage-items', 'view-audit',
  ],
  'customer-admin': [
    'view-stock', 'export', 'view-review', 'adjust-stock', 'import-vessels', 'manage-tablets',
    'reset-vessel-password', 'manage-users', 'view-audit',
  ],
}

export function can(who: { role: RoleKey } | RoleKey, permission: Permission): boolean {
  return grants[typeof who === 'string' ? who : who.role].includes(permission)
}
