import type { NotificationKind } from '../../api/notifications'
import type { DashboardRole } from '../../app/access'

/** Where an alert takes each admin (canvas EA 24, BU 04). */
export function notificationPath(kind: NotificationKind, role: DashboardRole): string {
  const ea = role === 'enterprise_admin'
  switch (kind) {
    case 'scans_escalated':
    case 'escalation_reminder':
      return ea ? '/escalations' : '/review-queue'
    case 'unit_no_bu_admin':
      return ea ? '/bu-admins' : '/home'
    case 'invite_expired':
      return ea ? '/bu-admins' : '/technicians'
    case 'batch_delegated':
    case 'batch_no_progress':
    case 'batch_reminder':
    case 'batch_reassigned':
    case 'batch_taken_back':
    case 'scan_removed_from_batch':
    case 'ea_delegated_in_unit':
      return ea ? '/escalations' : '/delegations'
    case 'export_ready':
      return ea ? '/scans' : '/review-queue'
    default:
      return ea ? '/scans' : '/review-queue'
  }
}
