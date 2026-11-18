import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { MemoryRouter, useLocation } from 'react-router'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Me } from '../../api/me'
import type { QueueFilters, QueueItem } from '../../api/review'
import { DashboardContext } from '../../app/DashboardContext'
import { pickTechnician } from '../../test/pickTechnician'
import { dateTime } from '../../lib/time'
import { ReviewQueuePage } from './ReviewQueuePage'

const createBatch = vi.fn()
const fetchNextPage = vi.fn()
let items: QueueItem[] = []
let hasNextPage = false
const asked: QueueFilters[] = []

const mutation = (fn: ReturnType<typeof vi.fn>) => ({ mutateAsync: fn, isPending: false })
vi.mock('../../api/review', () => ({
  useReviewQueue: (_buId: string, filters: QueueFilters) => {
    asked.push(filters)
    return {
      items,
      isPending: false,
      isError: false,
      hasNextPage,
      isFetchingNextPage: false,
      fetchNextPage,
    }
  },
  useQueueCounts: () => ({ data: { waiting: 3 } }),
  useDelegates: () => ({
    data: [
      { user_id: 'tn', full_name: 'T. Nguyen', open_review_count: 12, own_scans_in_selection: 0 },
      { user_id: 'jm', full_name: 'J. Martinez', open_review_count: 0, own_scans_in_selection: 1 },
    ],
    isPending: false,
  }),
  useCreateBatch: () => mutation(createBatch),
}))
vi.mock('../../api/equipmentTypes', () => ({
  useEquipmentTypes: () => ({
    data: [
      { type_id: 't1', name: 'Control Valve' },
      { type_id: 't2', name: 'Paint Label' },
    ],
  }),
}))
vi.mock('../../api/technicians', () => ({
  useTechnicians: () => ({
    data: [
      { user_id: 'jm', full_name: 'J. Martinez' },
      { user_id: 'tn', full_name: 'T. Nguyen' },
    ],
  }),
}))

const unit = { bu_id: 'p04', name: 'Plant 04', role: 'bu_admin' as const, is_primary: true }
const dialog = () => within(screen.getByRole('dialog', { name: /Delegate/ }))
const last = () => asked.at(-1) as QueueFilters

function Where() {
  const here = useLocation()
  return <span data-testid="address">{here.search}</span>
}
function page(path = '/review-queue') {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <DashboardContext.Provider value={{ me: {} as Me, role: 'bu_admin', unit }}>
        <ReviewQueuePage />
        <Where />
      </DashboardContext.Provider>
    </MemoryRouter>,
  )
}

const base = {
  flag_count: 0,
  corrected_count: 0,
  unreadable_count: 0,
  revision_no: 1,
  resubmitted: false,
  approved_by_name: null,
  batch_id: null,
  batch_no: null,
  assigned_to_name: null,
  decided_by_name: null,
}
const free: QueueItem = {
  ...base,
  scan_id: 's1',
  record_no: 'REC-90141',
  equipment_type_name: 'Control Valve',
  captured_by_name: 'J. Martinez',
  location_path: 'Bldg C › Bin 05',
  waiting_since: '2026-10-03T10:00:00Z',
  date: '2026-10-03T10:00:00Z',
  status: 'waiting',
  revision_no: 2,
  resubmitted: true,
}
const delegated: QueueItem = {
  ...base,
  scan_id: 's2',
  record_no: 'REC-90152',
  equipment_type_name: 'Paint Label',
  captured_by_name: 'T. Nguyen',
  location_path: 'Bldg C › Bin 04',
  waiting_since: '2026-10-05T09:00:00Z',
  date: '2026-10-05T09:00:00Z',
  status: 'waiting',
  batch_id: 'b15',
  batch_no: 'B-15',
  assigned_to_name: 'A. Patel',
}
const approved: QueueItem = {
  ...base,
  scan_id: 's3',
  record_no: 'REC-90160',
  equipment_type_name: 'Paint Label',
  captured_by_name: 'T. Nguyen',
  location_path: 'Bldg D › Bin 01',
  waiting_since: '2026-10-02T08:00:00Z',
  date: '2026-10-04T10:00:00Z',
  status: 'approved',
  decided_by_name: 'Bo Plant04',
  approved_by_name: 'Bo Plant04',
}
const rejected: QueueItem = {
  ...approved,
  scan_id: 's4',
  record_no: 'REC-90170',
  status: 'rejected',
  decided_by_name: 'A. Patel',
  approved_by_name: null,
}

const table = () => within(screen.getByRole('table', { name: 'Review queue scans' }))
const funnel = (name: string) =>
  fireEvent.click(screen.getByRole('button', { name: `Filter by ${name}` }))
const tick = (name: string) => fireEvent.click(screen.getByRole('checkbox', { name }))

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(new Date('2026-10-05T12:00:00Z'))
  asked.length = 0
  items = [free, delegated, approved, rejected]
  hasNextPage = false
  createBatch.mockReset().mockResolvedValue({ batch_no: 'B-16' })
  fetchNextPage.mockReset()
})
afterEach(() => vi.useRealTimers())

describe('Review queue: one table, no tabs', () => {
  it('GIVEN the page THEN there are no tabs and no Delegate by bin', () => {
    page()
    expect(screen.queryByRole('tablist')).not.toBeInTheDocument()
    expect(screen.queryByRole('tab')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Delegate by bin/ })).not.toBeInTheDocument()
  })

  it('GIVEN the table THEN its columns are the select-all checkbox, Scan ID, Schema, Captured by, Location, Date, Status', () => {
    page()
    const headers = table()
      .getAllByRole('columnheader')
      .map((h) => h.textContent ?? '')
    // The first column holds only the select-all checkbox, no word.
    expect(headers[0]).toBe('')
    expect(
      within(screen.getAllByRole('columnheader')[0] as HTMLElement).getByRole('checkbox', {
        name: 'Select all waiting scans shown',
      }),
    ).toBeInTheDocument()
    expect(headers.slice(1).map((h) => h.replace(/[▲▼]/g, '').trim())).toEqual([
      'Scan ID',
      'Schema',
      'Captured by',
      'Location',
      'Date',
      'Status',
    ])
    // Not columns any more: the old Assigned and Approved by, and the old Waiting since.
    for (const gone of ['Assigned', 'Approved by', 'Waiting since']) {
      expect(table().queryByRole('columnheader', { name: new RegExp(`^${gone}`) })).toBeNull()
    }
  })

  it('GIVEN the opening view THEN asks the API for scans under review in the default order, with a Status chip', () => {
    page()
    expect(last()).toEqual({
      status: ['waiting'],
      schemas: [],
      capturedBy: [],
      from: '',
      to: '',
      search: '',
      decidedFrom: '',
      sort: '',
    })
    const chips = within(screen.getByRole('list', { name: 'Filters applied' }))
    expect(chips.getByText('Status: Under Review')).toBeInTheDocument()
  })

  it('GIVEN scans THEN each shows its status, and who is behind it', () => {
    page()
    const row = (id: string) => within(table().getByText(id).closest('[role="row"]') as HTMLElement)
    // Waiting, nobody has it.
    expect(row('REC-90141').getByText('Under Review')).toBeInTheDocument()
    expect(row('REC-90141').queryByText(/^With /)).toBeNull()
    // Waiting, with a technician: who, and a link to the batch.
    expect(row('REC-90152').getByText('Under Review')).toBeInTheDocument()
    expect(row('REC-90152').getByText(/With A\. Patel/)).toBeInTheDocument()
    expect(row('REC-90152').getByRole('link', { name: 'B-15' })).toHaveAttribute(
      'href',
      '/delegations/b15',
    )
    // Decided: the status and who decided.
    expect(row('REC-90160').getByText('Approved')).toBeInTheDocument()
    expect(row('REC-90160').getByText('Bo Plant04')).toBeInTheDocument()
    expect(row('REC-90170').getByText('Rejected')).toBeInTheDocument()
    expect(row('REC-90170').getByText('A. Patel')).toBeInTheDocument()
  })

  it('GIVEN scans THEN the Date column holds only the capture date, and the pill tells the wait on hover', () => {
    page()
    const row = (id: string) => within(table().getByText(id).closest('[role="row"]') as HTMLElement)
    expect(row('REC-90141').getByText(dateTime('2026-10-03T10:00:00Z'))).toBeInTheDocument()
    expect(row('REC-90160').getByText(dateTime('2026-10-04T10:00:00Z'))).toBeInTheDocument()
    // No "2 days" badge and no "Decided" label in the Date column.
    expect(row('REC-90141').queryByText('2 days')).toBeNull()
    expect(row('REC-90160').queryByText('Decided')).toBeNull()
    // The wait is the Under Review pill's hover text (2 days since 3 Oct, shown on 5 Oct).
    expect(row('REC-90141').getByText('Under Review')).toHaveAttribute(
      'title',
      'Under review for 2 days',
    )
    expect(row('REC-90160').getByText('Approved')).not.toHaveAttribute('title')
  })

  it('GIVEN a resubmitted scan THEN it is marked', () => {
    page()
    expect(table().getByText('Resubmitted · rev 2')).toBeInTheDocument()
  })

  it('GIVEN scans THEN the count line says how many are shown, with a + when there are more', () => {
    page()
    expect(screen.getByRole('status')).toHaveTextContent('4 scans')
    hasNextPage = true
    page()
    expect(screen.getAllByRole('status').at(-1)).toHaveTextContent('4+ scans')
  })

  it('GIVEN more pages WHEN Load more is pressed THEN the next page is fetched', () => {
    hasNextPage = true
    page()
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }))
    expect(fetchNextPage).toHaveBeenCalledOnce()
  })
})

describe('Selecting and delegating', () => {
  it('GIVEN scans THEN only a waiting scan nobody has can be picked', () => {
    page()
    expect(table().getByRole('checkbox', { name: 'Select REC-90141' })).toBeInTheDocument()
    for (const id of ['REC-90152', 'REC-90160', 'REC-90170']) {
      expect(table().queryByRole('checkbox', { name: `Select ${id}` })).toBeNull()
    }
  })

  it('GIVEN the checkbox beside "Select" WHEN ticked THEN every free waiting scan is picked, and untick clears', () => {
    items = [free, { ...free, scan_id: 's5', record_no: 'REC-90180' }, delegated, approved]
    page()
    const all = screen.getByRole('checkbox', { name: 'Select all waiting scans shown' })
    expect(all).not.toBeChecked()
    fireEvent.click(all)
    expect(screen.getByText('2 selected')).toBeInTheDocument()
    expect(table().getByRole('checkbox', { name: 'Select REC-90141' })).toBeChecked()
    expect(table().getByRole('checkbox', { name: 'Select REC-90180' })).toBeChecked()
    expect(all).toBeChecked()
    fireEvent.click(all)
    expect(screen.queryByText(/selected$/)).toBeNull()
  })

  it('GIVEN only some are picked THEN the header checkbox shows a dash, not a tick', () => {
    items = [free, { ...free, scan_id: 's5', record_no: 'REC-90180' }]
    page()
    fireEvent.click(table().getByRole('checkbox', { name: 'Select REC-90141' }))
    const all = screen.getByRole('checkbox', {
      name: 'Select all waiting scans shown',
    }) as HTMLInputElement
    expect(all.indeterminate).toBe(true)
    expect(all.checked).toBe(false)
  })

  it('GIVEN no scan can be picked THEN the header checkbox is disabled', () => {
    items = [delegated, approved]
    page()
    expect(screen.getByRole('checkbox', { name: 'Select all waiting scans shown' })).toBeDisabled()
  })

  it('GIVEN a picked scan WHEN delegated THEN contract 3.9 gets the technician and scans, and no banner is shown', async () => {
    page()
    fireEvent.click(table().getByRole('checkbox', { name: 'Select REC-90141' }))
    fireEvent.click(screen.getByRole('button', { name: 'Delegate to technicians' }))
    pickTechnician(dialog(), 'Nguyen')
    fireEvent.click(dialog().getByRole('button', { name: 'Delegate 1 scan to T. Nguyen' }))
    await waitFor(() =>
      expect(createBatch).toHaveBeenCalledWith({
        assignedTo: 'tn',
        scanIds: ['s1'],
        idempotencyKey: expect.any(String),
      }),
    )
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull())
    // The list shows the result (who has it now), so there is no banner and the pick is cleared.
    expect(screen.queryByText(/delegated to T\. Nguyen/)).toBeNull()
    expect(screen.queryByText(/selected$/)).toBeNull()
  })

  it('GIVEN the delegate popup THEN it has no bin picker, and no technician list until a name is typed', () => {
    page()
    fireEvent.click(table().getByRole('checkbox', { name: 'Select REC-90141' }))
    fireEvent.click(screen.getByRole('button', { name: 'Delegate to technicians' }))
    expect(dialog().queryByRole('combobox', { name: 'Add scans by bin' })).toBeNull()
    expect(dialog().queryByText(/bin/i)).toBeNull()
    expect(dialog().queryAllByRole('option')).toHaveLength(0)
    expect(dialog().getByRole('button', { name: 'Pick a technician' })).toBeDisabled()
    pickTechnician(dialog(), 'Nguyen')
    expect(dialog().getByRole('button', { name: 'Delegate 1 scan to T. Nguyen' })).toBeEnabled()
  })

  it('GIVEN the technician captured every picked scan THEN they cannot get the batch', () => {
    page()
    fireEvent.click(table().getByRole('checkbox', { name: 'Select REC-90141' }))
    fireEvent.click(screen.getByRole('button', { name: 'Delegate to technicians' }))
    pickTechnician(dialog(), 'Martinez')
    expect(dialog().getByText(/excluded because J\. Martinez submitted it/)).toBeInTheDocument()
    expect(dialog().getByRole('button', { name: 'Delegate 0 scans to J. Martinez' })).toBeDisabled()
  })
})

describe('Header filters', () => {
  it('GIVEN the Status filter WHEN Approved is ticked THEN waiting and approved are asked for', () => {
    page()
    funnel('Status')
    expect(screen.getByRole('dialog', { name: 'Status filter' })).toBeInTheDocument()
    expect(screen.getByRole('checkbox', { name: 'Under Review' })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: 'Approved' })).not.toBeChecked()
    tick('Approved')
    expect(last().status).toEqual(['waiting', 'approved'])
    expect(screen.getByTestId('address')).toHaveTextContent('status=waiting&status=approved')
  })

  it('GIVEN the Status chip WHEN removed THEN all three statuses are asked for (the API default is waiting)', () => {
    page()
    fireEvent.click(screen.getByRole('button', { name: 'Remove filter Status: Under Review' }))
    // The API's own default is waiting, so "no status filter" must be asked for as all three.
    expect(last().status).toEqual(['waiting', 'approved', 'rejected'])
    expect(screen.getByTestId('address')).toHaveTextContent('status=any')
  })

  it('GIVEN the Schema filter THEN it lists the unit’s schemas and filters by the ticked one', () => {
    page()
    funnel('Schema')
    expect(screen.getByRole('checkbox', { name: 'Control Valve' })).toBeInTheDocument()
    tick('Paint Label')
    expect(last().schemas).toEqual(['t2'])
    expect(screen.getByText('Schema: Paint Label')).toBeInTheDocument()
  })

  it('GIVEN the Captured by filter THEN it lists technicians, searchable, and filters by the ticked ones', () => {
    page()
    funnel('Captured by')
    fireEvent.change(screen.getByRole('searchbox', { name: 'Search Captured by' }), {
      target: { value: 'ngu' },
    })
    expect(screen.queryByRole('checkbox', { name: 'J. Martinez' })).toBeNull()
    tick('T. Nguyen')
    expect(last().capturedBy).toEqual(['tn'])
    expect(screen.getByText('Captured by: T. Nguyen')).toBeInTheDocument()
  })

  it('GIVEN the Date filter WHEN From and To are set THEN the range is asked for and shown as a chip', () => {
    page()
    funnel('Date')
    fireEvent.change(screen.getByLabelText('From'), { target: { value: '2026-10-01' } })
    fireEvent.change(screen.getByLabelText('To'), { target: { value: '2026-10-04' } })
    expect(last().from).toBe('2026-10-01')
    expect(last().to).toBe('2026-10-04')
    expect(screen.getByText('Date: 1 Oct – 4 Oct')).toBeInTheDocument()
    // Only whole days up to today (Indian time) can be picked.
    expect(screen.getByLabelText('To')).toHaveAttribute('max', '2026-10-05')
  })

  it('GIVEN the sort arrow THEN it flips between the default order and newest first, and only the Date column has one', () => {
    page()
    expect(screen.getAllByRole('button', { name: /^Sort by/ })).toHaveLength(1)
    fireEvent.click(
      screen.getByRole('button', { name: 'Sort by Date, oldest first. Click for newest first.' }),
    )
    expect(last().sort).toBe('newest_first')
    expect(screen.getByTestId('address')).toHaveTextContent('sort=newest_first')
    fireEvent.click(
      screen.getByRole('button', { name: 'Sort by Date, newest first. Click for oldest first.' }),
    )
    expect(last().sort).toBe('') // back to the default order
    expect(screen.getByTestId('address')).not.toHaveTextContent('sort=')
  })

  it('GIVEN several filters THEN Clear all removes every one, including Status', () => {
    page('/review-queue?status=approved&schema=t1&by=tn&from=2026-10-01')
    expect(
      within(screen.getByRole('list', { name: 'Filters applied' })).getAllByRole('listitem'),
    ).toHaveLength(5) // 4 chips + Clear all
    fireEvent.click(screen.getByRole('button', { name: 'Clear all' }))
    expect(last()).toMatchObject({
      status: ['waiting', 'approved', 'rejected'],
      schemas: [],
      capturedBy: [],
      from: '',
      to: '',
    })
    expect(screen.getByTestId('address')).toHaveTextContent('status=any')
  })

  it('GIVEN no scan matches THEN says so with a way to clear the filters', () => {
    items = []
    page('/review-queue?schema=t1')
    expect(screen.getByText(/No scans match these filters/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Clear all filters' }))
    expect(last().schemas).toEqual([])
  })

  it('GIVEN nothing under review and no filters but the default THEN says so', () => {
    items = []
    page()
    expect(screen.getByText('Nothing under review here.')).toBeInTheDocument()
  })
})

describe('Links into the queue', () => {
  it('GIVEN Home’s "approved this week" link THEN it opens on approved scans decided from that Monday', () => {
    page('/review-queue?status=approved&decided=2026-10-05')
    expect(last()).toMatchObject({ status: ['approved'], decidedFrom: '2026-10-05', from: '' })
    const chips = within(screen.getByRole('list', { name: 'Filters applied' }))
    expect(chips.getByText('Status: Approved')).toBeInTheDocument()
    expect(chips.getByText('Decided from 5 Oct')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Remove filter Decided from 5 Oct' }))
    expect(last().decidedFrom).toBe('')
  })

  it('GIVEN the Scan ID funnel WHEN an ID is typed with spaces THEN it is sent as typed, shown as a chip, and cleared with it', () => {
    page()
    funnel('Scan ID')
    fireEvent.change(screen.getByLabelText('Search Scan ID'), {
      target: { value: '100 000 039 6' },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Done' }))
    expect(last().search).toBe('100 000 039 6')
    expect(screen.getByTestId('address')).toHaveTextContent('q=100+000+039+6')
    expect(screen.getByText('Scan ID: 100 000 039 6')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Remove filter Scan ID: 100 000 039 6' }))
    expect(last().search).toBe('')
  })

  it('GIVEN a search in the address THEN the box starts with it and Clear all removes it too', () => {
    page('/review-queue?q=1000000396')
    expect(last().search).toBe('1000000396')
    fireEvent.click(screen.getByRole('button', { name: 'Clear all' }))
    expect(last().search).toBe('')
  })

  it('GIVEN Home’s "approved this week" link THEN it opens on approved scans from that Monday', () => {
    page('/review-queue?status=approved&from=2026-10-05')
    expect(last()).toMatchObject({ status: ['approved'], from: '2026-10-05', to: '' })
    const chips = within(screen.getByRole('list', { name: 'Filters applied' }))
    expect(chips.getByText('Status: Approved')).toBeInTheDocument()
    expect(chips.getByText('Date: from 5 Oct')).toBeInTheDocument()
  })

  it('GIVEN the old ?tab=approved link THEN it still opens (on the default view, not a broken page)', () => {
    page('/review-queue?tab=approved')
    expect(last().status).toEqual(['waiting'])
    expect(screen.getByRole('table', { name: 'Review queue scans' })).toBeInTheDocument()
  })
})
