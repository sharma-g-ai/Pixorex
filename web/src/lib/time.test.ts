import { describe, expect, it } from 'vitest'
import { dateTime, timeAgo, timeLeft, waitedFor } from './time'

const now = new Date('2026-10-05T12:00:00Z')

describe('dateTime', () => {
  it('shows date, hours, minutes and seconds in the viewer’s time zone', () => {
    // Built from a local time, so the expected text holds in any time zone.
    expect(dateTime(new Date(2026, 9, 5, 9, 7, 3).toISOString())).toBe('5 Oct 09:07:03')
    expect(dateTime(new Date(2026, 10, 12, 18, 6, 42).toISOString())).toBe('12 Nov 18:06:42')
  })

  it('keeps consecutive scans apart by the second', () => {
    const first = dateTime(new Date(2026, 10, 12, 10, 30, 0).toISOString())
    const second = dateTime(new Date(2026, 10, 12, 10, 30, 5).toISOString())
    expect([first, second]).toEqual(['12 Nov 10:30:00', '12 Nov 10:30:05'])
  })
})

describe('timeAgo', () => {
  it.each([
    ['2026-10-05T11:59:30Z', 'just now'],
    ['2026-10-05T11:46:00Z', '14 min ago'],
    ['2026-10-05T09:00:00Z', '3 h ago'],
    ['2026-10-04T10:00:00Z', 'yesterday'],
    ['2026-10-02T10:00:00Z', '2 Oct'],
  ])('%s → %s', (iso, expected) => {
    expect(timeAgo(iso, now)).toBe(expected)
  })
})

describe('timeLeft', () => {
  it.each([
    ['2026-10-06T10:00:00Z', '22 h left'],
    ['2026-10-05T12:18:00Z', '18 min left'],
    ['2026-10-05T12:00:20Z', '1 min left'],
    ['2026-10-05T11:00:00Z', null],
  ])('%s → %s', (iso, expected) => {
    expect(timeLeft(iso, now)).toBe(expected)
  })
})

describe('waitedFor', () => {
  it.each([
    ['2026-10-05T11:30:00Z', 'under 1 h'],
    ['2026-10-05T07:00:00Z', '5 h'],
    ['2026-10-04T10:00:00Z', '1 day'],
    ['2026-09-26T10:00:00Z', '9 days'],
  ])('%s → %s', (iso, expected) => {
    expect(waitedFor(iso, now)).toBe(expected)
  })
})
