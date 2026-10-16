import { describe, expect, it } from 'vitest'
import type { Batch, ReviewField } from '../../api/review'
import {
  batchStatus,
  editsSummary,
  flagText,
  technicianDecisionStatus,
  verificationStatus,
  waitingStatus,
} from './reviewRules'

const now = new Date('2026-10-05T12:00:00Z')
const field = (over: Partial<ReviewField>): ReviewField => ({
  field_key: 'k',
  label: 'Model number',
  ai_value: 'A',
  confidence: 0.42,
  flag_reasons: [],
  technician_value: null,
  verification_state: 'accepted',
  unreadable_reason: null,
  note: null,
  ...over,
})
const batch = (over: Partial<Batch>): Batch => ({
  batch_id: 'b',
  batch_no: 'B-14',
  assigned_to_name: 'T. Nguyen',
  created_by_name: 'R. Kowalski',
  scan_count: 30,
  decided_count: 0,
  created_at: '2026-10-03T12:00:00Z',
  reminded_at: null,
  status: 'active',
  ...over,
})

describe('review rules', () => {
  it('colours waiting time by age', () => {
    expect(waitingStatus('2026-10-05T07:00:00Z', now)).toEqual({ label: '5 h', tone: 'neutral' })
    expect(waitingStatus('2026-10-03T10:00:00Z', now)).toEqual({ label: '2 days', tone: 'warning' })
    expect(waitingStatus('2026-09-26T10:00:00Z', now)).toEqual({ label: '9 days', tone: 'danger' })
  })

  it('summarises technician edits', () => {
    expect(editsSummary({ corrected_count: 2, unreadable_count: 1 })).toBe(
      '2 corrected · 1 unreadable',
    )
    expect(editsSummary({ corrected_count: 0, unreadable_count: 0 })).toBe('—')
  })

  it('explains flags in words', () => {
    expect(flagText(field({ flag_reasons: ['low_confidence'] }))).toBe('Low confidence · 42%')
    expect(flagText(field({ flag_reasons: ['critical_not_found'] }))).toBe(
      'Critical field · not found',
    )
    expect(flagText(field({}))).toBe('—')
  })

  it('names what the technician did', () => {
    expect(verificationStatus(field({ verification_state: 'corrected' })).label).toBe('Corrected')
    expect(
      verificationStatus(
        field({ verification_state: 'unreadable', unreadable_reason: 'label_worn' }),
      ).label,
    ).toBe('Unreadable · label worn')
    expect(verificationStatus(field({ flag_reasons: ['no_confidence'] })).label).toBe(
      'Kept as read',
    )
    expect(verificationStatus(field({})).label).toBe('Looks right')
  })

  it('labels technician decisions', () => {
    const base = {
      decision_id: 'd',
      scan_id: 's',
      record_no: 'R',
      decided_by_name: 'T',
      decided_at: '',
    }
    expect(
      technicianDecisionStatus({
        ...base,
        decision: 'rejected',
        reject_category: 'image_unclear',
        overridden: false,
      }).label,
    ).toBe('Rejected · Image unclear')
    expect(
      technicianDecisionStatus({
        ...base,
        decision: 'approved',
        reject_category: null,
        overridden: true,
      }).label,
    ).toBe('Overridden by you')
  })

  it('flags batches with no progress after a day', () => {
    expect(batchStatus(batch({}), now)).toEqual({ label: 'No progress · 2 days', tone: 'warning' })
    expect(batchStatus(batch({ decided_count: 18 }), now).label).toBe('In progress')
    expect(batchStatus(batch({ decided_count: 30 }), now).label).toBe('Done')
  })
})
