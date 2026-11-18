import { describe, expect, it } from 'vitest'
import { dateRange } from './dateRange'
import { exportFileName } from './download'

const now = new Date('2026-10-05T12:00:00Z')

describe('dateRange', () => {
  it('GIVEN today THEN from and to are the same day', () => {
    expect(dateRange('today', now)).toEqual({ from: '2026-10-05', to: '2026-10-05' })
  })

  it('GIVEN last 7 days THEN includes today and the 6 days before', () => {
    expect(dateRange('7d', now)).toEqual({ from: '2026-09-29', to: '2026-10-05' })
  })

  it('GIVEN last 30 days THEN crosses the month', () => {
    expect(dateRange('30d', now).from).toBe('2026-09-06')
  })

  it('GIVEN 20:00 UTC (already tomorrow 01:30 in India) THEN "today" is the Indian day', () => {
    // In UTC this would still be 5 Oct; in India it is 6 Oct, so the range must end on the 6th.
    const lateEvening = new Date('2026-10-05T20:00:00Z')
    expect(dateRange('today', lateEvening)).toEqual({ from: '2026-10-06', to: '2026-10-06' })
    expect(dateRange('7d', lateEvening).from).toBe('2026-09-30')
  })

  it('GIVEN 18:29 UTC (23:59 IST) THEN it is still the same Indian day', () => {
    expect(dateRange('today', new Date('2026-10-05T18:29:00Z')).to).toBe('2026-10-05')
    expect(dateRange('today', new Date('2026-10-05T18:30:00Z')).to).toBe('2026-10-06')
  })
})

describe('export file name', () => {
  it('is dated by the Indian day', () => {
    expect(exportFileName('scans', new Date('2026-10-05T12:00:00Z'))).toBe(
      'pixorex-scans-2026-10-05.csv',
    )
    expect(exportFileName('audit_log', new Date('2026-10-05T20:00:00Z'))).toBe(
      'pixorex-audit-log-2026-10-06.csv',
    )
  })
})
