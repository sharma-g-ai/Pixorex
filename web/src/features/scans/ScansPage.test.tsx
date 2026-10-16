import { fireEvent, render, screen, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { reviewedByText, scanStatus, statusQuery } from './scanStatus'
import { ScansPage } from './ScansPage'

const useAllScans = vi.fn()
vi.mock('../../api/scans', () => ({ useAllScans: (f: unknown) => useAllScans(f) }))
vi.mock('../../api/businessUnits', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useBusinessUnits: () => ({ data: [{ bu_id: 'p04', name: 'Plant 04' }] }),
}))

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(new Date('2026-10-05T12:00:00Z'))
  useAllScans.mockReset().mockReturnValue({
    isPending: false,
    isError: false,
    hasNextPage: false,
    items: [
      {
        scan_id: 's1',
        record_no: 'REC-90141',
        bu_name: 'Plant 04',
        equipment_type_name: 'Control Valve V-071',
        captured_by_name: 'J. Martinez',
        location_path: 'Bldg C › Bin 05',
        review_status: 'waiting_for_approval',
        captured_at: '2026-10-03T12:00:00Z',
        reviewed_by: null,
        assignment: null,
        escalation_reason: 'not_approved_24h',
      },
    ],
  })
})
afterEach(() => vi.useRealTimers())

const page = () =>
  render(
    <MemoryRouter>
      <ScansPage />
    </MemoryRouter>,
  )

describe('scan status', () => {
  it('maps statuses and filters to contract values', () => {
    const row = { review_status: 'waiting_for_approval', reviewed_by: null, assignment: null }
    expect(scanStatus(row)).toEqual({ label: 'Waiting review', tone: 'warning' })
    expect(statusQuery('waiting')).toEqual({ review_status: 'waiting_for_approval' })
    expect(statusQuery('delegated')).toEqual({ delegated: true })
    expect(statusQuery('any')).toEqual({})
  })
})

describe('Scans (contract 3.18)', () => {
  it('GIVEN scans THEN lists them, last 30 days by default', () => {
    page()
    const table = within(screen.getByRole('table', { name: 'Scans' }))
    expect(table.getByRole('link', { name: /Control Valve V-071/ })).toHaveAttribute(
      'href',
      '/scans/s1',
    )
    expect(table.getByText('Waiting review')).toBeInTheDocument()
    expect(useAllScans).toHaveBeenLastCalledWith({ from: '2026-09-06', to: '2026-10-05' })
  })

  it('GIVEN unit and status picked THEN the query filters by both', () => {
    page()
    fireEvent.click(screen.getByRole('tab', { name: 'Plant 04' }))
    fireEvent.change(screen.getByLabelText('Status'), { target: { value: 'delegated' } })
    expect(useAllScans).toHaveBeenLastCalledWith({
      bu_id: 'p04',
      delegated: true,
      from: '2026-09-06',
      to: '2026-10-05',
    })
  })
})

describe('scan rows (contract 3.18 v0.3.1)', () => {
  const none = { reviewed_by: null, assignment: null, escalation_reason: null }
  const batch = { batch_no: 'B-15', assigned_to_name: 'A. Patel' }

  it('shows an overridden decision as "first → overrider"', () => {
    const reviewed_by = { name: 'R. Kowalski', overrode_name: 'T. Nguyen' }
    expect(reviewedByText({ ...none, reviewed_by })).toBe('T. Nguyen → R. Kowalski')
    expect(scanStatus({ review_status: 'rejected', reviewed_by, assignment: null })).toEqual({
      label: 'Rejected · overridden',
      tone: 'danger',
    })
  })

  it('shows a delegated scan with its technician and batch', () => {
    expect(reviewedByText({ ...none, assignment: batch })).toBe('A. Patel · B-15')
    expect(
      scanStatus({ review_status: 'waiting_for_approval', reviewed_by: null, assignment: batch }),
    ).toEqual({ label: 'Delegated', tone: 'neutral' })
  })

  it('says why an undecided scan is with the EA', () => {
    expect(reviewedByText({ ...none, escalation_reason: 'not_approved_24h' })).toBe(
      'escalated to you',
    )
    expect(reviewedByText({ ...none, escalation_reason: 'no_bu_admin' })).toBe('no BU Admin')
    expect(reviewedByText(none)).toBe('—')
  })

  it('GIVEN a search WHEN Enter is pressed THEN q is sent; clearing it removes q', () => {
    page()
    expect(
      within(screen.getByRole('table', { name: 'Scans' })).getByText('escalated to you'),
    ).toBeInTheDocument()
    const box = screen.getByLabelText('Search scans')
    fireEvent.change(box, { target: { value: ' 98274 ' } })
    expect(useAllScans).not.toHaveBeenLastCalledWith(expect.objectContaining({ q: '98274' }))
    fireEvent.submit(screen.getByRole('search'))
    expect(useAllScans).toHaveBeenLastCalledWith(expect.objectContaining({ q: '98274' }))
    fireEvent.change(box, { target: { value: '' } })
    expect(useAllScans).toHaveBeenLastCalledWith({ from: '2026-09-06', to: '2026-10-05' })
  })
})
