import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { BuAdmin } from '../../api/buAdmins'
import type { BusinessUnit } from '../../api/businessUnits'
import type { Invite } from '../../api/invites'
import { BuAdminsPage } from './BuAdminsPage'

const setUnits = vi.fn()
const removeAdmin = vi.fn()
const createInvite = vi.fn()

const rk: BuAdmin = {
  user_id: 'rk',
  full_name: 'R. Kowalski',
  email: 'r.kowalski@ppg.com',
  status: 'active',
  last_active_at: null,
  units: [
    { bu_id: 'p04', name: 'Plant 04' },
    { bu_id: 'p05', name: 'Plant 05' },
  ],
}
const unit = (bu_id: string, name: string, admin: BuAdmin | null): BusinessUnit => ({
  bu_id,
  name,
  facility_name: name,
  bu_admin: admin ? { user_id: admin.user_id, full_name: admin.full_name } : null,
  waiting_count: 3,
  locations_status: 'published',
})
const units = [
  unit('p04', 'Plant 04', rk),
  unit('p05', 'Plant 05', rk),
  unit('p11', 'Plant 11', null),
]
const invites: Invite[] = [
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
  {
    invite_id: 'i2',
    email: 'tech@ppg.com',
    role: 'field_technician',
    units: [{ bu_id: 'p04', name: 'Plant 04' }],
    invited_by_name: 'R. Kowalski',
    created_at: '2026-10-05T06:00:00Z',
    expires_at: '2026-10-06T06:00:00Z',
    status: 'pending',
  },
]

vi.mock('../../api/buAdmins', () => ({
  useBuAdmins: () => ({ data: [rk], isPending: false, isError: false }),
  useSetBuAdminUnits: () => ({ mutateAsync: setUnits, isPending: false }),
  useRemoveBuAdmin: () => ({ mutateAsync: removeAdmin, isPending: false }),
}))
vi.mock('../../api/businessUnits', () => ({ useBusinessUnits: () => ({ data: units }) }))
vi.mock('../../api/invites', () => ({
  useInvites: () => ({ data: invites }),
  useCreateInvite: () => ({ mutateAsync: createInvite, isPending: false }),
  useResendInvite: () => ({ mutateAsync: vi.fn(), isPending: false }),
  useCancelInvite: () => ({ mutateAsync: vi.fn(), isPending: false }),
}))

const dialog = () => within(screen.getByRole('dialog'))

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(new Date('2026-10-05T12:00:00Z'))
  for (const fn of [setUnits, removeAdmin, createInvite]) fn.mockReset()
  render(<BuAdminsPage />)
})
afterEach(() => vi.useRealTimers())

describe('BuAdminsPage', () => {
  it('GIVEN BU Admins and invites THEN lists admins with units and only BU Admin invites', () => {
    const admins = within(screen.getByRole('table', { name: 'BU Admins' }))
    expect(admins.getByText('R. Kowalski')).toBeInTheDocument()
    expect(admins.getByText('Plant 05')).toBeInTheDocument()

    const pending = within(screen.getByRole('table', { name: 'Pending BU Admin invites' }))
    expect(pending.getByText('m.lopez@ppg.com')).toBeInTheDocument()
    expect(pending.getByText('Pending · 18 h left')).toBeInTheDocument()
    expect(pending.queryByText('tech@ppg.com')).not.toBeInTheDocument()
  })

  it('GIVEN the invite dialog THEN units already run are disabled and a vacant unit can be invited into', async () => {
    createInvite.mockResolvedValue({})
    fireEvent.click(screen.getByRole('button', { name: '+ Invite BU Admin' }))

    expect(dialog().getByRole('checkbox', { name: /Plant 04/ })).toBeDisabled()
    fireEvent.change(dialog().getByLabelText('Work email'), { target: { value: 'p.rao@ppg.com' } })
    fireEvent.click(dialog().getByRole('checkbox', { name: /Plant 11/ }))
    fireEvent.click(dialog().getByRole('button', { name: 'Send invite' }))

    expect(await screen.findByText(/Invite sent to p\.rao@ppg\.com/)).toBeInTheDocument()
    expect(createInvite).toHaveBeenCalledWith({
      body: { role: 'bu_admin', email: 'p.rao@ppg.com', bu_ids: ['p11'] },
      idempotencyKey: expect.any(String),
    })
  })

  it('GIVEN Edit units WHEN a vacant unit is added THEN contract 1.16 gets the full list', async () => {
    setUnits.mockResolvedValue({})
    fireEvent.click(screen.getByRole('button', { name: 'Edit units of R. Kowalski' }))
    expect(
      dialog().getByText(/adding it cancels the pending invite to m\.lopez@ppg\.com/),
    ).toBeInTheDocument()
    fireEvent.click(dialog().getByRole('checkbox', { name: /Plant 11/ }))
    fireEvent.click(dialog().getByRole('button', { name: 'Save changes' }))

    await waitFor(() =>
      expect(setUnits).toHaveBeenCalledWith({ userId: 'rk', buIds: ['p04', 'p05', 'p11'] }),
    )
  })

  it('GIVEN Edit units WHEN every unit is unticked THEN it asks to use Remove instead', async () => {
    fireEvent.click(screen.getByRole('button', { name: 'Edit units of R. Kowalski' }))
    fireEvent.click(dialog().getByRole('checkbox', { name: /Plant 04/ }))
    fireEvent.click(dialog().getByRole('checkbox', { name: /Plant 05/ }))
    fireEvent.click(dialog().getByRole('button', { name: 'Save changes' }))

    expect(await dialog().findByText(/To take every unit away, use Remove/)).toBeInTheDocument()
    expect(setUnits).not.toHaveBeenCalled()
  })

  it('GIVEN Remove for one unit with a replacement THEN contract 1.17 gets that unit and the email', async () => {
    removeAdmin.mockResolvedValue(undefined)
    fireEvent.click(screen.getByRole('button', { name: 'Remove R. Kowalski' }))
    expect(dialog().getByRole('button', { name: 'Remove from all units' })).toBeInTheDocument()

    fireEvent.click(dialog().getByRole('checkbox', { name: /Plant 05/ }))
    expect(dialog().getByText(/stays BU Admin for/)).toBeInTheDocument()
    fireEvent.click(dialog().getByLabelText(/Invite a new BU Admin now/))
    fireEvent.change(dialog().getByLabelText('Email'), { target: { value: 'p.rao@ppg.com' } })
    fireEvent.click(dialog().getByRole('button', { name: 'Remove from Plant 04' }))

    expect(await screen.findByText('R. Kowalski was removed from Plant 04.')).toBeInTheDocument()
    expect(removeAdmin).toHaveBeenCalledWith({
      userId: 'rk',
      buIds: ['p04'],
      replacementEmail: 'p.rao@ppg.com',
    })
  })
})
