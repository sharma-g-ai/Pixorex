import type { QueueFilters, QueueStatus } from '../../api/review'

export const ALL_STATUSES: QueueStatus[] = ['waiting', 'approved', 'rejected']

export const statusLabels: Record<QueueStatus, string> = {
  waiting: 'Under Review',
  approved: 'Approved',
  rejected: 'Rejected',
}

/** The queue opens on the scans still waiting for a decision. */
export const DEFAULT_FILTERS: QueueFilters = {
  status: ['waiting'],
  schemas: [],
  capturedBy: [],
  from: '',
  to: '',
  search: '',
  decidedFrom: '',
  sort: '',
}

const DAY = /^\d{4}-\d{2}-\d{2}$/

/**
 * The filters held in the page address, so a link such as Home's "approved this week"
 * (?status=approved&from=2026-11-16) opens the queue already filtered, and a reload keeps it.
 *   status   repeated; absent = waiting; "any" = the status filter was cleared (all three)
 *   schema   repeated schema ids        by   repeated technician ids
 *   from, to YYYY-MM-DD (captured days)  q Scan ID typed in the search box
 *   decided YYYY-MM-DD (decided from)   sort newest_first or oldest_first (absent: default order)
 */
export function filtersFromParams(params: URLSearchParams): QueueFilters {
  let status = DEFAULT_FILTERS.status
  if (params.has('status')) {
    const asked = params.getAll('status')
    status = asked.includes('any') ? [] : ALL_STATUSES.filter((s) => asked.includes(s))
    if (status.length === 0 && !asked.includes('any')) status = DEFAULT_FILTERS.status
  }
  const day = (key: string) => {
    const value = params.get(key) ?? ''
    return DAY.test(value) ? value : ''
  }
  return {
    status,
    schemas: params.getAll('schema'),
    capturedBy: params.getAll('by'),
    from: day('from'),
    to: day('to'),
    search: (params.get('q') ?? '').slice(0, 40),
    decidedFrom: day('decided'),
    sort:
      params.get('sort') === 'newest_first'
        ? 'newest_first'
        : params.get('sort') === 'oldest_first'
          ? 'oldest_first'
          : '',
  }
}

export function paramsFromFilters(filters: QueueFilters): URLSearchParams {
  const params = new URLSearchParams()
  const isDefault = filters.status.length === 1 && filters.status[0] === DEFAULT_FILTERS.status[0]
  if (filters.status.length === 0) params.set('status', 'any')
  else if (!isDefault) filters.status.forEach((s) => params.append('status', s))
  filters.schemas.forEach((s) => params.append('schema', s))
  filters.capturedBy.forEach((s) => params.append('by', s))
  if (filters.from) params.set('from', filters.from)
  if (filters.to) params.set('to', filters.to)
  if (filters.search) params.set('q', filters.search)
  if (filters.decidedFrom) params.set('decided', filters.decidedFrom)
  if (filters.sort) params.set('sort', filters.sort)
  return params
}

/** The statuses to ask the API for: with none picked, all three (the API's own default is waiting). */
export function statusesToAsk(filters: QueueFilters): QueueStatus[] {
  return filters.status.length ? filters.status : ALL_STATUSES
}

/** The queue as it is read from the API, with the status filter widened as above. */
export function requestFilters(filters: QueueFilters): QueueFilters {
  return { ...filters, status: statusesToAsk(filters) }
}

/** Anything narrowing the list beyond the opening view? (Decides if "Clear all" is useful.) */
export function isFiltered(filters: QueueFilters): boolean {
  return (
    filters.status.join() !== DEFAULT_FILTERS.status.join() ||
    filters.schemas.length > 0 ||
    filters.capturedBy.length > 0 ||
    filters.from !== '' ||
    filters.to !== '' ||
    filters.search !== '' ||
    filters.decidedFrom !== ''
  )
}
