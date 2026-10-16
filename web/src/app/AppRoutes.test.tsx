import { fireEvent, render, screen, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { Me, UnitRole } from '../api/me'
import { useMe } from '../api/me'
import { AppRoutes } from './AppRoutes'

const mutate = vi.fn()

vi.mock('../api/me', () => ({
  useMe: vi.fn(),
  useSwitchUnit: () => ({ mutate, isPending: false }),
}))
vi.mock('../api/review', () => ({
  useReviewQueue: () => ({ data: undefined, isPending: true }),
  useBatches: () => ({ data: [] }),
  useTechnicianDecisions: () => ({ data: [], isPending: false }),
}))
vi.mock('../api/invites', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useInvites: () => ({ data: [] }),
}))
vi.mock('../api/notifications', () => ({
  useNotifications: () => ({ data: { items: [], unread_count: 2 }, isPending: false }),
  useMarkNotificationRead: () => ({ mutate: vi.fn() }),
  useMarkAllNotificationsRead: () => ({ mutate: vi.fn(), isPending: false }),
}))
vi.mock('../api/businessUnits', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useBusinessUnits: () => ({
    data: ['p04', 'p05', 'p07'].map((id) => ({
      bu_id: id,
      name: id,
      facility_name: id,
      bu_admin: null,
      locations_status: 'published',
    })),
  }),
}))

const unit = (over: Partial<UnitRole>): UnitRole => ({
  bu_id: 'p04',
  name: 'PPG Plant 04 — Coatings',
  role: 'bu_admin',
  is_primary: false,
  ...over,
})

const me = (units: UnitRole[], active_bu_id: string | null = null): Me => ({
  user_id: 'u-1',
  full_name: 'R. Kowalski',
  email: 'rk@ppg.test',
  status: 'active',
  tenant_name: 'PPG Industries',
  units,
  active_bu_id,
  last_bu_id: null,
})

function signedInAs(value: Me) {
  vi.mocked(useMe).mockReturnValue({ isPending: false, isError: false, data: value } as never)
}

function renderAt(path: string) {
  return render(
    <QueryClientProvider client={new QueryClient()}>
      <MemoryRouter initialEntries={[path]}>
        <AppRoutes />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

const menu = () => within(screen.getByRole('navigation', { name: 'Main' }))

beforeEach(() => mutate.mockReset())

describe('Enterprise Admin', () => {
  it('GIVEN an EA WHEN they open the app THEN they land on Overview with the EA menu and company card', () => {
    signedInAs(me([unit({ role: 'enterprise_admin', bu_id: null, name: null })]))
    renderAt('/')

    expect(screen.getByRole('heading', { name: 'Overview' })).toBeInTheDocument()
    for (const label of [
      'Overview',
      'BU Admins',
      'Locations',
      'Scans',
      'Escalated scans',
      'Audit log',
    ]) {
      expect(menu().getByRole('link', { name: label })).toBeInTheDocument()
    }
    expect(menu().queryByRole('link', { name: 'Technicians' })).not.toBeInTheDocument()
    expect(screen.getByText('Company')).toBeInTheDocument()
    expect(screen.getByText('3 units')).toBeInTheDocument()
    expect(screen.getByText('Enterprise Admin')).toBeInTheDocument()
  })
})

describe('BU Admin', () => {
  const p04 = unit({})
  const p05 = unit({ bu_id: 'p05', name: 'PPG Plant 05 — Powder Coatings' })

  it('GIVEN a BU Admin WHEN they open the app THEN they land on Home with the BU menu and current unit', () => {
    signedInAs(me([p04, p05], 'p04'))
    renderAt('/')

    expect(
      screen.getByRole('heading', { name: /^Good (morning|afternoon|evening), R\.$/ }),
    ).toBeInTheDocument()
    for (const label of [
      'Home',
      'Review queue',
      'Delegations',
      'Equipment types',
      'Technicians',
      'Audit log',
    ]) {
      expect(menu().getByRole('link', { name: label })).toBeInTheDocument()
    }
    expect(menu().queryByRole('link', { name: 'Escalated scans' })).not.toBeInTheDocument()
    expect(screen.getByText('Business unit · 2')).toBeInTheDocument()
  })

  it('GIVEN a BU Admin WHEN they open an EA page THEN they are sent to their Home', () => {
    signedInAs(me([p04], 'p04'))
    renderAt('/escalations')
    expect(
      screen.getByRole('heading', { name: /^Good (morning|afternoon|evening), R\.$/ }),
    ).toBeInTheDocument()
  })

  it('GIVEN two units WHEN they pick the other one THEN the switch is saved for that unit', () => {
    signedInAs(me([p04, p05], 'p04'))
    renderAt('/home')

    fireEvent.click(screen.getByRole('button', { name: /switch business unit/i }))
    fireEvent.click(screen.getByRole('menuitemradio', { name: /Plant 05/ }))

    expect(mutate).toHaveBeenCalledWith('p05')
  })

  it('GIVEN two units WHEN they pick the current one THEN nothing is saved', () => {
    signedInAs(me([p04, p05], 'p04'))
    renderAt('/home')

    fireEvent.click(screen.getByRole('button', { name: /switch business unit/i }))
    fireEvent.click(screen.getByRole('menuitemradio', { name: /Plant 04/ }))

    expect(mutate).not.toHaveBeenCalled()
  })
})

describe('No access', () => {
  it('GIVEN only technician roles WHEN they open the app THEN they get no dashboard', () => {
    signedInAs(me([unit({ role: 'field_technician' })]))
    renderAt('/home')
    expect(screen.getByRole('heading', { name: 'No dashboard access' })).toBeInTheDocument()
    expect(screen.queryByRole('navigation', { name: 'Main' })).not.toBeInTheDocument()
  })

  it('GIVEN /me fails WHEN the app loads THEN an error is shown', () => {
    vi.mocked(useMe).mockReturnValue({
      isPending: false,
      isError: true,
      error: new Error('x'),
    } as never)
    renderAt('/')
    expect(
      screen.getByRole('heading', { name: "We couldn't load your account" }),
    ).toBeInTheDocument()
  })
})
