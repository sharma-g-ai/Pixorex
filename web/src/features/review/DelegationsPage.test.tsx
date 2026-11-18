import { fireEvent, render, screen, within } from '@testing-library/react'
import { MemoryRouter, useLocation } from 'react-router'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Me } from '../../api/me'
import type { Batch, BatchFilters, DecisionFilters, TechnicianDecision } from '../../api/review'
import { DashboardContext } from '../../app/DashboardContext'
import { dateTime } from '../../lib/time'
import { DelegationsPage } from './DelegationsPage'

let batches: Batch[] = []
let decisions: TechnicianDecision[] = []
let hasNextPage = false
const fetchNextPage = vi.fn()
const batchFilters: BatchFilters[] = []
const decisionFilters: DecisionFilters[] = []

vi.mock('../../api/review', () => ({
  useBatchList: (_buId: string, filters: BatchFilters) => {
    batchFilters.push(filters)
    return {
      items: batches,
      isPending: false,
      isError: false,
      hasNextPage,
      isFetchingNextPage: false,
      fetchNextPage,
    }
  },
  useDecisionList: (_buId: string, filters: DecisionFilters) => {
    decisionFilters.push(filters)
    return {
      items: decisions,
      isPending: false,
      isError: false,
      hasNextPage,
      isFetchingNextPage: false,
      fetchNextPage,
    }
  },
}))
vi.mock('../../api/technicians', () => ({
  useTechnicians: () => ({
    data: [
      { user_id: 'tn', full_name: 'T. Nguyen' },
      { user_id: 'ap', full_name: 'A. Patel' },
    ],
  }),
}))

const unit = { bu_id: 'p04', name: 'Plant 04', role: 'bu_admin' as const, is_primary: true }
const lastBatch = () => batchFilters.at(-1) as BatchFilters
const lastDecision = () => decisionFilters.at(-1) as DecisionFilters

function Where() {
  const here = useLocation()
  return <span data-testid="address">{here.pathname}</span>
}
function page(path = '/delegations') {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <DashboardContext.Provider value={{ me: {} as Me, role: 'bu_admin', unit }}>
        <DelegationsPage />
        <Where />
      </DashboardContext.Provider>
    </MemoryRouter>,
  )
}

const batch = (over: Partial<Batch>): Batch => ({
  batch_id: 'b14',
  batch_no: 'B-14',
  assigned_to_name: 'T. Nguyen',
  created_by_name: 'R. K',
  scan_count: 30,
  decided_count: 0,
  open_count: 30,
  overridden_count: 0,
  overridden_unseen_count: 0,
  created_at: '2026-10-03T12:00:00Z',
  reminded_at: null,
  status: 'active',
  ...over,
})
const decision = (over: Partial<TechnicianDecision>): TechnicianDecision => ({
  decision_id: 'd1',
  scan_id: 's1',
  record_no: 'REC-1',
  equipment_type_name: 'Control Valve',
  decided_by_name: 'T. Nguyen',
  decision: 'approved',
  reject_category: null,
  decided_at: '2026-10-05T09:00:00Z',
  overridden: false,
  batch_id: 'b12',
  batch_no: 'B-12',
  ...over,
})

const table = (name: string) => within(screen.getByRole('table', { name }))
const funnel = (name: string) =>
  fireEvent.click(screen.getByRole('button', { name: `Filter by ${name}` }))
const tick = (name: string) => fireEvent.click(screen.getByRole('checkbox', { name }))

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(new Date('2026-10-05T12:00:00Z'))
  batchFilters.length = 0
  decisionFilters.length = 0
  hasNextPage = false
  fetchNextPage.mockReset()
  batches = [
    batch({}), // no progress for 2 days
    batch({
      batch_id: 'b12',
      batch_no: 'B-12',
      assigned_to_name: 'A. Patel',
      decided_count: 6,
      scan_count: 10,
    }),
    batch({
      batch_id: 'b11',
      batch_no: 'B-11',
      decided_count: 10,
      scan_count: 10,
      status: 'completed',
    }),
    batch({
      batch_id: 'b10',
      batch_no: 'B-10',
      status: 'taken_back',
      decided_count: 4,
      scan_count: 8,
    }),
  ]
  decisions = [
    decision({}),
    decision({
      decision_id: 'd2',
      scan_id: 's2',
      record_no: 'REC-2',
      decision: 'rejected',
      reject_category: 'image_unclear',
    }),
    decision({
      decision_id: 'd3',
      scan_id: 's3',
      record_no: 'REC-3',
      decision: 'approved',
      overridden: true,
    }),
  ]
})
afterEach(() => vi.useRealTimers())

describe('Delegations: batches', () => {
  it('GIVEN the page THEN there are two tabs, Batches and All decisions', () => {
    page()
    expect(screen.getAllByRole('tab').map((t) => t.textContent)).toEqual([
      'Batches',
      'All decisions',
    ])
    expect(screen.getByRole('tab', { name: 'Batches' })).toHaveAttribute('aria-selected', 'true')
    expect(screen.queryByRole('tab', { name: 'Decided by technicians' })).toBeNull()
  })

  it('GIVEN the batch list THEN each row has one way in, Open, and no Reassign, Take back or Send reminder', () => {
    page()
    const list = table('Delegated batches')
    expect(list.getByRole('link', { name: 'Open batch B-14' })).toHaveAttribute(
      'href',
      '/delegations/b14',
    )
    expect(list.getAllByRole('link', { name: /^Open batch/ })).toHaveLength(4)
    for (const gone of ['Reassign', 'Take back', 'Send reminder', 'See decisions']) {
      expect(screen.queryByRole('button', { name: gone })).toBeNull()
    }
    // The batch number opens it too.
    expect(list.getByRole('link', { name: 'B-12' })).toHaveAttribute('href', '/delegations/b12')
  })

  it('GIVEN batches THEN each shows its progress and status, and the day it was delegated', () => {
    page()
    const list = table('Delegated batches')
    expect(list.getByText('No progress · 2 days')).toBeInTheDocument()
    expect(list.getByText('In progress')).toBeInTheDocument()
    expect(list.getByText('Done')).toBeInTheDocument()
    expect(list.getByText('Taken back')).toBeInTheDocument()
    expect(list.getByText('6 of 10 reviewed')).toBeInTheDocument()
    expect(list.getAllByText(dateTime('2026-10-03T12:00:00Z')).length).toBeGreaterThan(0)
  })

  it('GIVEN the opening view THEN asks for every technician, newest first, no dates', () => {
    page()
    expect(lastBatch()).toEqual({ assignedTo: [], from: '', to: '', sort: 'newest_first' })
  })

  it('GIVEN the Delegated to filter WHEN a technician is ticked THEN only theirs are asked for', () => {
    page()
    funnel('Delegated to')
    tick('A. Patel')
    expect(lastBatch().assignedTo).toEqual(['ap'])
    expect(screen.getByText('Delegated to: A. Patel')).toBeInTheDocument()
  })

  it('GIVEN the Delegated date WHEN a range and the sort are set THEN they are asked for', () => {
    page()
    funnel('Delegated')
    fireEvent.change(screen.getByLabelText('From'), { target: { value: '2026-10-01' } })
    expect(lastBatch().from).toBe('2026-10-01')
    expect(screen.getByText('Delegated: from 1 Oct')).toBeInTheDocument()
    fireEvent.click(
      screen.getByRole('button', {
        name: 'Sort by Delegated, newest first. Click for oldest first.',
      }),
    )
    expect(lastBatch().sort).toBe('oldest_first')
  })

  it('GIVEN the Status filter WHEN No progress is ticked THEN only batches with no progress stay', () => {
    page()
    funnel('Status')
    expect(screen.getByRole('checkbox', { name: 'In progress' })).toBeInTheDocument()
    tick('No progress')
    const list = table('Delegated batches')
    expect(list.getAllByRole('link', { name: /^Open batch/ })).toHaveLength(1)
    expect(list.getByRole('link', { name: 'Open batch B-14' })).toBeInTheDocument()
    expect(list.queryByText('Done')).toBeNull()
    // Two states ticked: both kinds stay.
    tick('Done')
    expect(table('Delegated batches').getAllByRole('link', { name: /^Open batch/ })).toHaveLength(2)
  })

  it('GIVEN a Status filter WHEN its chip is removed THEN every batch is back', () => {
    page()
    funnel('Status')
    tick('Done')
    tick('No progress')
    expect(table('Delegated batches').getAllByRole('link', { name: /^Open batch/ })).toHaveLength(2)
    // Chips list the choices in the order they were ticked.
    fireEvent.click(screen.getByRole('button', { name: 'Remove filter Status: Done, No progress' }))
    expect(table('Delegated batches').getAllByRole('link', { name: /^Open batch/ })).toHaveLength(4)
  })

  it('GIVEN no batches THEN says how to make one', () => {
    batches = []
    page()
    expect(screen.getByText(/No batches yet/)).toBeInTheDocument()
  })

  it('GIVEN a filter that matches no batch THEN says no batch matches, not that there are none', () => {
    batches = [batch({})] // only a batch with no progress
    page()
    funnel('Status')
    tick('Done')
    expect(screen.getByText('No batches match these filters.')).toBeInTheDocument()
    expect(screen.queryByText(/No batches yet/)).toBeNull()
  })

  it('GIVEN more batches THEN Load more fetches the next page', () => {
    hasNextPage = true
    page()
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }))
    expect(fetchNextPage).toHaveBeenCalledOnce()
  })
})

describe('Delegations: all decisions', () => {
  const open = () => fireEvent.click(screen.getByRole('tab', { name: 'All decisions' }))

  it('GIVEN BU Home’s "Recent decisions" link (?tab=decided) THEN opens on All decisions', () => {
    page('/delegations?tab=decided')
    expect(screen.getByRole('tab', { name: 'All decisions' })).toHaveAttribute(
      'aria-selected',
      'true',
    )
    expect(screen.getByRole('table', { name: 'Decisions by technicians' })).toBeInTheDocument()
  })

  it('GIVEN decisions THEN each shows its batch, decision, reviewer and time, and opens the scan', () => {
    page()
    open()
    const list = table('Decisions by technicians')
    expect(list.getAllByRole('link', { name: 'B-12' })[0]).toHaveAttribute(
      'href',
      '/delegations/b12',
    )
    expect(list.getByRole('link', { name: 'Check REC-1' })).toHaveAttribute(
      'href',
      '/review-queue/s1',
    )
    expect(list.getAllByText('T. Nguyen').length).toBeGreaterThan(0)
    expect(list.getAllByText(dateTime('2026-10-05T09:00:00Z')).length).toBeGreaterThan(0)
    // The reason under a rejection, and who changed an approval.
    expect(list.getByText('Image unclear')).toBeInTheDocument()
    expect(list.getByText('Changed by you')).toBeInTheDocument()
  })

  it('GIVEN a decision an admin changed THEN it counts as the opposite (an approval changed is Rejected)', () => {
    page()
    open()
    const row = within(
      table('Decisions by technicians').getByText('REC-3').closest('[role="row"]') as HTMLElement,
    )
    expect(row.getByText('Rejected')).toBeInTheDocument()
  })

  it('GIVEN the opening view THEN asks for every decision, newest first', () => {
    page()
    open()
    expect(lastDecision()).toEqual({
      decision: '',
      decidedBy: [],
      from: '',
      to: '',
      sort: 'newest_first',
    })
  })

  it('GIVEN the Decision filter THEN one ticked choice is asked for, and both ticked means no filter', () => {
    page()
    open()
    funnel('Decision')
    tick('Approved')
    expect(lastDecision().decision).toBe('approved')
    tick('Rejected')
    expect(lastDecision().decision).toBe('')
    expect(screen.getByText('Decision: Approved, Rejected')).toBeInTheDocument()
  })

  it('GIVEN the Reviewed by filter THEN technicians can be searched and ticked', () => {
    page()
    open()
    funnel('Reviewed by')
    fireEvent.change(screen.getByRole('searchbox', { name: 'Search Reviewed by' }), {
      target: { value: 'pat' },
    })
    expect(screen.queryByRole('checkbox', { name: 'T. Nguyen' })).toBeNull()
    tick('A. Patel')
    expect(lastDecision().decidedBy).toEqual(['ap'])
  })

  it('GIVEN the When column THEN it sorts and filters by the day', () => {
    page()
    open()
    funnel('When')
    fireEvent.change(screen.getByLabelText('To'), { target: { value: '2026-10-04' } })
    expect(lastDecision().to).toBe('2026-10-04')
    fireEvent.click(
      screen.getByRole('button', { name: 'Sort by When, newest first. Click for oldest first.' }),
    )
    expect(lastDecision().sort).toBe('oldest_first')
  })

  it('GIVEN no decisions THEN says so; with filters on, says nothing matches', () => {
    decisions = []
    page()
    open()
    expect(screen.getByText('No decisions by technicians yet.')).toBeInTheDocument()
    funnel('Decision')
    tick('Approved')
    expect(screen.getByText('No decisions match these filters.')).toBeInTheDocument()
  })
})
