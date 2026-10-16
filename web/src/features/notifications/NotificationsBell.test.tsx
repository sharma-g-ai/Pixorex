import { fireEvent, render, screen } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { notificationPath } from './notificationLinks'
import { NotificationsBell } from './NotificationsBell'

const markRead = vi.fn()
const markAll = vi.fn()
vi.mock('../../api/notifications', () => ({
  useNotifications: () => ({
    isPending: false,
    data: {
      unread_count: 1,
      items: [
        {
          notification_id: 'n1',
          kind: 'scans_escalated',
          title: '30 scans waiting over 24 hours',
          body: 'Plant 07 · 12, Plant 11 · 9 · review or delegate',
          bu_id: null,
          object_type: 'escalation',
          object_id: 'x',
          created_at: '2026-10-05T10:00:00Z',
          read_at: null,
          emailed_at: '2026-10-05T10:01:00Z',
        },
        {
          notification_id: 'n2',
          kind: 'export_ready',
          title: 'Your export is ready',
          body: null,
          bu_id: null,
          object_type: 'export_job',
          object_id: 'y',
          created_at: '2026-10-05T09:00:00Z',
          read_at: '2026-10-05T09:30:00Z',
          emailed_at: null,
        },
      ],
    },
  }),
  useMarkNotificationRead: () => ({ mutate: markRead }),
  useMarkAllNotificationsRead: () => ({ mutate: markAll, isPending: false }),
}))

beforeEach(() => {
  markRead.mockReset()
  markAll.mockReset()
})

const bell = () =>
  render(
    <MemoryRouter initialEntries={['/overview']}>
      <Routes>
        <Route path="/overview" element={<NotificationsBell role="enterprise_admin" />} />
        <Route path="/escalations" element={<h1>Escalated scans page</h1>} />
      </Routes>
    </MemoryRouter>,
  )

describe('Notifications (contracts 3.19–3.21)', () => {
  it('sends each alert to the right page for the role', () => {
    expect(notificationPath('scans_escalated', 'enterprise_admin')).toBe('/escalations')
    expect(notificationPath('scans_escalated', 'bu_admin')).toBe('/review-queue')
    expect(notificationPath('batch_no_progress', 'bu_admin')).toBe('/delegations')
    expect(notificationPath('invite_expired', 'bu_admin')).toBe('/technicians')
  })

  it('GIVEN an unread alert WHEN opened THEN marks it read and goes to its page', () => {
    bell()
    fireEvent.click(screen.getByRole('button', { name: 'Notifications, 1 unread' }))
    fireEvent.click(screen.getByRole('button', { name: /30 scans waiting over 24 hours/ }))
    expect(markRead).toHaveBeenCalledWith('n1')
    expect(screen.getByRole('heading', { name: 'Escalated scans page' })).toBeInTheDocument()
  })

  it('GIVEN Mark all read THEN contract 3.21 is called', () => {
    bell()
    fireEvent.click(screen.getByRole('button', { name: 'Notifications, 1 unread' }))
    fireEvent.click(screen.getByRole('button', { name: 'Mark all read' }))
    expect(markAll).toHaveBeenCalled()
  })

  it('GIVEN the panel is open WHEN Escape is pressed THEN it closes', () => {
    bell()
    const button = screen.getByRole('button', { name: 'Notifications, 1 unread' })
    fireEvent.click(button)
    expect(screen.getByRole('region', { name: 'Notifications' })).toBeInTheDocument()
    fireEvent.keyDown(button, { key: 'Escape' })
    expect(screen.queryByRole('region', { name: 'Notifications' })).not.toBeInTheDocument()
  })

  it('GIVEN an alert body THEN it is the second line; "also emailed" only when emailed_at is set', () => {
    bell()
    fireEvent.click(screen.getByRole('button', { name: 'Notifications, 1 unread' }))
    const escalated = screen.getByRole('button', { name: /30 scans waiting over 24 hours/ })
    expect(escalated).toHaveTextContent('Plant 07 · 12, Plant 11 · 9 · review or delegate')
    expect(escalated).toHaveTextContent('also emailed')
    expect(screen.getByRole('button', { name: /Your export is ready/ })).not.toHaveTextContent(
      'also emailed',
    )
  })
})
