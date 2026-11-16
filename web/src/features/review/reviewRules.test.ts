import { describe, expect, it } from 'vitest'
import type { Batch, ReviewField } from '../../api/review'
import {
  batchStatus,
  decidedByText,
  decisionOutcome,
  decisionOutcomeStatus,
  flagText,
  technicianDecisionStatus,
  oldestWaitingFirst,
  verificationStatus,
  waitingStatus,
} from './reviewRules'

describe('waiting queue order', () => {
  const at = (scan_id: string, waiting_since: string) => ({ scan_id, waiting_since })
  const ids = (list: { scan_id: string }[]) => list.map((i) => i.scan_id)

  it('GIVEN different waiting times THEN the longest waiting comes first', () => {
    const list = [
      at('new', '2026-10-05T11:00:00Z'),
      at('old', '2026-09-30T08:00:00Z'),
      at('mid', '2026-10-03T10:00:00Z'),
    ]
    expect(ids(oldestWaitingFirst(list))).toEqual(['old', 'mid', 'new'])
  })

  it('GIVEN a newly submitted scan THEN it joins at the bottom', () => {
    const list = [at('a', '2026-10-01T08:00:00Z'), at('b', '2026-10-02T08:00:00Z')]
    const after = oldestWaitingFirst([at('just-in', '2026-10-05T11:59:59Z'), ...list])
    expect(ids(after)).toEqual(['a', 'b', 'just-in'])
  })

  it('GIVEN the same second THEN the order is fixed by scan id, not random', () => {
    const t = '2026-10-05T10:00:00Z'
    expect(ids(oldestWaitingFirst([at('z', t), at('a', t)]))).toEqual(['a', 'z'])
  })

  it('GIVEN missing or unreadable times THEN those go last and the rest stay sorted', () => {
    const list = [
      at('bad', 'not a date'),
      at('b', '2026-10-02T08:00:00Z'),
      at('none', ''),
      at('a', '2026-10-01T08:00:00Z'),
    ]
    expect(ids(oldestWaitingFirst(list))).toEqual(['a', 'b', 'bad', 'none'])
    expect(waitingStatus('not a date', now)).toEqual({ label: 'Unknown', tone: 'neutral' })
  })

  it('does not change the list it was given', () => {
    const list = [at('b', '2026-10-02T08:00:00Z'), at('a', '2026-10-01T08:00:00Z')]
    oldestWaitingFirst(list)
    expect(ids(list)).toEqual(['b', 'a'])
  })
})

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
    ).toBe('Changed → Rejected')
  })

  it('GIVEN a decision THEN the badge says where it ended and the line says who, why and "changed by you"', () => {
    const base = {
      decision_id: 'd',
      scan_id: 's',
      record_no: 'R',
      decided_by_name: 'Amrutha',
      decided_at: '',
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
