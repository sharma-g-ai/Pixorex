import type {
  Batch,
  QueueItem,
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
 * Longest waiting first: by when the scan entered the queue (its current revision's
 * submission, so a resubmitted scan counts from the resubmission), then by scan id so equal
 * times keep a fixed order. Items without a readable time go last instead of breaking the sort.
 * The API already returns this order; sorting here keeps it right whatever the data.
 */
export function oldestWaitingFirst<T extends { waiting_since: string; scan_id: string }>(
  items: readonly T[],
): T[] {
  return [...items].sort((a, b) => {
    const ta = timeOf(a.waiting_since)
    const tb = timeOf(b.waiting_since)
    if (ta === null || tb === null) {
      if (ta !== tb) return ta === null ? 1 : -1
    } else if (ta !== tb) {
      return ta - tb
    }
    return a.scan_id < b.scan_id ? -1 : a.scan_id > b.scan_id ? 1 : 0
  })
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

/** A bin (the place a scan was captured at) and the waiting scans nobody has been given. */
export interface Bin {
  path: string
  scanIds: string[]
}

/** Group the unassigned waiting scans by where they were captured, longest-waiting scans first. */
export function binsOf(items: readonly QueueItem[]): Bin[] {
  const byPath = new Map<string, QueueItem[]>()
  for (const item of items) {
    if (item.batch_no) continue // already with a technician
    byPath.set(item.location_path, [...(byPath.get(item.location_path) ?? []), item])
  }
  return [...byPath.entries()]
    .map(([path, scans]) => ({
      path,
      scanIds: oldestWaitingFirst(scans).map((s) => s.scan_id),
    }))
    .sort((a, b) => a.path.localeCompare(b.path))
}
