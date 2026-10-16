import { describe, expect, it } from 'vitest'
import { dateRange } from './dateRange'

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
})
