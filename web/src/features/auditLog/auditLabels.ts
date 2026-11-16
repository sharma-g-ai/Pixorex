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

/** "05 Oct 12:30:07" in the viewer's time zone. */
export function auditTime(iso: string): string {
  const d = new Date(iso)
  const day = d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short' })
  const time = d.toLocaleTimeString('en-GB', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  })
  return `${day} ${time}`
}

/**
 * One colour per kind of action, so a row can be told apart at a glance. Soft fill, strong
 * text: every pair reads at 4.5:1 or better. `dot` is the same hue for the small marker.
 */
export const auditCategoryColors: Record<AuditCategory, { pill: string; dot: string }> = {
  users: { pill: 'bg-info-soft text-info', dot: 'bg-info' },
  sign_in: { pill: 'bg-page text-ink-muted', dot: 'bg-ink-subtle' },
  escalation: { pill: 'bg-warning-soft text-warning', dot: 'bg-warning' },
  review: { pill: 'bg-brand-navy-soft text-brand-navy', dot: 'bg-brand-navy' },
  override: { pill: 'bg-danger-soft text-danger', dot: 'bg-danger' },
  locations: { pill: 'bg-teal-soft text-teal', dot: 'bg-teal' },
  equipment_types: { pill: 'bg-success-soft text-success', dot: 'bg-success' },
  export: { pill: 'bg-violet-soft text-violet', dot: 'bg-violet' },
  retention: { pill: 'bg-page text-ink-muted', dot: 'bg-ink-subtle' },
}
