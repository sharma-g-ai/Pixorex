import { api, unwrap } from './client'
import type { components, operations } from './generated/s4'
import { usePagedList } from './paging'

export type ScanRow = components['schemas']['ScanRow']
export type ScanFilters = Omit<
  NonNullable<operations['listAllScans']['parameters']['query']>,
  'cursor' | 'limit'
>

/** Contract 3.18: every scan the caller may see (EA: all units), newest first. */
export function useAllScans(filters: ScanFilters) {
  return usePagedList(['scans', filters], async (cursor) =>
    unwrap(await api.GET('/scans', { params: { query: { ...filters, cursor } } })),
  )
}
