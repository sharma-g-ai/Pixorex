import { describe, expect, it } from 'vitest'
import {
  addDays,
  dateTime,
  dayLabel,
  istDay,
  istMonday,
  istParts,
  timeAgo,
  timeLeft,
  waitedFor,
} from './time'

const now = new Date('2026-10-05T12:00:00Z')

describe('dateTime', () => {
  it('shows date, hours, minutes and seconds in Indian time, whatever the viewer’s zone', () => {
    // IST is UTC+5:30.
    expect(dateTime('2026-10-05T03:37:03Z')).toBe('5 Oct 09:07:03')
    expect(dateTime('2026-11-12T12:36:42Z')).toBe('12 Nov 18:06:42')
  })

  it('moves to the next day after 18:30 UTC', () => {
    expect(dateTime('2026-11-12T18:29:59Z')).toBe('12 Nov 23:59:59')
    expect(dateTime('2026-11-12T18:30:00Z')).toBe('13 Nov 00:00:00')
  })

  it('keeps consecutive scans apart by the second', () => {
    const first = dateTime('2026-11-12T05:00:00Z')
    const second = dateTime('2026-11-12T05:00:05Z')
    expect([first, second]).toEqual(['12 Nov 10:30:00', '12 Nov 10:30:05'])
  })
})

describe('Indian calendar days', () => {
  it('istDay is the day in India, not in UTC', () => {
    expect(istDay(new Date('2026-11-17T18:29:00Z'))).toBe('2026-11-17')
    expect(istDay(new Date('2026-11-17T18:30:00Z'))).toBe('2026-11-18')
  })

  it('istParts gives the hour and the weekday in India', () => {
    expect(istParts(new Date('2026-11-18T03:30:00Z'))).toMatchObject({ hour: 9, weekday: 2 })
    expect(istParts(new Date('2026-11-22T18:30:00Z'))).toMatchObject({ hour: 0, weekday: 0 })
  })

  it('a week starts on Monday 00:00 IST', () => {
    expect(istMonday(new Date('2026-11-18T10:00:00Z'))).toBe('2026-11-16') // a Wednesday
    expect(istMonday(new Date('2026-11-16T00:00:00Z'))).toBe('2026-11-16') // Monday 05:30 IST
    // Sunday 22 Nov 19:00 UTC is already Monday 23 Nov 00:30 in India.
    expect(istMonday(new Date('2026-11-22T19:00:00Z'))).toBe('2026-11-23')
    // Sunday 22 Nov 18:00 UTC is still Sunday 23:30 in India: the week began on the 16th.
    expect(istMonday(new Date('2026-11-22T18:00:00Z'))).toBe('2026-11-16')
  })

  it('addDays crosses months and years', () => {
    expect(addDays('2026-11-30', 1)).toBe('2026-12-01')
    expect(addDays('2026-01-01', -1)).toBe('2025-12-31')
  })

  it('dayLabel writes a picked day as "18 Nov"', () => {
    expect(dayLabel('2026-11-18')).toBe('18 Nov')
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
