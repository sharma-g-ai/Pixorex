import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '../../api/client'
import type { Me } from '../../api/me'
import type { Assignment, Batch } from '../../api/review'
import { DashboardContext } from '../../app/DashboardContext'
import { dateTime } from '../../lib/time'
import { pickTechnician } from '../../test/pickTechnician'
import { BatchPage } from './BatchPage'

const calls = { remind: vi.fn(), reassign: vi.fn(), takeBack: vi.fn() }
let detail: { batch: Batch; assignments: Assignment[] } | undefined
let state: { isPending: boolean; isError: boolean } = { isPending: false, isError: false }

const mutation = (fn: ReturnType<typeof vi.fn>) => ({ mutateAsync: fn, isPending: false })
vi.mock('../../api/review', () => ({
  useBatch: () => ({ data: detail, ...state }),
  useRemindBatch: () => mutation(calls.remind),
  useReassignBatch: () => mutation(calls.reassign),
  useTakeBackBatch: () => mutation(calls.takeBack),
  useDelegates: () => ({
    data: [
      { user_id: 'tn', full_name: 'T. Nguyen', open_review_count: 3, own_scans_in_selection: 0 },
    ],
    isPending: false,
  }),
}))

const unit = { bu_id: 'p04', name: 'Plant 04', role: 'bu_admin' as const, is_primary: true }
const me = { full_name: 'Priya Nair' } as Me
function page() {
  return render(
    <MemoryRouter initialEntries={['/delegations/b12']}>
      <DashboardContext.Provider value={{ me, role: 'bu_admin', unit }}>
        <Routes>
          <Route path="/delegations/:batchId" element={<BatchPage />} />
        </Routes>
      </DashboardContext.Provider>
    </MemoryRouter>,
  )
}

const batch = (over: Partial<Batch> = {}): Batch => ({
  batch_id: 'b12',
  batch_no: 'B-12',
  assigned_to_name: 'Meera Iyer',
  created_by_name: 'Priya Nair',
  scan_count: 5,
  decided_count: 3,
  open_count: 2,
  overridden_count: 0,
  overridden_unseen_count: 0,
  created_at: '2026-10-04T10:20:00Z',
  reminded_at: null,
  status: 'active',
  ...over,
})
const scan = (over: Partial<Assignment>): Assignment => ({
  scan_id: 's1',
  record_no: 'REC-1',
  status: 'assigned',
  removed_reason: null,
  equipment_type_name: 'Control Valve',
  captured_by_name: 'J. Martinez',
  location_path: 'Bldg C › Bin 05',
  flag_count: 0,
  submitted_at: '2026-10-03T10:00:00Z',
  thumbnail_url: null,
  my_decision: null,
  outcome: null,
  ...over,
})
const outcome = (over: Record<string, unknown> = {}) => ({
  decision: 'approved' as const,
  reject_category: null,
  decided_by_name: 'Meera Iyer',
  decided_at: '2026-10-05T09:00:00Z',
  overridden: false,
  ...over,
})

const dialog = () => within(screen.getByRole('dialog'))
const table = () => within(screen.getByRole('table', { name: 'Scans in batch B-12' }))
const row = (id: string) => within(table().getByText(id).closest('[role="row"]') as HTMLElement)

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(new Date('2026-10-05T12:00:00Z'))
  for (const fn of Object.values(calls)) fn.mockReset().mockResolvedValue({})
  state = { isPending: false, isError: false }
  detail = {
    batch: batch(),
    assignments: [
      scan({ scan_id: 's1', record_no: 'REC-1' }),
      scan({
        scan_id: 's2',
        record_no: 'REC-2',
        status: 'decided',
        equipment_type_name: 'Paint Label',
        outcome: outcome(),
      }),
      scan({
        scan_id: 's3',
        record_no: 'REC-3',
        status: 'decided',
        outcome: outcome({ decision: 'rejected', reject_category: 'image_unclear' }),
      }),
      scan({
        scan_id: 's4',
        record_no: 'REC-4',
        status: 'decided',
        outcome: outcome({
          decision: 'rejected',
          reject_category: 'other',
          decided_by_name: 'Priya Nair',
          overridden: true,
        }),
      }),
      scan({ scan_id: 's5', record_no: 'REC-5', status: 'removed', removed_reason: 'taken_back' }),
    ],
  }
})
afterEach(() => vi.useRealTimers())

describe('Batch page: what it shows', () => {
  it('GIVEN a batch THEN its header says who has it, since when and who made it', () => {
    page()
    expect(screen.getByRole('heading', { name: 'Batch B-12' })).toBeInTheDocument()
    expect(
      screen.getByText(
        `Delegated to Meera Iyer · ${dateTime('2026-10-04T10:20:00Z')} · by Priya Nair`,
      ),
    ).toBeInTheDocument()
    expect(screen.getByRole('link', { name: '← Delegations' })).toHaveAttribute(
      'href',
      '/delegations',
    )
  })

  it('GIVEN a batch THEN shows how far it is and the counts by outcome', () => {
    page()
    expect(screen.getByRole('progressbar', { name: '3 of 5 reviewed' })).toBeInTheDocument()
    expect(
      screen.getByText('1 approved · 2 rejected · 1 still with the technician'),
    ).toBeInTheDocument()
  })

  it('GIVEN the scans THEN each shows where it stands, with the reason under a rejection', () => {
    page()
    expect(row('REC-1').getByText('Delegated')).toBeInTheDocument()
    expect(row('REC-2').getByText('Approved')).toBeInTheDocument()
    expect(row('REC-3').getByText('Rejected')).toBeInTheDocument()
    expect(row('REC-3').getByText('Image unclear')).toBeInTheDocument()
    // The admin changed the technician's decision: "you" for the viewer.
    expect(row('REC-4').getByText('Changed by you')).toBeInTheDocument()
    expect(row('REC-5').getByText('Taken back')).toBeInTheDocument()
  })

  it('GIVEN the scans THEN decided ones show when, and undecided ones a dash', () => {
    page()
    expect(row('REC-2').getByText(dateTime('2026-10-05T09:00:00Z'))).toBeInTheDocument()
    expect(row('REC-1').getByText('—')).toBeInTheDocument()
  })

  it('GIVEN a decided scan THEN the action is Check, otherwise Open, and both open the scan', () => {
    page()
    expect(row('REC-2').getByRole('link', { name: 'Check REC-2' })).toHaveAttribute(
      'href',
      '/review-queue/s2',
    )
    expect(row('REC-1').getByRole('link', { name: 'Open REC-1' })).toHaveAttribute(
      'href',
      '/review-queue/s1',
    )
  })

  it('GIVEN loading or a missing batch THEN says so, with a way back', () => {
    state = { isPending: true, isError: false }
    detail = undefined
    page()
    expect(screen.getByText('Loading the batch…')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: '← Delegations' })).toBeInTheDocument()
  })

  it('GIVEN the batch cannot be loaded THEN says so', () => {
    state = { isPending: false, isError: true }
    detail = undefined
    page()
    expect(screen.getByText(/We couldn't load this batch/)).toBeInTheDocument()
  })
})

describe('Batch page: filters', () => {
  const funnel = (name: string) =>
    fireEvent.click(screen.getByRole('button', { name: `Filter by ${name}` }))

  it('GIVEN the Status filter WHEN Rejected is ticked THEN only rejected scans stay', () => {
    page()
    funnel('Status')
    fireEvent.click(screen.getByRole('checkbox', { name: 'Rejected' }))
    expect(table().queryByText('REC-1')).toBeNull()
    expect(table().queryByText('REC-2')).toBeNull()
    expect(table().getByText('REC-3')).toBeInTheDocument()
    expect(table().getByText('REC-4')).toBeInTheDocument()
    expect(screen.getByText('Status: Rejected')).toBeInTheDocument()
  })

  it('GIVEN the Schema filter THEN lists the batch’s schemas and filters by them', () => {
    page()
    funnel('Schema')
    fireEvent.click(screen.getByRole('checkbox', { name: 'Paint Label' }))
    expect(table().getAllByRole('link', { name: /^(Check|Open) / })).toHaveLength(1)
    expect(table().getByText('REC-2')).toBeInTheDocument()
  })

  it('GIVEN two filters THEN Clear all brings every scan back', () => {
    page()
    funnel('Status')
    fireEvent.click(screen.getByRole('checkbox', { name: 'Approved' }))
    funnel('Schema')
    fireEvent.click(screen.getByRole('checkbox', { name: 'Paint Label' }))
    fireEvent.click(screen.getByRole('button', { name: 'Clear all' }))
    expect(table().getAllByRole('link', { name: /^(Check|Open) / })).toHaveLength(5)
  })

  it('GIVEN a filter that matches nothing THEN says so', () => {
    page()
    funnel('Status')
    fireEvent.click(screen.getByRole('checkbox', { name: 'Left the batch' }))
    funnel('Schema')
    fireEvent.click(screen.getByRole('checkbox', { name: 'Paint Label' }))
    expect(screen.getByText('No scans match these filters.')).toBeInTheDocument()
  })
})

describe('Batch page: what an admin can do', () => {
  const buttons = () =>
    ['Send reminder', 'Reassign', 'Take back'].filter((name) =>
      screen.queryByRole('button', { name }),
    )

  it('GIVEN a batch in progress THEN Reassign and Take back are offered, not Send reminder', () => {
    page()
    expect(buttons()).toEqual(['Reassign', 'Take back'])
  })

  it('GIVEN a batch with no progress for a day or more THEN Send reminder joins them', () => {
    detail = { batch: batch({ decided_count: 0, open_count: 5 }), assignments: [] }
    page()
    expect(buttons()).toEqual(['Send reminder', 'Reassign', 'Take back'])
  })

  it.each([
    ['done', { status: 'completed' as const, decided_count: 5, open_count: 0 }],
    ['taken back', { status: 'taken_back' as const }],
  ])('GIVEN a %s batch THEN nothing can be done to it, only read', (_name, over) => {
    detail = { batch: batch(over), assignments: [] }
    page()
    expect(buttons()).toEqual([])
  })

  it('GIVEN Send reminder THEN the technician is reminded and the page says so', async () => {
    detail = { batch: batch({ decided_count: 0, open_count: 5 }), assignments: [] }
    page()
    fireEvent.click(screen.getByRole('button', { name: 'Send reminder' }))
    await waitFor(() => expect(calls.remind).toHaveBeenCalledOnce())
    // This is the one notice kept: nothing on the page changes, so it is not visible otherwise.
    expect(await screen.findByText('Reminder sent to Meera Iyer.')).toBeInTheDocument()
  })

  it('GIVEN Send reminder fails THEN the reason is shown', async () => {
    calls.remind.mockRejectedValue(
      new ApiError({ type: '/problems/forbidden', title: 'Not allowed', status: 403 }),
    )
    detail = { batch: batch({ decided_count: 0, open_count: 5 }), assignments: [] }
    page()
    fireEvent.click(screen.getByRole('button', { name: 'Send reminder' }))
    expect(await screen.findByText('Not allowed')).toBeInTheDocument()
  })

  it('GIVEN Take back THEN says what happens, sends the message, and closes with no banner', async () => {
    page()
    fireEvent.click(screen.getByRole('button', { name: 'Take back' }))
    expect(dialog().getByText('Take back batch B-12?')).toBeInTheDocument()
    expect(dialog().getByText(/go back to your review queue/)).toBeInTheDocument()
    expect(dialog().getByText(/loses them from the app straight away/)).toBeInTheDocument()
    expect(dialog().queryByText(/Unassigned/)).toBeNull() // not a status any more
    fireEvent.change(dialog().getByLabelText('Message to Meera Iyer (optional)'), {
      target: { value: 'I will handle these.' },
    })
    fireEvent.click(dialog().getByRole('button', { name: 'Take back 2 scans' }))
    await waitFor(() => expect(calls.takeBack).toHaveBeenCalledWith('I will handle these.'))
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull())
    expect(screen.queryByText(/was taken back/)).toBeNull() // the page shows it, no banner
  })

  it('GIVEN Reassign THEN the open scans go to the technician picked', async () => {
    page()
    fireEvent.click(screen.getByRole('button', { name: 'Reassign' }))
    expect(dialog().getByText(/Pick who takes over from Meera Iyer/)).toBeInTheDocument()
    pickTechnician(dialog(), 'Nguyen')
    fireEvent.click(dialog().getByRole('button', { name: /Reassign 1 scan to T\. Nguyen/ }))
    await waitFor(() => expect(calls.reassign).toHaveBeenCalledWith('tn'))
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull())
  })
})
