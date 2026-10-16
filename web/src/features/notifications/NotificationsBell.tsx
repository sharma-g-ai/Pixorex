import { useState } from 'react'
import { useNavigate } from 'react-router'
import {
  useMarkAllNotificationsRead,
  useMarkNotificationRead,
  useNotifications,
  type Notification,
} from '../../api/notifications'
import type { DashboardRole } from '../../app/access'
import { Button } from '../../components/Button'
import { Icon } from '../../components/icons'
import { timeAgo } from '../../lib/time'
import { notificationPath } from './notificationLinks'

/** The bell in the page header and its alerts panel (canvas EA 24, BU 04; contracts 3.19–3.21). */
export function NotificationsBell({ role }: { role: DashboardRole }) {
  const [open, setOpen] = useState(false)
  const notifications = useNotifications()
  const unread = notifications.data?.unread_count ?? 0

  return (
    <div
      className="relative"
      onKeyDown={(e) => {
        if (e.key === 'Escape') setOpen(false)
      }}
    >
      <button
        type="button"
        aria-label={unread ? `Notifications, ${unread} unread` : 'Notifications'}
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
        className="relative flex size-9.5 items-center justify-center rounded-lg border border-line text-ink-muted hover:border-line-strong"
      >
        <Icon name="bell" size={17} />
        {unread > 0 && (
          <span className="absolute -top-1.25 -right-1.5 flex h-4.25 min-w-4.25 items-center justify-center rounded-full bg-danger px-1 text-label font-bold text-surface">
            {unread}
          </span>
        )}
      </button>
      {open && (
        <NotificationsPanel
          items={notifications.data?.items ?? []}
          loading={notifications.isPending}
          role={role}
          onClose={() => setOpen(false)}
        />
      )}
    </div>
  )
}

interface PanelProps {
  items: Notification[]
  loading: boolean
  role: DashboardRole
  onClose: () => void
}

function NotificationsPanel({ items, loading, role, onClose }: PanelProps) {
  const navigate = useNavigate()
  const markRead = useMarkNotificationRead()
  const markAll = useMarkAllNotificationsRead()

  const openItem = (n: Notification) => {
    if (!n.read_at) markRead.mutate(n.notification_id)
    onClose()
    void navigate(notificationPath(n.kind, role))
  }

  return (
    <>
      <button
        type="button"
        aria-label="Close notifications"
        className="fixed inset-0 z-10 cursor-default"
        onClick={onClose}
      />
      <section
        aria-label="Notifications"
        className="absolute top-11 right-0 z-20 w-95 overflow-hidden rounded-xl border border-line bg-surface shadow-lg"
      >
        <div className="flex items-center justify-between border-b border-line px-4 py-3">
          <h2 className="text-card-title font-bold">Notifications</h2>
          <Button
            variant="link"
            disabled={markAll.isPending || items.every((n) => n.read_at)}
            onClick={() => markAll.mutate(undefined)}
          >
            Mark all read
          </Button>
        </div>
        {loading ? (
          <p className="px-4 py-6 text-body text-ink-muted">Loading…</p>
        ) : items.length === 0 ? (
          <p className="px-4 py-6 text-body text-ink-muted">You're all caught up.</p>
        ) : (
          <ul className="max-h-105 overflow-y-auto">
            {items.map((n) => (
              <li key={n.notification_id} className="border-b border-line-soft last:border-b-0">
                <button
                  type="button"
                  onClick={() => openItem(n)}
                  className={`flex w-full gap-3 px-4 py-3 text-left hover:bg-page ${n.read_at ? '' : 'bg-info-soft'}`}
                >
                  <span
                    aria-hidden="true"
                    className={`mt-1.5 size-2 shrink-0 rounded-full ${n.read_at ? 'bg-transparent' : 'bg-brand-accent'}`}
                  />
                  <span className="min-w-0">
                    <span className="block text-body-sm font-semibold">{n.title}</span>
                    {n.body && <span className="block text-small text-ink-muted">{n.body}</span>}
                    <span className="block text-meta text-ink-subtle">
                      {timeAgo(n.created_at)}
                      {n.emailed_at && ' · also emailed'}
                    </span>
                  </span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>
    </>
  )
}
