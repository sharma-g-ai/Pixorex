import { fireEvent, render, screen, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Me } from '../../api/me'
import { DashboardContext } from '../../app/DashboardContext'
import type { DashboardRole } from '../../app/access'
import { actorName } from './auditLabels'
import { AuditLogPage } from './AuditLogPage'

const useAuditLog = vi.fn()
vi.mock('../../api/auditLog', () => ({ useAuditLog: (f: unknown) => useAuditLog(f) }))
vi.mock('../../api/businessUnits', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useBusinessUnits: () => ({ data: [{ bu_id: 'p04', name: 'Plant 04' }] }),
}))

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(new Date('2026-10-05T12:00:00Z'))
  useAuditLog.mockReset().mockReturnValue({
    isPending: false,
    isError: false,
    hasNextPage: false,
    items: [
      {
        occurred_at: '2026-10-05T10:05:00Z',
        actor_type: 'user',
        actor_name: 'R. Kowalski',
        bu_name: 'Plant 04',
        category: 'override',
        summary: "Overrode T. Nguyen's approval of REC-90131 → Rejected",
        action: 'decision.overridden',
        object_type: 'decision',
      },
    ],
  })
})
afterEach(() => vi.useRealTimers())

function page(role: DashboardRole) {
  const unit =
    role === 'bu_admin' ? { bu_id: 'p04', name: 'Plant 04', role, is_primary: true } : null
  return render(
    <MemoryRouter>
      <DashboardContext.Provider value={{ me: {} as Me, role, unit }}>
        <AuditLogPage />
      </DashboardContext.Provider>
    </MemoryRouter>,
  )
}

describe('Audit log (contract 3.22)', () => {
  it('names system actions "System"', () => {
    expect(actorName({ actor_type: 'system', actor_name: null })).toBe('System')
  })

  it('GIVEN an EA THEN all units, last 7 days; filters narrow the query', () => {
    page('enterprise_admin')
    const table = within(screen.getByRole('table', { name: 'Audit log' }))
    expect(table.getByText('Override')).toBeInTheDocument()
    expect(
      table.getByText("Overrode T. Nguyen's approval of REC-90131 → Rejected"),
    ).toBeInTheDocument()
    expect(table.queryByText('decision.overridden')).not.toBeInTheDocument()
    expect(useAuditLog).toHaveBeenLastCalledWith({ from: '2026-09-29', to: '2026-10-05' })

    fireEvent.change(screen.getByLabelText('Unit'), { target: { value: 'p04' } })
    fireEvent.change(screen.getByLabelText('Type of action'), { target: { value: 'override' } })
    expect(useAuditLog).toHaveBeenLastCalledWith({
      bu_id: 'p04',
      category: 'override',
      from: '2026-09-29',
      to: '2026-10-05',
    })
    fireEvent.click(screen.getByRole('button', { name: 'Clear filters' }))
    expect(useAuditLog).toHaveBeenLastCalledWith({ from: '2026-09-29', to: '2026-10-05' })
  })

  it('GIVEN a BU Admin THEN only their current unit, no unit picker (D-06)', () => {
    page('bu_admin')
    expect(screen.queryByLabelText('Unit')).not.toBeInTheDocument()
    expect(useAuditLog).toHaveBeenLastCalledWith(expect.objectContaining({ bu_id: 'p04' }))
  })
})
