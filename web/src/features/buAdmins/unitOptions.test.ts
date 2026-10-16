import { describe, expect, it } from 'vitest'
import type { BuAdmin } from '../../api/buAdmins'
import type { BusinessUnit } from '../../api/businessUnits'
import type { Invite } from '../../api/invites'
import { editOptions, inviteOptions, removeOptions } from './unitOptions'

const rk = { user_id: 'rk', full_name: 'R. Kowalski' }
const sa = { user_id: 'sa', full_name: 'S. Alvi' }
const unit = (
  bu_id: string,
  name: string,
  bu_admin: typeof rk | null,
  waiting = 0,
): BusinessUnit => ({
  bu_id,
  name,
  facility_name: name,
  bu_admin,
  waiting_count: waiting,
  locations_status: 'published',
})
const units = [
  unit('p04', 'Plant 04', rk, 23),
  unit('p07', 'Plant 07', sa),
  unit('p11', 'Plant 11', null),
]
const pending: Invite[] = [
  {
    invite_id: 'i1',
    email: 'm.lopez@ppg.com',
    role: 'bu_admin',
    units: [{ bu_id: 'p11', name: 'Plant 11' }],
    invited_by_name: 'A. Mehta',
    created_at: '2026-10-05T06:00:00Z',
    expires_at: '2026-10-06T06:00:00Z',
    status: 'pending',
  },
]
const admin: BuAdmin = {
  user_id: 'rk',
  full_name: 'R. Kowalski',
  email: 'rk@ppg.com',
  status: 'active',
  last_active_at: null,
  units: [{ bu_id: 'p04', name: 'Plant 04' }],
}

describe('inviteOptions', () => {
  it('GIVEN units with and without BU Admins THEN only vacant units can be picked', () => {
    expect(inviteOptions(units, pending)).toEqual([
      { bu_id: 'p04', name: 'Plant 04', disabledReason: 'Already run by R. Kowalski' },
      { bu_id: 'p07', name: 'Plant 07', disabledReason: 'Already run by S. Alvi' },
      { bu_id: 'p11', name: 'Plant 11', note: 'No BU Admin · invite pending for m.lopez@ppg.com' },
    ])
  })
})

describe('editOptions', () => {
  it('GIVEN R. Kowalski THEN own and vacant units are open, others are not', () => {
    const [own, other, vacant] = editOptions(admin, units, pending)
    expect(own).toEqual({ bu_id: 'p04', name: 'Plant 04' })
    expect(other?.disabledReason).toBe('Already run by S. Alvi')
    expect(vacant?.note).toBe(
      'No BU Admin — adding it cancels the pending invite to m.lopez@ppg.com',
    )
  })
})

describe('removeOptions', () => {
  it('GIVEN R. Kowalski THEN lists only their units with waiting scans', () => {
    expect(removeOptions(admin, units)).toEqual([
      { bu_id: 'p04', name: 'Plant 04', note: '23 waiting scans' },
    ])
  })
})
