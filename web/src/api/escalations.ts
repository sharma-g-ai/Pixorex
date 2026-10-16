import { api, unwrap } from './client'
import type { components } from './generated/s4'
import { usePagedList } from './paging'
import { useRefreshingMutation } from './useRefreshingMutation'

export type Escalation = components['schemas']['Escalation']

/** Contract 3.16: open escalations, all units or one. */
export function useEscalations(buId?: string) {
  return usePagedList(['escalations', buId ?? 'all'], async (cursor) =>
    unwrap(
      await api.GET('/escalations', {
        params: { query: { open: true, ...(buId ? { bu_id: buId } : {}), cursor } },
      }),
    ),
  )
}

/** Contract 3.17: email and dashboard reminder to the unit's BU Admin (409 no-bu-admin). */
export function useRemindBuAdmin() {
  return useRefreshingMutation(
    async (buId: string) =>
      unwrap(
        await api.POST('/business-units/{buId}/escalations/remind', {
          params: { path: { buId } },
        }),
      ),
    [['escalations'], ['audit-log']],
  )
}
