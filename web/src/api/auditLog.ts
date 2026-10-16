import { api, unwrap } from './client'
import type { components, operations } from './generated/s4'
import { usePagedList } from './paging'

export type AuditEntry = components['schemas']['AuditEntry']
export type AuditCategory = AuditEntry['category']
export type AuditFilters = Omit<
  NonNullable<operations['listAuditLog']['parameters']['query']>,
  'cursor' | 'limit'
>

/** Contract 3.22: the insert-only audit log, newest first. There is no write endpoint. */
export function useAuditLog(filters: AuditFilters) {
  return usePagedList(['audit-log', filters], async (cursor) =>
    unwrap(await api.GET('/audit-log', { params: { query: { ...filters, cursor } } })),
  )
}
