import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '../../api/client'
import type { Escalation } from '../../api/escalations'
import { groupByUnit, whyText } from './escalationRules'
import { EscalationsPage } from './EscalationsPage'

const remind = vi.fn()
const createBatch = vi.fn()
let items: Escalation[] = []

vi.mock('../../api/escalations', () => ({
  useEscalations: () => ({ items, isPending: false, isError: false, hasNextPage: false }),
  useRemindBuAdmin: () => ({ mutate: remind }),
}))
vi.mock('../../api/businessUnits', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useBusinessUnits: () => ({
    data: [
      {
        bu_id: 'p04',
        name: 'Plant 04',
        bu_admin: { user_id: 'rk', full_name: 'R. Kowalski' },
        escalated_count: 2,
      },
      { bu_id: 'p11', name: 'Plant 11', bu_admin: null, escalated_count: 1 },
    ],
  }),
}))
vi.mock('../../api/invites', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useInvites: () => ({ data: [], isPending: false, isError: false }),
  useCreateInvite: () => ({ mutateAsync: vi.fn() }),
}))
vi.mock('../../api/review', () => ({
  useCreateBatch: () => ({ mutateAsync: createBatch }),
  useDelegates: () => ({
    data: [
      { user_id: 'tn', full_name: 'T. Nguyen', open_review_count: 0, own_scans_in_selection: 0 },
    ],
    isPending: false,
  }),
}))

const esc = (
  id: string,
  bu: string,
  at: string,
  reason: Escalation['reason'] = 'not_approved_24h',
) => ({
  escalation_id: `e-${id}`,
  scan_id: id,
  record_no: `REC-${id}`,
  bu_id: bu,
  bu_name: bu === 'p04' ? 'Plant 04' : 'Plant 11',
  equipment_type_name: 'Control Valve',
  captured_by_name: 'J. Martinez',
  reason,
  escalated_at: at,
  reminded_at: null,
  batch_no: null,
})

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(new Date('2026-10-05T12:00:00Z'))
  remind.mockReset()
  createBatch.mockReset().mockResolvedValue({ batch_no: 'B-20' })
  items = [
    esc('1', 'p04', '2026-09-26T12:00:00Z'),
    esc('2', 'p04', '2026-10-02T12:00:00Z'),
    esc('3', 'p11', '2026-10-02T12:00:00Z', 'no_bu_admin'),
  ]
})
afterEach(() => vi.useRealTimers())

const page = () =>
  render(
    <MemoryRouter>
      <EscalationsPage />
    </MemoryRouter>,
  )

describe('escalation rules', () => {
  it('groups by unit, biggest first, oldest scan first', () => {
    const groups = groupByUnit(items)
    expect(groups.map((g) => g.buId)).toEqual(['p04', 'p11'])
    expect(groups[0]?.oldest).toBe('2026-09-26T12:00:00Z')
    expect(groups[1]?.noBuAdmin).toBe(true)
  })

  it('explains why a scan is with the EA', () => {
    expect(whyText('not_approved_24h', 'S. Alvi')).toBe('Over 24 h with S. Alvi')
    expect(whyText('no_bu_admin')).toBe('No BU Admin')
  })
})

describe('Escalated scans (contracts 3.16, 3.17)', () => {
  it('GIVEN escalations THEN one card per unit with oldest wait and why', () => {
    page()
    const p04 = within(screen.getByRole('region', { name: 'Plant 04' }))
    expect(p04.getByText('2 scans')).toBeInTheDocument()
    expect(p04.getByText('9 days')).toBeInTheDocument()
    expect(p04.getByText('Over 24 h with R. Kowalski')).toBeInTheDocument()
    const p11 = within(screen.getByRole('region', { name: 'Plant 11' }))
    expect(p11.getByRole('button', { name: 'Assign BU Admin' })).toBeInTheDocument()
    expect(screen.getByRole('tab', { name: /All units/ })).toHaveTextContent('· 3')
  })

  it('GIVEN Assign BU Admin THEN the invite dialog opens with that unit ticked (canvas)', () => {
    page()
    const p11 = within(screen.getByRole('region', { name: 'Plant 11' }))
    fireEvent.click(p11.getByRole('button', { name: 'Assign BU Admin' }))
    const dialog = within(screen.getByRole('dialog'))
    expect(dialog.getByRole('checkbox', { name: /Plant 11/ })).toBeChecked()
    expect(dialog.getByRole('checkbox', { name: /Plant 04/ })).toBeDisabled()
  })

  it('GIVEN Remind THEN the BU Admin is reminded and the page says so', () => {
    remind.mockImplementation((_buId, opts: { onSuccess: () => void }) => opts.onSuccess())
    page()
    fireEvent.click(screen.getByRole('button', { name: 'Remind R. Kowalski' }))
    expect(remind).toHaveBeenCalledWith('p04', expect.anything())
    expect(
      screen.getByText('Reminder sent to R. Kowalski by email and on the dashboard.'),
    ).toBeInTheDocument()
  })

  it('GIVEN the unit has no BU Admin anymore THEN says so (409 no-bu-admin)', () => {
    remind.mockImplementation((_buId, opts: { onError: (e: unknown) => void }) =>
      opts.onError(new ApiError({ type: '/problems/no-bu-admin', title: 'Conflict', status: 409 })),
    )
    page()
    fireEvent.click(screen.getByRole('button', { name: 'Remind R. Kowalski' }))
    expect(screen.getByText(/has no BU Admin to remind/)).toBeInTheDocument()
  })

  it('GIVEN a unit opened WHEN scans are picked and delegated THEN one batch is created', async () => {
    page()
    fireEvent.click(screen.getByRole('tab', { name: /Plant 04/ }))
    const table = within(screen.getByRole('table', { name: 'Escalated scans in Plant 04' }))
    expect(table.getByRole('link', { name: /Control Valve\s*REC-1/ })).toHaveAttribute(
      'href',
      '/escalations/1',
    )
    expect(table.getAllByText('J. Martinez')).toHaveLength(2)
    fireEvent.click(screen.getByRole('checkbox', { name: 'Select REC-1' }))
    fireEvent.click(
      within(screen.getByText('1 selected').parentElement as HTMLElement).getByRole('button', {
        name: 'Delegate to technicians',
      }),
    )
    const dialog = within(screen.getByRole('dialog'))
    fireEvent.click(dialog.getByLabelText(/T\. Nguyen/))
    fireEvent.click(dialog.getByRole('button', { name: 'Delegate 1 scan to T. Nguyen' }))
    expect(await screen.findByText('Batch B-20 delegated to T. Nguyen.')).toBeInTheDocument()
    expect(screen.queryByText('1 selected')).not.toBeInTheDocument()
    await waitFor(() =>
      expect(createBatch).toHaveBeenCalledWith({
        assignedTo: 'tn',
        scanIds: ['1'],
        idempotencyKey: expect.any(String),
      }),
    )
  })

  it('GIVEN every scan of a unit is already in a batch THEN no empty delegate dialog opens', () => {
    items = items.map((e) => ({ ...e, batch_no: 'B-1' }))
    page()
    const p04 = within(screen.getByRole('region', { name: 'Plant 04' }))
    fireEvent.click(p04.getByRole('button', { name: 'Delegate to technicians' }))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(
      screen.getByText('Every escalated scan in Plant 04 is already in a batch.'),
    ).toBeInTheDocument()
  })
})
