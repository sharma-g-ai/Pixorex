import { describe, expect, it } from 'vitest'
import {
  ALL_STATUSES,
  DEFAULT_FILTERS,
  filtersFromParams,
  isFiltered,
  paramsFromFilters,
  requestFilters,
} from './queueFilters'

const read = (query: string) => filtersFromParams(new URLSearchParams(query))

describe('queue filters in the address', () => {
  it('GIVEN no parameters THEN the queue opens on waiting scans, oldest first', () => {
    expect(read('')).toEqual(DEFAULT_FILTERS)
    expect(isFiltered(read(''))).toBe(false)
  })

  it('GIVEN Home’s approved-this-week link THEN opens approved scans from that Monday', () => {
    expect(read('status=approved&from=2026-11-16')).toEqual({
      ...DEFAULT_FILTERS,
      status: ['approved'],
      from: '2026-11-16',
    })
  })

  it('GIVEN several statuses, schemas and people THEN keeps them all', () => {
    expect(
      read('status=rejected&status=waiting&schema=t1&schema=t2&by=u1&sort=newest_first'),
    ).toEqual({
      status: ['waiting', 'rejected'], // always in the same order
      schemas: ['t1', 't2'],
      capturedBy: ['u1'],
      from: '',
      to: '',
      search: '',
      decidedFrom: '',
      sort: 'newest_first',
    })
  })

  it('GIVEN status=any THEN the status filter is cleared', () => {
    expect(read('status=any').status).toEqual([])
    expect(isFiltered(read('status=any'))).toBe(true)
  })

  it('GIVEN rubbish THEN falls back to the opening view, not a broken one', () => {
    expect(read('status=banana').status).toEqual(['waiting'])
    expect(read('from=yesterday&to=2026-13').from).toBe('')
    expect(read('from=yesterday&to=2026-13').to).toBe('')
    expect(read('sort=sideways').sort).toBe('') // the default order
  })

  it('GIVEN any filters THEN writing then reading them gives the same filters', () => {
    const cases = [
      DEFAULT_FILTERS,
      { ...DEFAULT_FILTERS, status: [] },
      { ...DEFAULT_FILTERS, status: ALL_STATUSES },
      { ...DEFAULT_FILTERS, status: ['approved' as const], from: '2026-11-01', to: '2026-11-18' },
      { ...DEFAULT_FILTERS, schemas: ['a', 'b'], capturedBy: ['x'], sort: 'newest_first' as const },
    ]
    for (const filters of cases) {
      expect(filtersFromParams(paramsFromFilters(filters))).toEqual(filters)
    }
  })

  it('GIVEN the opening view THEN the address stays clean', () => {
    expect(paramsFromFilters(DEFAULT_FILTERS).toString()).toBe('')
  })

  it('GIVEN the status filter cleared THEN the API is asked for all three statuses', () => {
    // The API's own default is waiting, so "no filter" must say so explicitly.
    expect(requestFilters({ ...DEFAULT_FILTERS, status: [] }).status).toEqual(ALL_STATUSES)
    expect(requestFilters({ ...DEFAULT_FILTERS, status: ['approved'] }).status).toEqual([
      'approved',
    ])
  })
})
