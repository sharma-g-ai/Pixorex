import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '../../api/client'
import type { Me } from '../../api/me'
import type { Batch, QueueItem, ScanReview } from '../../api/review'
import { DashboardContext } from '../../app/DashboardContext'
import { DelegationsPage } from './DelegationsPage'
import { ReviewQueuePage } from './ReviewQueuePage'
import { ScanReviewView } from './ScanReviewView'

const calls = {
  decide: vi.fn(),
  override: vi.fn(),
  createBatch: vi.fn(),
  takeBack: vi.fn(),
  reassign: vi.fn(),
}
let review: ScanReview
let items: QueueItem[] = []
let batches: Batch[] = []

const mutation = (fn: ReturnType<typeof vi.fn>) => ({ mutateAsync: fn, isPending: false })
vi.mock('../../api/review', () => ({
  useScanReview: () => ({ data: review, isPending: false, isError: false }),
  useDecide: () => mutation(calls.decide),
  useOverride: () => mutation(calls.override),
  useReviewQueue: () => ({
    data: {
      counts: { waiting: 3, over_1d: 1, over_1w: 0, delegated: 1, decided_by_technicians: 2 },
      items,
    },
    isPending: false,
    isError: false,
  }),
  useTechnicianDecisions: () => ({ data: [], isPending: false }),
  useDelegates: () => ({
    data: [
      { user_id: 'tn', full_name: 'T. Nguyen', open_review_count: 12, own_scans_in_selection: 0 },
      { user_id: 'jm', full_name: 'J. Martinez', open_review_count: 0, own_scans_in_selection: 1 },
    ],
    isPending: false,
  }),
  useCreateBatch: () => mutation(calls.createBatch),
  useBatches: () => ({ data: batches, isPending: false, isError: false }),
  useBatch: () => ({
    data: {
      assignments: [{ scan_id: 's9', record_no: 'R9', status: 'assigned', removed_reason: null }],
    },
    isPending: false,
  }),
  useReassignBatch: () => mutation(calls.reassign),
  useTakeBackBatch: () => mutation(calls.takeBack),
  useRemindBatch: () => mutation(vi.fn()),
}))

const dialog = () => within(screen.getByRole('dialog'))
const unit = { bu_id: 'p04', name: 'Plant 04', role: 'bu_admin' as const, is_primary: true }
function inShell(node: React.ReactNode, path = '/') {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <DashboardContext.Provider value={{ me: {} as Me, role: 'bu_admin', unit }}>
        {node}
      </DashboardContext.Provider>
    </MemoryRouter>,
  )
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(new Date('2026-10-05T12:00:00Z'))
  for (const fn of Object.values(calls)) fn.mockReset().mockResolvedValue({ batch_no: 'B-16' })
  review = {
    scan_id: 's1',
    record_no: 'REC-90141',
    equipment_type_name: 'Control Valve',
    location_path: 'Building C › Bin 05',
    captured_by_name: 'J. Martinez',
    photos: [],
    current_revision: {
      revision_id: 'r1',
      revision_no: 1,
      origin: 'technician_review',
      empty_required_fields: [],
      review_status: 'waiting_for_approval',
    },
    fields: [
      {
        field_key: 'model',
        label: 'Model number',
        ai_value: 'CR 32-4-1 G',
        confidence: 0.42,
        flag_reasons: ['low_confidence'],
        technician_value: 'CR 32-4-1 F',
        verification_state: 'corrected',
        unreadable_reason: null,
        note: null,
      },
    ],
    decisions: [],
  }
  items = [
    {
      scan_id: 's1',
      record_no: 'REC-90141',
      equipment_type_name: 'Control Valve',
      captured_by_name: 'J. Martinez',
      location_path: 'Bldg C › Bin 05',
      flag_count: 3,
      corrected_count: 2,
      unreadable_count: 1,
      waiting_since: '2026-10-03T10:00:00Z',
      batch_no: null,
      assigned_to_name: null,
    },
    {
      scan_id: 's2',
      record_no: 'REC-90152',
      equipment_type_name: 'Paint Label',
      captured_by_name: 'T. Nguyen',
      location_path: 'Bldg C › Bin 04',
      flag_count: 0,
      corrected_count: 0,
      unreadable_count: 0,
      waiting_since: '2026-10-05T09:00:00Z',
      batch_no: 'B-15',
      assigned_to_name: 'A. Patel',
    },
  ]
  batches = [
    {
      batch_id: 'b14',
      batch_no: 'B-14',
      assigned_to_name: 'T. Nguyen',
      created_by_name: 'R. K',
      scan_count: 30,
      decided_count: 0,
      created_at: '2026-10-03T12:00:00Z',
      reminded_at: null,
      status: 'active',
    },
  ]
})
afterEach(() => vi.useRealTimers())

describe('Scan review', () => {
  it('GIVEN a waiting scan THEN shows AI vs technician values and approves (contract 3.5)', async () => {
    inShell(<ScanReviewView scanId="s1" back={{ to: '/review-queue', label: 'Review queue' }} />)
    const fields = within(screen.getByRole('table', { name: 'Extracted fields' }))
    expect(fields.getByText('Low confidence · 42%')).toBeInTheDocument()
    expect(fields.getByText('Corrected')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Approve' }))
    expect(await screen.findByText('Approved. The technician is told.')).toBeInTheDocument()
    expect(calls.decide).toHaveBeenCalledWith({
      body: { decision: 'approved' },
      idempotencyKey: expect.any(String),
    })
  })

  it('GIVEN Reject THEN a category is required and the note is sent', async () => {
    inShell(<ScanReviewView scanId="s1" back={{ to: '/', label: 'Back' }} />)
    fireEvent.click(screen.getByRole('button', { name: 'Reject' }))
    expect(dialog().getByRole('button', { name: 'Reject scan' })).toBeDisabled()
    fireEvent.click(dialog().getByLabelText('Data correction needed'))
    fireEvent.change(dialog().getByLabelText('Note for J. Martinez'), {
      target: { value: 'Check the 5th character.' },
    })
    fireEvent.click(dialog().getByRole('button', { name: 'Reject scan' }))

    await waitFor(() =>
      expect(calls.decide).toHaveBeenCalledWith({
        body: {
          decision: 'rejected',
          reject_category: 'data_correction_needed',
          note: 'Check the 5th character.',
        },
        idempotencyKey: expect.any(String),
      }),
    )
  })

  it('GIVEN someone else decided first THEN says so (409 already-decided)', async () => {
    calls.decide.mockRejectedValueOnce(
      new ApiError({ type: '/problems/already-decided', title: 'Conflict', status: 409 }),
    )
    inShell(<ScanReviewView scanId="s1" back={{ to: '/', label: 'Back' }} />)
    fireEvent.click(screen.getByRole('button', { name: 'Approve' }))
    expect(await screen.findByText(/Someone else decided this scan first/)).toBeInTheDocument()
  })

  it('GIVEN a technician approval THEN the admin can override it (contract 3.7)', async () => {
    review = {
      ...review,
      current_revision: { ...review.current_revision, review_status: 'approved' },
      decisions: [
        {
          decision_id: 'd1',
          revision_id: 'r1',
          decision: 'approved',
          reject_category: null,
          note: null,
          decided_by_name: 'T. Nguyen',
          decider_role: 'delegated_technician',
          is_current: true,
          overrides_decision_id: null,
          decided_at: '2026-10-04T17:20:00Z',
        },
      ],
    }
    inShell(<ScanReviewView scanId="s1" back={{ to: '/', label: 'Back' }} />)
    fireEvent.click(screen.getByRole('button', { name: 'Override: reject' }))
    fireEvent.click(dialog().getByLabelText('Image unclear'))
    fireEvent.click(dialog().getByRole('button', { name: 'Override and reject' }))
    await waitFor(() => expect(calls.override).toHaveBeenCalled())
    expect(calls.override.mock.calls[0]?.[0].body).toMatchObject({
      decision: 'rejected',
      reject_category: 'image_unclear',
    })
  })
})

describe('Review queue', () => {
  it('GIVEN scans THEN lists them with counts; delegated scans cannot be picked', () => {
    inShell(<ReviewQueuePage />)
    expect(screen.getByRole('tab', { name: /Over 1 day/ })).toHaveTextContent('1')
    const table = within(screen.getByRole('table', { name: 'Scans waiting for review' }))
    expect(table.getByText('2 corrected · 1 unreadable')).toBeInTheDocument()
    expect(table.getByText('2 days')).toBeInTheDocument()
    expect(table.getByText('A. Patel · B-15')).toBeInTheDocument()
    expect(table.queryByRole('checkbox', { name: 'Select REC-90152' })).not.toBeInTheDocument()
  })

  it('GIVEN a selected scan WHEN delegated THEN contract 3.9 gets the technician and scans', async () => {
    inShell(<ReviewQueuePage />)
    fireEvent.click(screen.getByRole('checkbox', { name: 'Select REC-90141' }))
    fireEvent.click(screen.getByRole('button', { name: 'Delegate to technicians' }))
    fireEvent.click(dialog().getByLabelText(/T\. Nguyen/))
    fireEvent.click(dialog().getByRole('button', { name: 'Delegate 1 scan to T. Nguyen' }))

    expect(await screen.findByText('Batch B-16 delegated to T. Nguyen.')).toBeInTheDocument()
    expect(calls.createBatch).toHaveBeenCalledWith({
      assignedTo: 'tn',
      scanIds: ['s1'],
      idempotencyKey: expect.any(String),
    })
  })

  it('GIVEN the technician captured every selected scan THEN they cannot get the batch', () => {
    inShell(<ReviewQueuePage />)
    fireEvent.click(screen.getByRole('checkbox', { name: 'Select REC-90141' }))
    fireEvent.click(screen.getByRole('button', { name: 'Delegate to technicians' }))
    fireEvent.click(dialog().getByLabelText(/J\. Martinez/))
    expect(dialog().getByText(/excluded because J\. Martinez submitted it/)).toBeInTheDocument()
    expect(dialog().getByRole('button', { name: 'Delegate 0 scans to J. Martinez' })).toBeDisabled()
  })
})

describe('Delegations', () => {
  it('GIVEN a batch with no progress THEN it says so and can be taken back with a message', async () => {
    inShell(<DelegationsPage />)
    expect(screen.getByText('No progress · 2 days')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Take back' }))
    fireEvent.change(dialog().getByLabelText('Message to T. Nguyen (optional)'), {
      target: { value: 'I will handle these.' },
    })
    fireEvent.click(dialog().getByRole('button', { name: 'Take back 30 scans' }))
    await waitFor(() => expect(calls.takeBack).toHaveBeenCalledWith('I will handle these.'))
  })

  it('GIVEN BU Home "All decisions" (?tab=decided) THEN opens on Decided by technicians', () => {
    inShell(<DelegationsPage />, '/delegations?tab=decided')
    expect(screen.getByRole('tab', { name: 'Decided by technicians' })).toHaveAttribute(
      'aria-selected',
      'true',
    )
  })

  it('GIVEN Reassign THEN the open scans go to the picked technician (contract 3.12)', async () => {
    inShell(<DelegationsPage />)
    fireEvent.click(screen.getByRole('button', { name: 'Reassign' }))
    fireEvent.click(dialog().getByLabelText(/T\. Nguyen/))
    fireEvent.click(dialog().getByRole('button', { name: 'Reassign 1 scan to T. Nguyen' }))
    await waitFor(() => expect(calls.reassign).toHaveBeenCalledWith('tn'))
  })
})
