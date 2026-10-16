import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { getDeviceId } from '../lib/deviceId'
import { api, unwrap } from './client'
import type { components } from './generated/s2'

export type Me = components['schemas']['Me']
export type UnitRole = components['schemas']['UnitRole']

export const meQueryKey = ['me'] as const

/** Contract 1.1 GET /me: the signed-in user, their tenant and units. */
export function useMe() {
  return useQuery({
    queryKey: meQueryKey,
    queryFn: async () => unwrap(await api.GET('/me')),
  })
}

/** Contract 1.2 PUT /me/active-unit: switch unit without a new sign-in. */
export function useSwitchUnit() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async (buId: string) =>
      unwrap(
        await api.PUT('/me/active-unit', {
          params: { header: { 'X-Device-Id': getDeviceId() } },
          body: { bu_id: buId },
        }),
      ),
    onSuccess: async (me) => {
      queryClient.setQueryData(meQueryKey, me)
      // Everything else on screen belongs to the old unit.
      await queryClient.invalidateQueries({ predicate: (q) => q.queryKey[0] !== meQueryKey[0] })
    },
  })
}
