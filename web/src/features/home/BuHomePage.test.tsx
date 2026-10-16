import { render, screen, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Invite } from '../../api/invites'
import type { Me } from '../../api/me'
import type { Batch, QueueCounts } from '../../api/review'
import { DashboardContext } from '../../app/DashboardContext'
import { BuHomePage } from './BuHomePage'
import { buNeedsYou, calmSummary, greeting } from './homeRules'

let counts: QueueCounts
let batches: Batch[] = []
let invites: Invite[] = []
vi.mock('../../api/review', () => ({
  useReviewQueue: () => ({ data: { counts, items: [] }, isPending: false }),
  useBatches: () => ({ data: batches }),
  useTechnicianDecisions: () => ({ data: decisions, isPending: false }),
}))
vi.mock('../../api/auditLog', () => ({
  useAuditLog: () => ({
    isPending: false,
    items: [
      {
        occurred_at: '2026-10-05T09:12:00Z',
        actor_type: 'user',
        actor_name: 'M. Diaz',
        bu_name: 'Plant 04',
        category: 'review',
        summary: 'Submitted Powder Booth Nameplate · REC-91004',
        action: 'scan.submitted',
        object_type: 'scan',
      },
    ],
  }),
}))
let decisions: unknown[] = []
vi.mock('../../api/invites', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useInvites: () => ({ data: invites }),
}))

const now = new Date('2026-10-05T08:00:00Z')
const stuckBatch = {
  batch_id: 'b14',
  batch_no: 'B-14',
  assigned_to_name: 'T. Nguyen',
  created_by_name: 'R. K',
  scan_count: 30,
  decided_count: 0,
  created_at: '2026-10-03T08:00:00Z',
  reminded_at: null,
  status: 'active',
} as Batch
const expiredInvite = {
  invite_id: 'i1',
  email: 'd.ross@ppg.com',
  status: 'expired',
  expires_at: '2026-10-04T08:00:00Z',
} as Invite

beforeEach(() => {
  decisions = []
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(now)
  counts = {
    waiting: 23,
    over_1d: 9,
    over_1w: 2,
    delegated: 60,
    decided_by_technicians: 3,
    approved_this_week: 112,
  }
  batches = [stuckBatch]
  invites = [expiredInvite]
})
afterEach(() => vi.useRealTimers())

const page = () =>
  render(
    <MemoryRouter>
      <DashboardContext.Provider
        value={{
          me: { full_name: 'Robert Kowalski' } as Me,
          role: 'bu_admin',
          unit: { bu_id: 'p04', name: 'Plant 04', role: 'bu_admin', is_primary: true },
        }}
      >
        <BuHomePage />
      </DashboardContext.Provider>
    </MemoryRouter>,
  )

describe('home rules', () => {
  it('greets by first name and time of day', () => {
    expect(greeting('Robert Kowalski', new Date(2026, 9, 5, 9))).toBe('Good morning, Robert')
    expect(greeting('Robert Kowalski', new Date(2026, 9, 5, 15))).toBe('Good afternoon, Robert')
  })

  it('lists only what needs attention', () => {
    const quiet = { ...counts, over_1d: 0, over_1w: 0 }
    expect(buNeedsYou(quiet, [], [], now)).toEqual([])
    expect(buNeedsYou(counts, [stuckBatch], [expiredInvite], now).map((i) => i.title)).toEqual([
      'Waiting over a week',
      'Waiting over a day',
      'Batch with no progress',
      'Invite expired',
    ])
    expect(calmSummary(6)).toBe('6 scans are waiting review, all under 24 hours. No stuck batches.')
  })
})

describe('BU Home (canvas BU 03)', () => {
  it('GIVEN long waits, a stuck batch and an expired invite THEN shows each with where to act', () => {
    page()
    expect(screen.getByRole('link', { name: /23\s*waiting review/ })).toHaveAttribute(
      'href',
      '/review-queue',
    )
    expect(screen.getByText('approved this week')).toBeInTheDocument()
    expect(screen.getByText('112')).toBeInTheDocument()
    const batch = within(screen.getByRole('region', { name: 'Batch with no progress' }))
    expect(batch.getByText('B-14 · T. Nguyen · 0 of 30')).toBeInTheDocument()
    expect(batch.getByRole('link', { name: 'Remind or take back →' })).toHaveAttribute(
      'href',
      '/delegations',
    )
    const invite = within(screen.getByRole('region', { name: 'Invite expired' }))
    expect(invite.getByRole('link', { name: 'Resend →' })).toHaveAttribute('href', '/technicians')
    expect(
      screen.getByText('waiting over 24 h · also with your Enterprise Admin'),
    ).toBeInTheDocument()
  })

  it('GIVEN something needs the admin THEN the 3 latest technician decisions show, each with Check', () => {
    decisions = ['d1', 'd2', 'd3', 'd4'].map((id, i) => ({
      decision_id: id,
      scan_id: `s${i}`,
      record_no: `REC-9013${i}`,
      decided_by_name: i === 2 ? 'A. Patel' : 'T. Nguyen',
      decision: i === 2 ? 'rejected' : 'approved',
      reject_category: i === 2 ? 'image_unclear' : null,
      decided_at: '2026-10-05T06:00:00Z',
      overridden: false,
    }))
    page()
    expect(screen.getByRole('link', { name: 'All decisions' })).toHaveAttribute(
      'href',
      '/delegations?tab=decided',
    )
    expect(screen.getAllByRole('link', { name: 'Check' })).toHaveLength(3)
    expect(screen.getByText('Rejected by A. Patel · Image unclear')).toBeInTheDocument()
    expect(screen.getAllByRole('link', { name: 'Check' })[0]).toHaveAttribute(
      'href',
      '/review-queue/s0',
    )
    expect(screen.queryByText('Recent activity in Plant 04')).not.toBeInTheDocument()
  })

  it('GIVEN nothing urgent THEN says so', () => {
    counts = {
      waiting: 6,
      over_1d: 0,
      over_1w: 0,
      delegated: 0,
      decided_by_technicians: 0,
      approved_this_week: 15,
    }
    batches = []
    invites = []
    page()
    expect(screen.getByText('Nothing urgent in Plant 04')).toBeInTheDocument()
    expect(screen.getByText('waiting over 24 h')).toBeInTheDocument()
    // Canvas BU 03 (Plant 05): recent activity instead of technician decisions.
    expect(screen.getByText('Recent activity in Plant 04')).toBeInTheDocument()
    expect(screen.getByText('Submitted Powder Booth Nameplate · REC-91004')).toBeInTheDocument()
    expect(screen.queryByText('Recent decisions by technicians')).not.toBeInTheDocument()
  })
})
