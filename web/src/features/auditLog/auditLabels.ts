import type { AuditCategory, AuditEntry } from '../../api/auditLog'

/** "Type" column and the "All actions ▾" menu (canvas EA 22, 52). */
export const auditCategoryLabels: Record<AuditCategory, string> = {
  users: 'Users',
  sign_in: 'Sign-in',
  escalation: 'Escalation',
  review: 'Review',
  override: 'Override',
  locations: 'Locations',
  equipment_types: 'Equipment types',
  export: 'Export',
  retention: 'Retention',
}

/** "A. Mehta", or "System" for automatic actions. */
export function actorName(entry: Pick<AuditEntry, 'actor_type' | 'actor_name'>): string {
  return entry.actor_type === 'system' ? 'System' : (entry.actor_name ?? 'Unknown user')
}

/** "05 Oct 12:30" in the viewer's time zone. */
export function auditTime(iso: string): string {
  const d = new Date(iso)
  const day = d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short' })
  const time = d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' })
  return `${day} ${time}`
}
