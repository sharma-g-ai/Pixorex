import { describe, expect, it } from 'vitest'
import type { Invite } from '../../api/invites'
import { accountStatus, inviteExpired, inviteStatus } from './inviteStatus'

const now = new Date('2026-10-05T12:00:00Z')

const invite = (over: Partial<Invite>): Invite => ({
  invite_id: 'i',
  email: 'n.kim@ppg.com',
  role: 'field_technician',
  units: [],
  invited_by_name: 'R. Kowalski',
  created_at: '2026-10-05T10:00:00Z',
  expires_at: '2026-10-06T10:00:00Z',
  status: 'pending',
  ...over,
})

describe('inviteStatus', () => {
  it('GIVEN a pending invite THEN hours left', () => {
    expect(inviteStatus(invite({}), now)).toEqual({ label: 'Pending · 22 h left', tone: 'warning' })
  })

  it('GIVEN a pending invite past expiry THEN Expired', () => {
    const late = invite({ expires_at: '2026-10-05T11:00:00Z' })
    expect(inviteStatus(late, now)?.label).toBe('Expired')
    expect(inviteExpired(late, now)).toBe(true)
  })

  it('GIVEN accepted or cancelled THEN not shown', () => {
    expect(inviteStatus(invite({ status: 'accepted' }), now)).toBeNull()
    expect(inviteStatus(invite({ status: 'cancelled' }), now)).toBeNull()
  })
})

describe('accountStatus', () => {
  it.each([
    ['active', 'Active'],
    ['invited', 'Not activated yet'],
    ['removed', 'Removed · needs new invite'],
  ] as const)('%s → %s', (status, label) => {
    expect(accountStatus(status).label).toBe(label)
  })
})
