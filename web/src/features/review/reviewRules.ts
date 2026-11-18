import type {
  Assignment,
  Batch,
  RejectCategory,
  ReviewField,
  TechnicianDecision,
} from '../../api/review'
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

/** Milliseconds since 1970, or null when the time is missing or can't be read. */
export function timeOf(iso: string | null | undefined): number | null {
  if (!iso) return null
  const ms = new Date(iso).getTime()
  return Number.isNaN(ms) ? null : ms
}

/** Waiting badge: grey under a day, orange from 1 day, red from 1 week (canvas BU 05). */
export function waitingStatus(since: string, now = new Date()): BadgeStatus {
  if (timeOf(since) === null) return { label: 'Unknown', tone: 'neutral' }
  const days = daysSince(since, now)
  const tone = days >= 7 ? 'danger' : days >= 1 ? 'warning' : 'neutral'
  return { label: waitedFor(since, now), tone }
}

/**
 * Where a technician's decision left the scan: their own decision, or the opposite when a BU
 * Admin overrode it (contract 3.7 only ever replaces approved with rejected or the other way).
 */
export function decisionOutcome(
  d: Pick<TechnicianDecision, 'decision' | 'overridden'>,
): 'approved' | 'rejected' {
  const approved = d.decision === 'approved'
  return approved !== d.overridden ? 'approved' : 'rejected'
}

/**
 * The value that was submitted for a field: the technician's fix, else what the AI read and
 * the technician kept. Null when nothing was sent (marked unreadable or left empty).
 */
export function extractedText(
  field: Pick<ReviewField, 'ai_value' | 'technician_value' | 'verification_state'>,
): string | null {
  if (field.verification_state === 'unreadable' || field.verification_state === 'left_empty') {
    return null
  }
  return field.technician_value ?? field.ai_value
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
        // The value does not fit the field's type (a number, a date, ...). There is no
        // format check feature any more, so the old wording would mislead.
        return "Doesn't match the field type"
      case 'no_confidence':
        return 'No confidence score'
      case 'missing_required':
        return 'Missing · required'
      case 'critical_not_found':
        // Only on scans made before "critical" was removed (18 Nov 2026).
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

/**
 * Only where the scan ended: "Approved", "Rejected", or "Changed → Rejected" when the BU Admin
 * changed the technician's decision (same wording as the phone). Who, why and when go in the
 * line under it (decidedByText), so nothing is said twice.
 */
export function decisionOutcomeStatus(d: TechnicianDecision): BadgeStatus {
  const approved = decisionOutcome(d) === 'approved'
  const outcome = approved ? 'Approved' : 'Rejected'
  return {
    label: d.overridden ? `Changed → ${outcome}` : outcome,
    tone: approved ? 'success' : 'danger',
  }
}

/** Badge for a decision made by a technician in a table that has no line under it (canvas BU 19). */
export function technicianDecisionStatus(d: TechnicianDecision): BadgeStatus {
  if (d.overridden) return decisionOutcomeStatus(d)
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

/** The four states a batch is told apart by in the list's Status filter. */
export type BatchState = 'in_progress' | 'no_progress' | 'done' | 'taken_back'

export const batchStateLabels: Record<BatchState, string> = {
  in_progress: 'In progress',
  no_progress: 'No progress',
  done: 'Done',
  taken_back: 'Taken back',
}

export function batchState(batch: Batch, now = new Date()): BatchState {
  const label = batchStatus(batch, now).label
  if (label === 'Taken back') return 'taken_back'
  if (label === 'Done') return 'done'
  return label.startsWith('No progress') ? 'no_progress' : 'in_progress'
}

/** Where one scan of a batch stands, for the batch page: a status and a line under it. */
export interface AssignmentStatus {
  key: 'delegated' | 'approved' | 'rejected' | 'removed'
  label: string
  tone: BadgeStatus['tone']
  /** Reject reason, "Changed by you", or why it left the batch. */
  detail: string | null
}

const removedLabels: Record<string, string> = {
  taken_back: 'Taken back',
  reassigned: 'Reassigned',
  user_removed: 'Removed',
}

/**
 * Delegated: still with the technician. Approved or rejected: the current decision, with the
 * reason, or who changed the technician's decision. Removed: it left the batch undecided.
 */
export function assignmentStatus(
  a: Pick<Assignment, 'status' | 'removed_reason' | 'outcome'>,
  viewerName: string,
): AssignmentStatus {
  if (a.outcome) {
    const approved = a.outcome.decision === 'approved'
    const category = a.outcome.reject_category
      ? rejectCategoryLabels[a.outcome.reject_category as RejectCategory]
      : null
    const changedBy = a.outcome.decided_by_name === viewerName ? 'you' : a.outcome.decided_by_name
    return {
      key: approved ? 'approved' : 'rejected',
      label: approved ? 'Approved' : 'Rejected',
      tone: approved ? 'success' : 'danger',
      detail: a.outcome.overridden ? `Changed by ${changedBy}` : category,
    }
  }
  if (a.status === 'removed') {
    return {
      key: 'removed',
      label: removedLabels[a.removed_reason ?? ''] ?? 'Removed',
      tone: 'neutral',
      detail: null,
    }
  }
  return { key: 'delegated', label: 'Delegated', tone: 'neutral', detail: null }
}

/** What the technician decided: "Approved by T. Nguyen", "Rejected by A. Patel · Image unclear", plus "· changed by you". */
export function decidedByText(d: TechnicianDecision): string {
  const category = d.reject_category
    ? rejectCategoryLabels[d.reject_category as RejectCategory]
    : null
  const said =
    d.decision === 'approved'
      ? `Approved by ${d.decided_by_name}`
      : category
        ? `Rejected by ${d.decided_by_name} · ${category}`
        : `Rejected by ${d.decided_by_name}`
  return d.overridden ? `${said} · changed by you` : said
}
