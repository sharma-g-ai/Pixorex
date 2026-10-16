import { render, screen, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import { describe, expect, it, vi } from 'vitest'
import type { BusinessUnit } from '../../api/businessUnits'
import { useBusinessUnits } from '../../api/businessUnits'
import { DashboardContext } from '../../app/DashboardContext'
import { UnitsOverviewPage } from './UnitsOverviewPage'

vi.mock('../../api/businessUnits', () => ({ useBusinessUnits: vi.fn() }))

const rk = { user_id: 'rk', full_name: 'R. Kowalski' }
const units: BusinessUnit[] = [
  {
    bu_id: 'p04',
    name: 'PPG Plant 04 — Coatings',
    facility_name: 'Plant 04',
    bu_admin: rk,
    waiting_count: 23,
    escalated_count: 9,
    locations_status: 'published',
  },
  {
    bu_id: 'p05',
    name: 'PPG Plant 05 — Powder Coatings',
    facility_name: 'Plant 05',
    bu_admin: rk,
    waiting_count: 6,
    locations_status: 'published',
  },
  {
    bu_id: 'p11',
    name: 'PPG Plant 11 — Resins',
    facility_name: 'Plant 11',
    bu_admin: null,
    waiting_count: 9,
    escalated_count: 3,
    locations_status: 'published',
  },
]

function renderPage(data: BusinessUnit[] | undefined) {
  vi.mocked(useBusinessUnits).mockReturnValue({ data, isPending: !data, isError: false } as never)
  const dashboard = {
    role: 'enterprise_admin' as const,
    unit: null,
    me: { tenant_name: 'PPG Industries' } as never,
  }
  return render(
    <MemoryRouter>
      <DashboardContext.Provider value={dashboard}>
        <UnitsOverviewPage />
      </DashboardContext.Provider>
    </MemoryRouter>,
  )
}

describe('UnitsOverviewPage', () => {
  it('GIVEN three units THEN shows a card per unit and the company line', () => {
    renderPage(units)
    expect(screen.getByText('PPG Industries · 3 business units')).toBeInTheDocument()
    expect(screen.getAllByRole('article')).toHaveLength(3)
  })

  it('GIVEN a BU Admin running two units THEN each card says which other unit they run', () => {
    renderPage(units)
    const plant04 = within(screen.getByRole('article', { name: 'PPG Plant 04 — Coatings' }))
    expect(plant04.getByText('R. Kowalski')).toBeInTheDocument()
    expect(plant04.getByText('Also runs PPG Plant 05 — Powder Coatings')).toBeInTheDocument()
  })

  it('GIVEN a unit without a BU Admin THEN its card says so', () => {
    renderPage(units)
    const plant11 = within(screen.getByRole('article', { name: 'PPG Plant 11 — Resins' }))
    expect(plant11.getByText('No BU Admin.')).toBeInTheDocument()
  })

  it('GIVEN escalations and a vacant unit THEN Needs you shows the totals', () => {
    renderPage(units)
    const scans = within(screen.getByRole('region', { name: 'Scans waiting over 24 hours' }))
    expect(scans.getByText('12')).toBeInTheDocument()
    const vacant = within(screen.getByRole('region', { name: 'Units without a BU Admin' }))
    expect(vacant.getByText('1')).toBeInTheDocument()
  })

  it('GIVEN no units THEN invites the EA to create the first one', () => {
    renderPage([])
    expect(screen.getByRole('heading', { name: 'No business units yet' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: '+ Create unit' })).toHaveAttribute(
      'href',
      '/overview/new-unit',
    )
  })
})
