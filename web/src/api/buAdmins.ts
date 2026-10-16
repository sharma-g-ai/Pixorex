import { useQuery } from '@tanstack/react-query'
import { businessUnitsQueryKey } from './businessUnits'
import { api, unwrap } from './client'
import { invitesKey } from './invites'
import { useRefreshingMutation } from './useRefreshingMutation'
import type { components } from './generated/s2'

export type BuAdmin = components['schemas']['BuAdmin']

const buAdminsKey = ['bu-admins'] as const

/** Contract 1.15 GET /bu-admins (EA): every BU Admin and the units they run. */
export function useBuAdmins() {
  return useQuery({
    queryKey: buAdminsKey,
    queryFn: async () => unwrap(await api.GET('/bu-admins')).items,
  })
}

/** After a change, the admin list, the unit cards and the invites all show who runs what. */
const adminChangeRefreshes = [buAdminsKey, businessUnitsQueryKey, invitesKey]

/** Contract 1.16: the full list of units this BU Admin runs. */
export function useSetBuAdminUnits() {
  return useRefreshingMutation(
    async ({ userId, buIds }: { userId: string; buIds: string[] }) =>
      unwrap(
        await api.PUT('/bu-admins/{userId}/business-units', {
          params: { path: { userId } },
          body: { bu_ids: buIds },
        }),
      ),
    adminChangeRefreshes,
  )
}

/**
 * Contract 1.17: removes the BU Admin from some or all of their units, optionally
 * inviting a replacement for those units. The account and history are kept.
 */
export function useRemoveBuAdmin() {
  return useRefreshingMutation(
    async ({
      userId,
      buIds,
      replacementEmail,
    }: {
      userId: string
      buIds: string[]
      replacementEmail?: string
    }) =>
      unwrap(
        await api.POST('/bu-admins/{userId}/remove', {
          params: { path: { userId } },
          body: replacementEmail
            ? { bu_ids: buIds, replacement_invite_email: replacementEmail }
            : { bu_ids: buIds },
        }),
      ),
    adminChangeRefreshes,
  )
}
