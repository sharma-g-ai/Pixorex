import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '../../api/client'
import type { Me } from '../../api/me'
import type { ScanReview } from '../../api/review'
import { DashboardContext } from '../../app/DashboardContext'
import { ScanReviewView } from './ScanReviewView'

const calls = {
  decide: vi.fn(),
  override: vi.fn(),
}
let review: ScanReview

const mutation = (fn: ReturnType<typeof vi.fn>) => ({ mutateAsync: fn, isPending: false })
vi.mock('../../api/review', () => ({
  useScanReview: () => ({ data: review, isPending: false, isError: false }),
  useScanHistory: () => ({ data: history, isPending: false, isError: false }),
  useDecide: () => mutation(calls.decide),
  useOverride: () => mutation(calls.override),
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

let history: unknown

beforeEach(() => {
  history = {
    scan_id: 's1',
    record_no: '1000000040',
    now: {
      text: 'With Bo Plant04 for review.',
      since: '2026-10-05T10:31:00Z',
      needs_technician: false,
    },
    events: [
      {
        kind: 'submitted',
        at: '2026-10-03T11:45:00Z',
        title: 'Submitted for review by J. Martinez',
        detail: '1 corrected',
      },
      {
        kind: 'rejected',
        at: '2026-10-04T15:15:00Z',
        title: 'Rejected by Bo Plant04',
        detail: 'Other · “Wrong plate”',
      },
      {
        kind: 'resubmitted',
        at: '2026-10-05T10:31:00Z',
        title: 'Fixed and sent back by J. Martinez',
        detail: 'Serial: SN-1 → SN-2',
      },
    ],
  }
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
})
afterEach(() => vi.useRealTimers())

describe('Scan review', () => {
  it('GIVEN a waiting scan THEN shows AI vs technician values and approves (contract 3.5)', async () => {
    inShell(<ScanReviewView scanId="s1" back={{ to: '/review-queue', label: 'Review queue' }} />)
    const fields = within(screen.getByRole('table', { name: 'Extracted fields' }))
    expect(fields.getByText('Low confidence · 42%')).toBeInTheDocument()
    expect(fields.getByText('Corrected')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Approve' }))
    await waitFor(() => expect(calls.decide).toHaveBeenCalled())
    // No confirmation banner: the History below shows the decision.
    expect(screen.queryByRole('status')).toBeNull()
    expect(screen.queryByText(/is told/)).toBeNull()
    expect(calls.decide).toHaveBeenCalledWith({
      body: { decision: 'approved' },
      idempotencyKey: expect.any(String),
    })
  })

  it('GIVEN a scan THEN its location shows one place per line, biggest first', () => {
    inShell(<ScanReviewView scanId="s1" back={{ to: '/', label: 'Back' }} />)
    const list = screen.getByRole('list', { name: 'Building C › Bin 05' })
    expect(
      within(list)
        .getAllByRole('listitem')
        .map((li) => li.textContent),
    ).toEqual(['Building C', '↳Bin 05'])
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

  it('GIVEN a decided scan THEN the decision is told once, in History, not in extra lines', () => {
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
          decided_by_name: 'Bo Plant04',
          decider_role: 'bu_admin',
          is_current: true,
          overrides_decision_id: null,
          decided_at: '2026-10-04T17:20:00Z',
        },
      ],
    }
    inShell(<ScanReviewView scanId="s1" back={{ to: '/', label: 'Back' }} />)
    expect(screen.queryByText(/Approved by Bo Plant04/)).toBeNull() // no banner
    expect(screen.queryByRole('heading', { name: 'Decisions' })).toBeNull() // no second list
    expect(screen.queryByText('This scan is not waiting for a decision.')).toBeNull()
    expect(screen.queryByRole('button', { name: 'Override: reject' })).toBeNull() // final
    expect(screen.getByRole('list', { name: 'History' })).toBeInTheDocument()
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

  it('GIVEN reason Other THEN a note is required before it can be sent (O-21)', () => {
    inShell(<ScanReviewView scanId="s1" back={{ to: '/', label: 'Back' }} />)
    fireEvent.click(screen.getByRole('button', { name: 'Reject' }))
    const send = () => dialog().getByRole('button', { name: 'Reject scan' })
    expect(send()).toBeDisabled() // no reason yet
    fireEvent.click(dialog().getByLabelText('Other'))
    expect(send()).toBeDisabled() // Other without a note
    fireEvent.change(dialog().getByLabelText(/required for Other/), {
      target: { value: 'Plate is for a different motor' },
    })
    expect(send()).toBeEnabled()
    fireEvent.click(dialog().getByLabelText('Image unclear'))
    fireEvent.change(dialog().getByLabelText(/Note for/), { target: { value: '' } })
    expect(send()).toBeEnabled() // a listed reason needs no note
  })
})

describe('Scan history', () => {
  it('GIVEN a rejected and resubmitted scan THEN the timeline shows it, with no repeated Now line', () => {
    inShell(<ScanReviewView scanId="s1" back={{ to: '/', label: 'Back' }} />)
    const timeline = within(screen.getByRole('list', { name: 'History' }))
    const items = timeline.getAllByRole('listitem')
    expect(items).toHaveLength(3)
    expect(items[1]).toHaveTextContent('Rejected by Bo Plant04')
    expect(items[1]).toHaveTextContent('Other · “Wrong plate”')
    expect(items[2]).toHaveTextContent('Serial: SN-1 → SN-2')
    expect(screen.queryByText(/^Now:/)).toBeNull()
  })
})

describe('Override a technician rejection (contract 3.7)', () => {
  const rejectedByTechnician = () => ({
    ...review,
    current_revision: { ...review.current_revision, review_status: 'rejected' },
    decisions: [
      {
        decision_id: 'd1',
        revision_id: 'r1',
        decision: 'rejected' as const,
        reject_category: 'data_correction_needed',
        note: null,
        decided_by_name: 'Amrutha',
        decider_role: 'delegated_technician' as const,
        is_current: true,
        overrides_decision_id: null,
        decided_at: '2026-11-13T14:18:15Z',
      },
    ],
  })

  it('GIVEN a technician rejected THEN the admin can override it to approved', async () => {
    review = rejectedByTechnician()
    inShell(<ScanReviewView scanId="s1" back={{ to: '/', label: 'Back' }} />)
    expect(screen.queryByRole('button', { name: 'Override: reject' })).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Override: approve' }))
    fireEvent.click(dialog().getByRole('button', { name: 'Override and approve' }))
    await waitFor(() => expect(calls.override).toHaveBeenCalled())
    expect(calls.override.mock.calls[0]?.[0].body).toEqual({ decision: 'approved' })
    expect(screen.queryByText(/Decision changed to approved/)).toBeNull() // no banner either
  })

  it('GIVEN the API refuses (required fields empty) THEN its message shows', async () => {
    review = rejectedByTechnician()
    calls.override.mockRejectedValueOnce(
      new ApiError({
        type: '/problems/invalid-state',
        title: 'Conflict',
        status: 409,
        detail: 'Required fields are empty: reject it for rework.',
      }),
    )
    inShell(<ScanReviewView scanId="s1" back={{ to: '/', label: 'Back' }} />)
    fireEvent.click(screen.getByRole('button', { name: 'Override: approve' }))
    fireEvent.click(dialog().getByRole('button', { name: 'Override and approve' }))
    expect(
      await screen.findByText(/Required fields are empty: reject it for rework./),
    ).toBeInTheDocument()
  })
})

describe('Low confidence and photos', () => {
  const kept = {
    field_key: 'voltage',
    label: 'Rated voltage',
    ai_value: '230',
    confidence: 0.7,
    flag_reasons: ['low_confidence'],
    technician_value: '230',
    verification_state: 'accepted',
    unreadable_reason: null,
    note: null,
  }

  it('GIVEN a low-confidence value kept as read THEN it is shown with its score, marked for review', () => {
    review = { ...review, fields: [kept] }
    inShell(<ScanReviewView scanId="s1" back={{ to: '/', label: 'Back' }} />)
    const fields = within(screen.getByRole('table', { name: 'Extracted fields' }))
    expect(fields.getByText('230')).toBeInTheDocument() // once: one column, not two
    expect(fields.getByText('70% confidence · needs review')).toBeInTheDocument()
  })

  it('GIVEN a corrected value THEN one Extracted text column shows the fix, the AI read struck through', () => {
    inShell(<ScanReviewView scanId="s1" back={{ to: '/', label: 'Back' }} />)
    const table = screen.getByRole('table', { name: 'Extracted fields' })
    const fields = within(table)
    expect(fields.getByRole('columnheader', { name: 'Extracted text' })).toBeInTheDocument()
    expect(fields.queryByRole('columnheader', { name: 'AI read' })).toBeNull()
    expect(fields.queryByRole('columnheader', { name: 'Technician' })).toBeNull()
    expect(fields.getByText('CR 32-4-1 F')).toBeInTheDocument() // the fix
    expect(fields.getByText('CR 32-4-1 G')).toHaveClass('line-through') // what the AI read
    expect(fields.getByText('Corrected')).toBeInTheDocument()
    expect(fields.queryByText(/% confidence/)).toBeNull() // the score was for the AI's value
  })

  it('GIVEN a field marked unreadable THEN its extracted text is empty', () => {
    review = {
      ...review,
      fields: [
        {
          ...kept,
          ai_value: null,
          confidence: null,
          technician_value: null,
          verification_state: 'unreadable',
          unreadable_reason: 'label_worn',
        },
      ],
    }
    inShell(<ScanReviewView scanId="s1" back={{ to: '/', label: 'Back' }} />)
    const fields = within(screen.getByRole('table', { name: 'Extracted fields' }))
    expect(fields.getByText('—')).toBeInTheDocument()
  })

  it('GIVEN a photo that fails to load THEN a message replaces the broken image', () => {
    review = {
      ...review,
      photos: [{ photo_no: 1, url: 'http://minio/1.jpg' }] as unknown as typeof review.photos,
    }
    inShell(<ScanReviewView scanId="s1" back={{ to: '/', label: 'Back' }} />)
    expect(screen.getByRole('status')).toHaveTextContent('Loading image…')
    fireEvent.error(screen.getByAltText('Image 1 of 1'))
    expect(screen.getByRole('alert')).toHaveTextContent("We couldn't load this image")
    expect(screen.queryByAltText('Image 1 of 1')).toBeNull()
  })
})

describe('Photo viewer', () => {
  it('GIVEN photos WHEN one is clicked THEN it opens over the page, not in a new tab', () => {
    review = {
      ...review,
      photos: [
        { photo_no: 1, url: 'http://minio/1.jpg' },
        { photo_no: 2, url: 'http://minio/2.jpg' },
      ] as unknown as typeof review.photos,
    }
    inShell(<ScanReviewView scanId="s1" back={{ to: '/', label: 'Back' }} />)
    expect(document.querySelector('a[target="_blank"]')).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Open image 1 of 2' }))
    const viewer = within(screen.getByRole('dialog', { name: 'Image 1 of 2' }))
    fireEvent.click(viewer.getByRole('button', { name: 'Next image' }))
    expect(screen.getByRole('dialog', { name: 'Image 2 of 2' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Close' }))
    expect(screen.queryByRole('dialog')).toBeNull()
  })
})

describe('Resubmitted scan', () => {
  it('GIVEN revision 1 rejected and revision 2 sent back THEN Approve and Reject are offered again', async () => {
    review = {
      ...review,
      current_revision: {
        ...review.current_revision,
        revision_id: 'r2',
        revision_no: 2,
        origin: 'rejection_fix',
      },
      decisions: [
        {
          decision_id: 'd1',
          revision_id: 'r1',
          decision: 'rejected',
          reject_category: 'other',
          note: 'Wrong plate',
          decided_by_name: 'Bo Plant04',
          decider_role: 'bu_admin',
          is_current: true,
          overrides_decision_id: null,
          decided_at: '2026-10-04T12:00:00Z',
        },
      ],
    }
    inShell(<ScanReviewView scanId="s1" back={{ to: '/', label: 'Back' }} />)
    // No banner: the History timeline already tells the rejection and the fix.
    expect(screen.queryByText(/Resubmitted · revision/)).toBeNull()
    expect(screen.queryByText(/fixed it and sent it back/)).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Approve' }))
    await waitFor(() => expect(calls.decide).toHaveBeenCalled())
  })
})
