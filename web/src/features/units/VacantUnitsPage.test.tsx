import { fireEvent, render, screen, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { BusinessUnit } from '../../api/businessUnits'
import type { Invite } from '../../api/invites'
import { vacantUnits } from './vacantUnits'
import { VacantUnitsPage } from './VacantUnitsPage'

const resend = vi.fn()
const unit = (id: string, admin: string | null, waiting: number) =>
  ({
    bu_id: id,
    name: `Plant ${id}`,
    facility_name: `Site ${id}`,
    bu_admin: admin ? { user_id: admin, full_name: admin } : null,
    waiting_count: waiting,
    escalated_count: 2,
    locations_status: 'published',
  }) as BusinessUnit
const invite = (
  id: string,
  bu: string,
  status: Invite['status'],
  created: string,
  expires: string,
) =>
  ({
    invite_id: id,
    email: `${id}@ppg.com`,
    role: 'bu_admin',
    units: [{ bu_id: bu, name: `Plant ${bu}` }],
    invited_by_name: 'A. Mehta',
    created_at: created,
    expires_at: expires,
    status,
  }) as Invite

let units: BusinessUnit[]
let invites: Invite[]
vi.mock('../../api/businessUnits', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useBusinessUnits: () => ({ data: units, isPending: false, isError: false }),
}))
vi.mock('../../api/invites', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useInvites: () => ({ data: invites, isPending: false, isError: false }),
  useResendInvite: () => ({ mutateAsync: resend, isPending: false }),
  useCancelInvite: () => ({ mutateAsync: vi.fn(), isPending: false }),
  useCreateInvite: () => ({ mutateAsync: vi.fn() }),
}))

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(new Date('2026-10-05T12:00:00Z'))
  resend.mockReset().mockResolvedValue({})
  units = [unit('04', 'rk', 23), unit('11', null, 9), unit('12', null, 30)]
  invites = [
    invite('old', '11', 'expired', '2026-10-01T09:00:00Z', '2026-10-02T09:00:00Z'),
    invite('new', '11', 'pending', '2026-10-05T06:00:00Z', '2026-10-06T06:00:00Z'),
  ]
})
afterEach(() => vi.useRealTimers())

describe('vacant units', () => {
  it('lists only units without a BU Admin, most waiting first, with the latest invite', () => {
    const rows = vacantUnits(units, invites)
    expect(rows.map((r) => r.unit.bu_id)).toEqual(['12', '11'])
    expect(rows[1]?.invite?.invite_id).toBe('new')
    expect(rows[0]?.invite).toBeNull()
  })
})

describe('Units without a BU Admin (EA "Needs you")', () => {
  const page = () =>
    render(
      <MemoryRouter>
        <VacantUnitsPage />
      </MemoryRouter>,
    )

  it('GIVEN a pending invite THEN shows its status and can resend it', async () => {
    page()
    const card = within(screen.getByRole('region', { name: 'Plant 11' }))
    expect(card.getByText('new@ppg.com')).toBeInTheDocument()
    expect(card.getByText('Pending · 18 h left')).toBeInTheDocument()
    fireEvent.click(card.getByRole('button', { name: 'Resend invite' }))
    expect(resend).toHaveBeenCalledWith('new')
    expect(await screen.findByText('Invite sent again to new@ppg.com.')).toBeInTheDocument()
  })

  it('GIVEN Invite someone else THEN the invite dialog opens with the unit ticked', () => {
    page()
    const card = within(screen.getByRole('region', { name: 'Plant 12' }))
    expect(card.queryByRole('button', { name: 'Resend invite' })).not.toBeInTheDocument()
    fireEvent.click(card.getByRole('button', { name: 'Invite someone else' }))
    const dialog = within(screen.getByRole('dialog'))
    expect(dialog.getByRole('checkbox', { name: /Plant 12/ })).toBeChecked()
    expect(dialog.getByRole('checkbox', { name: /Plant 04/ })).toBeDisabled()
  })

  it('GIVEN every unit has a BU Admin THEN says so', () => {
    units = [unit('04', 'rk', 1)]
    page()
    expect(screen.getByText('Every unit has a BU Admin.')).toBeInTheDocument()
  })
})
