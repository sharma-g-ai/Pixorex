import { useMutation, useQuery } from '@tanstack/react-query'
import { api, unwrap } from './client'
import type { components } from './generated/s2'

export type InvitePreview = components['schemas']['InvitePreview']

/**
 * Contract 1.6: read an invite before accepting. The token travels in the body, never a URL.
 * Not retried and not cached: a wrong or used link should answer once, and the token should
 * not outlive the page.
 */
export function useInvitePreview(token: string) {
  return useQuery({
    queryKey: ['invite-preview', token],
    queryFn: async () => unwrap(await api.POST('/invites/preview', { body: { token } })),
    enabled: token !== '',
    retry: false,
    gcTime: 0,
    staleTime: Infinity,
  })
}

/** Contract 1.7: accept; Keycloak then sends and checks the code at first sign-in (D-08). */
export function useAcceptInvite() {
  return useMutation({
    mutationFn: async (body: { token: string; full_name: string }) =>
      unwrap(await api.POST('/invites/accept', { body })),
  })
}
