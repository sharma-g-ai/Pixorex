import type { ScanFilters, ScanRow } from '../../api/scans'
import type { BadgeStatus } from '../../components/Badge'

const statuses: Record<string, BadgeStatus> = {
  waiting_for_approval: { label: 'Waiting review', tone: 'warning' },
  approved: { label: 'Approved', tone: 'success' },
  rejected: { label: 'Rejected', tone: 'danger' },
  closed: { label: 'Closed', tone: 'neutral' },
  draft: { label: 'Draft', tone: 'neutral' },
  discarded: { label: 'Discarded', tone: 'neutral' },
}

type StatusRow = Pick<ScanRow, 'review_status' | 'reviewed_by' | 'assignment'>
type ReviewedByRow = Pick<ScanRow, 'reviewed_by' | 'assignment' | 'escalation_reason'>

/** Review status of a scan as a badge (canvas EA 20): "Delegated", "Rejected · overridden". */
export function scanStatus(row: StatusRow): BadgeStatus {
  if (row.review_status === 'waiting_for_approval' && row.assignment) {
    return { label: 'Delegated', tone: 'neutral' }
  }
  const status = statuses[row.review_status] ?? { label: row.review_status, tone: 'neutral' }
  return row.reviewed_by?.overrode_name
    ? { ...status, label: `${status.label} · overridden` }
    : status
}

/** "Reviewed by" column: "T. Nguyen → R. Kowalski", "A. Patel · B-15", "escalated to you", "—". */
export function reviewedByText(row: ReviewedByRow): string {
  if (row.reviewed_by) {
    const { name, overrode_name } = row.reviewed_by
    return overrode_name ? `${overrode_name} → ${name}` : name
  }
  if (row.assignment) return `${row.assignment.assigned_to_name} · ${row.assignment.batch_no}`
  if (row.escalation_reason === 'no_bu_admin') return 'no BU Admin'
  if (row.escalation_reason === 'not_approved_24h') return 'escalated to you'
  return '—'
}

export type StatusFilter = 'any' | 'waiting' | 'approved' | 'rejected' | 'delegated'

export const statusFilterLabels: Record<StatusFilter, string> = {
  any: 'Any status',
  waiting: 'Waiting review',
  approved: 'Approved',
  rejected: 'Rejected',
  delegated: 'Delegated',
}

/** The "Any status ▾" menu as contract 3.18 query filters. */
export function statusQuery(
  filter: StatusFilter,
): Pick<ScanFilters, 'review_status' | 'delegated'> {
  switch (filter) {
    case 'waiting':
      return { review_status: 'waiting_for_approval' }
    case 'approved':
    case 'rejected':
      return { review_status: filter }
    case 'delegated':
      return { delegated: true }
    default:
      return {}
  }
}
