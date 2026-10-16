import { useQuery } from '@tanstack/react-query'
import { api, unwrap } from './client'
import type { components } from './generated/s4'
import { useRefreshingMutation } from './useRefreshingMutation'

export type Notification = components['schemas']['Notification']
export type NotificationKind = components['schemas']['NotificationKind']

const notificationsKey = ['notifications'] as const

/** Contract 3.19: the signed-in user's alerts, newest first, with the unread count. */
export function useNotifications() {
  return useQuery({
    queryKey: notificationsKey,
    queryFn: async () => unwrap(await api.GET('/me/notifications')),
    refetchInterval: 60_000,
  })
}

/** Contract 3.20. */
export function useMarkNotificationRead() {
  return useRefreshingMutation(
    async (notificationId: string) =>
      unwrap(
        await api.POST('/me/notifications/{notificationId}/read', {
          params: { path: { notificationId } },
        }),
      ),
    [notificationsKey],
  )
}

/** Contract 3.21. */
export function useMarkAllNotificationsRead() {
  return useRefreshingMutation(
    async () => unwrap(await api.POST('/me/notifications/read-all')),
    [notificationsKey],
  )
}
