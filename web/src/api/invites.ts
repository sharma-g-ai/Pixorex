import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api, unwrap } from './client'
import type { components } from './generated/s2'

export type Invite = components['schemas']['Invite']
export type Role = components['schemas']['Role']

export const invitesKey = ['invites'] as const

/**
 * Contract 1.9 GET /invites, all statuses. A BU Admin passes their unit (technician
 * invites); the EA passes none (BU Admin invites across all units).
 */
export function useInvites(buId?: string) {
  return useQuery({
    queryKey: [...invitesKey, buId ?? 'all'],
    queryFn: async () =>
      unwrap(await api.GET('/invites', { params: { query: buId ? { bu_id: buId } : {} } })).items,
  })
}

export interface CreateInvite {
  role: Role
  email: string
  bu_ids: string[]
}

/** Contract 1.8 POST /invites: one invite row per unit, link valid 24 hours. */
export function useCreateInvite() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ body, idempotencyKey }: { body: CreateInvite; idempotencyKey: string }) =>
      unwrap(
        await api.POST('/invites', {
          params: { header: { 'Idempotency-Key': idempotencyKey } },
          body,
        }),
      ),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: invitesKey }),
  })
}

/** Contract 1.10: new link, new 24 hours; the old link stops working. */
export function useResendInvite() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async (inviteId: string) =>
      unwrap(await api.POST('/invites/{inviteId}/resend', { params: { path: { inviteId } } })),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: invitesKey }),
  })
}

/** Contract 1.11: cancels a pending invite, or removes an expired one from the list. */
export function useCancelInvite() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async (inviteId: string) =>
      unwrap(await api.POST('/invites/{inviteId}/cancel', { params: { path: { inviteId } } })),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: invitesKey }),
  })
}
