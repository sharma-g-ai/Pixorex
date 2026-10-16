import type { Batch, RejectCategory, ReviewField, TechnicianDecision } from '../../api/review'
import type { BadgeStatus } from '../../components/Badge'
import { daysSince, waitedFor } from '../../lib/time'

export const rejectCategoryLabels: Record<RejectCategory, string> = {
  image_unclear: 'Image unclear',
  data_correction_needed: 'Data correction needed',
  wrong_equipment_type: 'Wrong equipment type',
  other: 'Other',
}

const unreadableLabels: Record<string, string> = {
  label_worn: 'label worn',
  not_on_nameplate: 'not on the nameplate',
  covered_or_unreachable: 'covered or unreachable',
  other: 'other',
}

/** Waiting badge: grey under a day, orange from 1 day, red from 1 week (canvas BU 05). */
export function waitingStatus(since: string, now = new Date()): BadgeStatus {
  const days = daysSince(since, now)
  const tone = days >= 7 ? 'danger' : days >= 1 ? 'warning' : 'neutral'
  return { label: waitedFor(since, now), tone }
}

/** "2 corrected · 1 unreadable", or "—" when the technician changed nothing. */
export function editsSummary(item: { corrected_count: number; unreadable_count: number }): string {
  const parts = []
  if (item.corrected_count) parts.push(`${item.corrected_count} corrected`)
  if (item.unreadable_count) parts.push(`${item.unreadable_count} unreadable`)
  return parts.join(' · ') || '—'
}

/** Why the AI value was flagged, in words (data model: ai_field_value.flag_reasons). */
export function flagText(field: Pick<ReviewField, 'flag_reasons' | 'confidence'>): string {
  const texts = field.flag_reasons.map((reason) => {
    switch (reason) {
      case 'low_confidence':
        return field.confidence === null
          ? 'Low confidence'
          : `Low confidence · ${Math.round(field.confidence * 100)}%`
      case 'format_failed':
        return 'Format check failed'
      case 'no_confidence':
        return 'No confidence score'
      case 'missing_required':
        return 'Missing · required'
      case 'critical_not_found':
        return 'Critical field · not found'
      default:
        return reason
    }
  })
  return texts.join(' · ') || '—'
}

/** What the technician did with the field (data model: revision_field.verification_state). */
export function verificationStatus(field: ReviewField): BadgeStatus {
  switch (field.verification_state) {
    case 'corrected':
      return { label: 'Corrected', tone: 'neutral' }
    case 'unreadable': {
      const reason = field.unreadable_reason ? unreadableLabels[field.unreadable_reason] : null
      return { label: reason ? `Unreadable · ${reason}` : 'Unreadable', tone: 'neutral' }
    }
    case 'left_empty':
      return { label: 'Left empty', tone: 'warning' }
    default:
      return field.flag_reasons.length > 0
        ? { label: 'Kept as read', tone: 'success' }
        : { label: 'Looks right', tone: 'success' }
  }
}

/** Badge for a decision made by a technician (canvas BU 19). */
export function technicianDecisionStatus(d: TechnicianDecision): BadgeStatus {
  if (d.overridden) return { label: 'Overridden by you', tone: 'neutral' }
  if (d.decision === 'approved') return { label: 'Approved', tone: 'success' }
  const category = d.reject_category
    ? rejectCategoryLabels[d.reject_category as RejectCategory]
    : null
  return { label: category ? `Rejected · ${category}` : 'Rejected', tone: 'danger' }
}

/** Batch progress and status (canvas BU 13). No progress for a day or more is called out. */
export function batchStatus(batch: Batch, now = new Date()): BadgeStatus {
  if (batch.status === 'taken_back') return { label: 'Taken back', tone: 'neutral' }
  if (batch.status === 'completed' || batch.decided_count >= batch.scan_count) {
    return { label: 'Done', tone: 'success' }
  }
  const days = daysSince(batch.created_at, now)
  if (batch.decided_count === 0 && days >= 1) {
    return { label: `No progress · ${days} ${days === 1 ? 'day' : 'days'}`, tone: 'warning' }
  }
  return { label: 'In progress', tone: 'neutral' }
}

/** "Approved by T. Nguyen" or "Rejected by A. Patel · Image unclear". */
export function decidedByText(d: TechnicianDecision): string {
  if (d.decision === 'approved') return `Approved by ${d.decided_by_name}`
  const category = d.reject_category
    ? rejectCategoryLabels[d.reject_category as RejectCategory]
    : null
  return category
    ? `Rejected by ${d.decided_by_name} · ${category}`
    : `Rejected by ${d.decided_by_name}`
}
