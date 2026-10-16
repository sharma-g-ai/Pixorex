import { describe, expect, it } from 'vitest'
import type { Technician } from '../../api/technicians'
import { isLocked, splitTechnicians, technicianStatus } from './staffStatus'

const now = new Date('2026-10-05T12:00:00Z')

const tech = (over: Partial<Technician>): Technician => ({
  user_id: 'u',
  full_name: 'J. Martinez',
  email: 'j@ppg.test',
  status: 'active',
  sign_in_locked_until: null,
  units: [],
  scans_this_month: 0,
  active_batch_no: null,
  last_active_at: null,
  ...over,
})

describe('technicianStatus', () => {
  it('GIVEN an active technician THEN Active', () => {
    expect(technicianStatus(tech({}), now)).toEqual({ label: 'Active', tone: 'success' })
  })

  it('GIVEN a running sign-in lock THEN locked with minutes left', () => {
    const t = tech({ sign_in_locked_until: '2026-10-05T12:18:00Z' })
    expect(technicianStatus(t, now)).toEqual({
      label: 'Sign-in locked · 18 min left',
      tone: 'warning',
    })
    expect(isLocked(t, now)).toBe(true)
  })

  it('GIVEN a lock that has already ended THEN Active again', () => {
    const t = tech({ sign_in_locked_until: '2026-10-05T11:00:00Z' })
    expect(technicianStatus(t, now).label).toBe('Active')
    expect(isLocked(t, now)).toBe(false)
  })

  it('GIVEN a removed technician THEN needs a new invite', () => {
    expect(technicianStatus(tech({ status: 'removed' }), now).label).toBe(
      'Removed · needs new invite',
    )
  })
})

describe('splitTechnicians', () => {
  it('GIVEN mixed statuses THEN removed ones are separated', () => {
    const a = tech({ user_id: 'a' })
    const b = tech({ user_id: 'b', status: 'removed' })
    expect(splitTechnicians([a, b])).toEqual({ current: [a], removed: [b] })
  })
})
