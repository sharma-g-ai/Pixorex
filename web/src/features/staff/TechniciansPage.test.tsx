import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Invite } from '../../api/invites'
import type { Me } from '../../api/me'
import type { Technician } from '../../api/technicians'
import { DashboardContext } from '../../app/DashboardContext'
import { dateTime } from '../../lib/time'
import { TechniciansPage } from './TechniciansPage'

const remove = vi.fn()
const createInvite = vi.fn()
const resend = vi.fn()
const cancel = vi.fn()
let technicians: Technician[] = []
let invites: Invite[] = []

vi.mock('../../api/technicians', () => ({
  useTechnicians: () => ({ data: technicians, isPending: false, isError: false }),
  useRemoveTechnician: () => ({ mutateAsync: remove, isPending: false }),
}))
vi.mock('../../api/invites', () => ({
  useInvites: () => ({ data: invites }),
  useCreateInvite: () => ({ mutateAsync: createInvite, isPending: false }),
  useResendInvite: () => ({ mutateAsync: resend, isPending: false }),
  useCancelInvite: () => ({ mutateAsync: cancel, isPending: false }),
}))

const tech = (over: Partial<Technician>): Technician => ({
  user_id: 'jm',
  full_name: 'J. Martinez',
  email: 'j.martinez@ppg.test',
  status: 'active',
  sign_in_locked_until: null,
  units: [{ bu_id: 'p04', name: 'Plant 04' }],
  scans_this_month: 86,
  active_batch_no: 'B-13',
  last_active_at: '2026-10-05T11:46:00Z',
  ...over,
})

const invite = (over: Partial<Invite>): Invite => ({
  invite_id: 'inv-1',
  email: 'n.kim@ppg.com',
  role: 'field_technician',
  units: [],
  invited_by_name: 'R. Kowalski',
  created_at: '2026-10-05T10:00:00Z',
  expires_at: '2026-10-06T10:00:00Z',
  status: 'pending',
  ...over,
})

const p04 = { bu_id: 'p04', name: 'PPG Plant 04', role: 'bu_admin' as const, is_primary: true }
const p05 = { bu_id: 'p05', name: 'PPG Plant 05', role: 'bu_admin' as const, is_primary: false }

function renderPage() {
  const me = { tenant_name: 'PPG', units: [p04, p05], active_bu_id: 'p04' } as unknown as Me
  return render(
    <DashboardContext.Provider value={{ me, role: 'bu_admin', unit: p04 }}>
      <TechniciansPage />
    </DashboardContext.Provider>,
  )
}

const table = (name: string) => within(screen.getByRole('table', { name }))
const dialog = () => within(screen.getByRole('dialog'))

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(new Date('2026-10-05T12:00:00Z'))
  for (const fn of [remove, createInvite, resend, cancel]) fn.mockReset()
  technicians = [
    tech({}),
    tech({
      user_id: 'lb',
      full_name: 'L. Brooks',
      email: 'l.brooks@ppg.test',
      sign_in_locked_until: '2026-10-05T12:18:00Z',
      active_batch_no: null,
    }),
    tech({ user_id: 'ft', full_name: 'F. Tech', email: 'former.tech@ppg.com', status: 'removed' }),
  ]
  invites = [
    invite({}),
    invite({ invite_id: 'inv-2', email: 'd.ross@ppg.com', status: 'expired' }),
    invite({ invite_id: 'inv-3', email: 'done@ppg.com', status: 'accepted' }),
  ]
})
afterEach(() => vi.useRealTimers())

describe('TechniciansPage lists', () => {
  it('GIVEN technicians THEN active and locked ones show with their status', () => {
    renderPage()
    const techs = table('Technicians')
    expect(techs.getByText('J. Martinez')).toBeInTheDocument()
    expect(techs.getByText('Active')).toBeInTheDocument()
    expect(techs.getAllByText(dateTime('2026-10-05T11:46:00Z'))).toHaveLength(2)
    expect(techs.getByText('Sign-in locked · 18 min left')).toBeInTheDocument()
    expect(techs.getByText('Unlocks on its own')).toBeInTheDocument()
    expect(techs.queryByRole('button', { name: 'Remove L. Brooks' })).not.toBeInTheDocument()
    expect(techs.queryByText('F. Tech')).not.toBeInTheDocument()
  })

  it('GIVEN invites and a removed technician THEN the second table shows them; accepted invites are hidden', () => {
    renderPage()
    const rows = table('Invites and removed accounts')
    expect(rows.getByText('Pending · 22 h left')).toBeInTheDocument()
    expect(rows.getByText('Expired')).toBeInTheDocument()
    expect(
      rows.getByRole('button', { name: 'Remove invite to d.ross@ppg.com' }),
    ).toBeInTheDocument()
    expect(rows.getByRole('button', { name: 'Cancel invite to n.kim@ppg.com' })).toBeInTheDocument()
    expect(rows.getByText('Removed · needs new invite')).toBeInTheDocument()
    expect(rows.queryByText('done@ppg.com')).not.toBeInTheDocument()
  })
})

describe('TechniciansPage actions', () => {
  it('GIVEN the page THEN it has no subtitle, no card heading repeating the page title, and no side notes', () => {
    renderPage()
    expect(screen.getByRole('heading', { level: 1, name: 'Technicians' })).toBeInTheDocument()
    expect(screen.queryByText('PPG Plant 04', { selector: 'p' })).toBeNull() // the unit is in the sidebar
    expect(screen.queryByRole('heading', { name: 'Technicians', level: 2 })).toBeNull()
    expect(screen.queryByText(/Field technicians use the mobile app only/)).toBeNull()
    expect(screen.queryByText(/Invite links are valid 24 hours/)).toBeNull()
    // The second card keeps its heading.
    expect(
      screen.getByRole('heading', { name: 'Invites and removed accounts' }),
    ).toBeInTheDocument()
  })

  it('GIVEN a technician WHEN removed and confirmed THEN contract 1.19 is called, with no banner', async () => {
    remove.mockResolvedValue(undefined)
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Remove J. Martinez' }))

    expect(
      dialog().getByRole('heading', { name: 'Remove J. Martinez from PPG Plant 04?' }),
    ).toBeInTheDocument()
    expect(dialog().getByText(/Their delegated batch \(B-13\)/)).toBeInTheDocument()
    fireEvent.click(dialog().getByRole('button', { name: 'Remove technician' }))

    await waitFor(() => expect(remove).toHaveBeenCalledWith('jm'))
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull())
    // The technician moves to the removed accounts list, so no banner says so.
    expect(screen.queryByText(/was removed from/)).toBeNull()
  })

  it('GIVEN the invite dialog WHEN sent empty THEN asks for an email and sends nothing', async () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: '+ Invite technician' }))
    fireEvent.click(dialog().getByRole('button', { name: 'Send invite' }))

    expect(await dialog().findByText('Enter a valid work email.')).toBeInTheDocument()
    expect(createInvite).not.toHaveBeenCalled()
  })

  it('GIVEN an email and both units ticked WHEN sent THEN contract 1.8 gets a technician invite for both', async () => {
    createInvite.mockResolvedValue({})
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: '+ Invite technician' }))
    fireEvent.change(dialog().getByLabelText('Work email'), { target: { value: 'c.wu@ppg.com' } })
    fireEvent.click(dialog().getByLabelText(/PPG Plant 05/))
    fireEvent.click(dialog().getByRole('button', { name: 'Send invite' }))

    expect(await screen.findByText(/Invite sent to c\.wu@ppg\.com/)).toBeInTheDocument()
    expect(createInvite).toHaveBeenCalledWith({
      body: { role: 'field_technician', email: 'c.wu@ppg.com', bu_ids: ['p04', 'p05'] },
      idempotencyKey: expect.any(String),
    })
  })

  it('GIVEN a removed technician WHEN Send new invite THEN the dialog opens with their email', () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Send new invite' }))
    expect(dialog().getByLabelText('Work email')).toHaveValue('former.tech@ppg.com')
  })

  it('GIVEN a pending invite WHEN Resend THEN contract 1.10 is called for it', async () => {
    resend.mockResolvedValue({})
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Resend invite to n.kim@ppg.com' }))
    await waitFor(() => expect(resend).toHaveBeenCalledWith('inv-1'))
    expect(await screen.findByText('Invite sent again to n.kim@ppg.com.')).toBeInTheDocument()
  })

  it('GIVEN a pending invite WHEN cancelled THEN contract 1.11 is called and no banner is shown (it leaves the list)', async () => {
    cancel.mockResolvedValue({})
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Cancel invite to n.kim@ppg.com' }))
    await waitFor(() => expect(cancel).toHaveBeenCalledWith('inv-1'))
    await new Promise((resolve) => setTimeout(resolve, 0))
    expect(screen.queryByText('Invite to n.kim@ppg.com removed.')).toBeNull()
    expect(screen.queryByRole('status')).toBeNull()
  })

  it('GIVEN cancelling fails THEN the reason is shown', async () => {
    cancel.mockRejectedValue(new Error('boom'))
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Cancel invite to n.kim@ppg.com' }))
    expect(await screen.findByRole('alert')).toBeInTheDocument()
  })
})
