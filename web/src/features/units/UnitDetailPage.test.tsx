import { fireEvent, render, screen, within } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router'
import { describe, expect, it, vi } from 'vitest'
import { UnitDetailPage } from './UnitDetailPage'

vi.mock('../../api/businessUnits', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useBusinessUnits: () => ({
    isPending: false,
    data: [
      {
        bu_id: 'p04',
        name: 'PPG Plant 04 — Coatings',
        facility_name: 'Cleveland',
        bu_admin: { user_id: 'rk', full_name: 'R. Kowalski' },
        waiting_count: 23,
        escalated_count: 9,
        delegated_count: 60,
        locations_status: 'published',
      },
      {
        bu_id: 'p12',
        name: 'PPG Plant 12 — Adhesives',
        facility_name: 'Atlanta',
        bu_admin: null,
        locations_status: 'published',
      },
    ],
  }),
}))
vi.mock('../../api/invites', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useInvites: () => ({ data: [], isPending: false, isError: false }),
  useCreateInvite: () => ({ mutateAsync: vi.fn() }),
}))
vi.mock('../../api/buAdmins', () => ({
  useSetBuAdminUnits: () => ({ mutateAsync: vi.fn() }),
  useRemoveBuAdmin: () => ({ mutateAsync: vi.fn() }),
  useBuAdmins: () => ({
    data: [
      {
        user_id: 'rk',
        full_name: 'R. Kowalski',
        email: 'r.kowalski@ppg.com',
        status: 'active',
        units: [
          { bu_id: 'p04', name: 'Plant 04' },
          { bu_id: 'p05', name: 'Plant 05' },
        ],
      },
    ],
  }),
}))
vi.mock('../../api/escalations', () => ({
  useEscalations: () => ({
    items: [
      {
        escalation_id: 'e1',
        scan_id: 's1',
        record_no: 'REC-90098',
        bu_id: 'p04',
        bu_name: 'Plant 04',
        equipment_type_name: 'Flowserve Pump Nameplate',
        captured_by_name: 'J. Martinez',
        reason: 'not_approved_24h',
        escalated_at: '2026-09-26T12:00:00Z',
        reminded_at: null,
        batch_no: null,
      },
    ],
  }),
}))
vi.mock('../../api/auditLog', () => ({ useAuditLog: () => ({ items: [], isPending: false }) }))

const page = (path: string) =>
  render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/overview/units/:buId" element={<UnitDetailPage />} />
      </Routes>
    </MemoryRouter>,
  )

describe('EA unit page (canvas EA 25)', () => {
  it('GIVEN a unit THEN shows its BU Admin, numbers and links filtered to the unit', () => {
    page('/overview/units/p04')
    expect(screen.getByRole('heading', { name: 'PPG Plant 04 — Coatings' })).toBeInTheDocument()
    expect(screen.getByText('r.kowalski@ppg.com · also runs Plant 05')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /9\s*over 24 h/ })).toHaveAttribute(
      'href',
      '/escalations?unit=p04',
    )
    expect(screen.getByText('J. Martinez')).toBeInTheDocument()
    expect(
      screen.getByRole('link', { name: /Flowserve Pump Nameplate\s*REC-90098/ }),
    ).toHaveAttribute('href', '/escalations/s1')
    expect(screen.getByRole('link', { name: /Audit log/ })).toHaveAttribute(
      'href',
      '/audit-log?unit=p04',
    )
    expect(
      within(screen.getByRole('table', { name: 'Recent activity' })).getByText(
        'No admin actions in the last 7 days.',
      ),
    ).toBeInTheDocument()
  })

  it('GIVEN an unknown unit THEN says so', () => {
    page('/overview/units/nope')
    expect(screen.getByText(/doesn't exist or was removed/)).toBeInTheDocument()
  })
})

describe('EA unit page: BU Admin card (canvas EA 25)', () => {
  it('GIVEN a BU Admin THEN Edit units and Remove open their dialogs on this page', () => {
    page('/overview/units/p04')
    expect(screen.queryByRole('link', { name: 'Manage' })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Edit units' }))
    expect(screen.getByRole('dialog')).toHaveTextContent('R. Kowalski')
    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: /Cancel/ }))
    fireEvent.click(screen.getByRole('button', { name: 'Remove' }))
    expect(screen.getByRole('dialog')).toBeInTheDocument()
  })
  it('GIVEN no BU Admin THEN Assign BU Admin opens the invite with this unit ticked', () => {
    page('/overview/units/p12')
    expect(screen.queryByRole('link', { name: 'Manage' })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Assign BU Admin' }))
    const dialog = within(screen.getByRole('dialog'))
    expect(dialog.getByRole('checkbox', { name: /Plant 12/ })).toBeChecked()
    expect(dialog.getByRole('checkbox', { name: /Plant 04/ })).toBeDisabled()
  })
})
