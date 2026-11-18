import { describe, expect, it } from 'vitest'
import type { Batch, ReviewField } from '../../api/review'
import {
  assignmentStatus,
  batchState,
  batchStatus,
  decidedByText,
  decisionOutcome,
  decisionOutcomeStatus,
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
  open_count: 0,
  overridden_count: 0,
  overridden_unseen_count: 0,
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

  it('explains flags in words', () => {
    expect(flagText(field({ flag_reasons: ['low_confidence'] }))).toBe('Low confidence · 42%')
    expect(flagText(field({ flag_reasons: ['format_failed'] }))).toBe(
      "Doesn't match the field type",
    )
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
      equipment_type_name: 'Motor Nameplate',
      decided_by_name: 'T',
      decided_at: '',
      batch_id: null,
      batch_no: null,
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
    ).toBe('Changed → Rejected')
  })

  it('GIVEN a decision THEN the badge says where it ended and the line says who, why and "changed by you"', () => {
    const base = {
      decision_id: 'd',
      scan_id: 's',
      record_no: 'R',
      equipment_type_name: 'Motor Nameplate',
      decided_by_name: 'Amrutha',
      decided_at: '',
      batch_id: null,
      batch_no: null,
    }
    const rejected = { ...base, decision: 'rejected', reject_category: 'data_correction_needed' }
    expect(decisionOutcomeStatus({ ...rejected, overridden: false })).toEqual({
      label: 'Rejected', // the reason is in the line under it, not repeated here
      tone: 'danger',
    })
    expect(decidedByText({ ...rejected, overridden: false })).toBe(
      'Rejected by Amrutha · Data correction needed',
    )
    const approved = { ...base, decision: 'approved', reject_category: null, overridden: true }
    expect(decisionOutcomeStatus(approved)).toEqual({ label: 'Changed → Rejected', tone: 'danger' })
    expect(decidedByText(approved)).toBe('Approved by Amrutha · changed by you')
  })

  it('GIVEN an overridden decision THEN its outcome is the other way', () => {
    expect(decisionOutcome({ decision: 'approved', overridden: false })).toBe('approved')
    expect(decisionOutcome({ decision: 'approved', overridden: true })).toBe('rejected')
    expect(decisionOutcome({ decision: 'rejected', overridden: false })).toBe('rejected')
    expect(decisionOutcome({ decision: 'rejected', overridden: true })).toBe('approved')
  })

  it('flags batches with no progress after a day', () => {
    expect(batchStatus(batch({}), now)).toEqual({ label: 'No progress · 2 days', tone: 'warning' })
    expect(batchStatus(batch({ decided_count: 18 }), now).label).toBe('In progress')
    expect(batchStatus(batch({ decided_count: 30 }), now).label).toBe('Done')
  })
})

describe('batch states for the list filter', () => {
  it.each([
    [{}, 'no_progress'],
    [{ decided_count: 18 }, 'in_progress'],
    [{ decided_count: 30 }, 'done'],
    [{ status: 'taken_back' as const }, 'taken_back'],
    [{ status: 'completed' as const }, 'done'],
    [{ created_at: '2026-10-05T06:00:00Z' }, 'in_progress'], // nothing done yet, but under a day
  ])('%j → %s', (over, expected) => {
    expect(batchState(batch(over), now)).toBe(expected)
  })
})

describe('status of one scan on the batch page', () => {
  const outcome = (over: Record<string, unknown> = {}) => ({
    decision: 'approved' as const,
    reject_category: null,
    decided_by_name: 'Meera Iyer',
    decided_at: '2026-10-05T10:00:00Z',
    overridden: false,
    ...over,
  })
  const a = (over: Record<string, unknown> = {}) =>
    assignmentStatus(
      { status: 'assigned', removed_reason: null, outcome: null, ...over } as Parameters<
        typeof assignmentStatus
      >[0],
      'Priya Nair',
    )

  it('GIVEN a scan still with the technician THEN it is Delegated', () => {
    expect(a()).toEqual({ key: 'delegated', label: 'Delegated', tone: 'neutral', detail: null })
  })

  it('GIVEN an approval THEN Approved, nothing under it', () => {
    expect(a({ status: 'decided', outcome: outcome() })).toEqual({
      key: 'approved',
      label: 'Approved',
      tone: 'success',
      detail: null,
    })
  })

  it('GIVEN a rejection THEN Rejected with the reason', () => {
    expect(
      a({
        status: 'decided',
        outcome: outcome({ decision: 'rejected', reject_category: 'image_unclear' }),
      }),
    ).toMatchObject({ key: 'rejected', label: 'Rejected', tone: 'danger', detail: 'Image unclear' })
  })

  it('GIVEN an admin changed the technician’s decision THEN says who, "you" for the viewer', () => {
    const changed = (by: string) =>
      a({
        status: 'decided',
        outcome: outcome({ decision: 'rejected', overridden: true, decided_by_name: by }),
      })
    expect(changed('Priya Nair').detail).toBe('Changed by you')
    expect(changed('Erin Admin').detail).toBe('Changed by Erin Admin')
  })

  it.each([
    ['taken_back', 'Taken back'],
    ['reassigned', 'Reassigned'],
    ['user_removed', 'Removed'],
  ])('GIVEN a scan that left undecided (%s) THEN says %s', (reason, label) => {
    expect(a({ status: 'removed', removed_reason: reason })).toMatchObject({
      key: 'removed',
      label,
      tone: 'neutral',
    })
  })

  it('GIVEN an admin decided it themselves (left the batch) THEN shows the decision, not "Removed"', () => {
    expect(
      a({
        status: 'removed',
        removed_reason: 'admin_decided',
        outcome: outcome({ decided_by_name: 'Priya Nair' }),
      }),
    ).toMatchObject({ key: 'approved', label: 'Approved' })
  })
})
