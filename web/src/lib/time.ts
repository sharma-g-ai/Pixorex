const MINUTE = 60_000
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR

/** Every time shown, and every day filter, follows Indian time whatever the viewer's zone
 * (decision of 18 Nov 2026). The API stores UTC; this is only how it is read. */
export const TIME_ZONE = 'Asia/Kolkata'

/** Parts of an instant on the Indian clock, e.g. { year: 2026, month: 11, day: 18, hour: 9 }. */
export function istParts(d: Date): {
  year: number
  month: number
  day: number
  hour: number
  weekday: number
} {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: TIME_ZONE,
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
    hour: 'numeric',
    hourCycle: 'h23',
    weekday: 'short',
  }).formatToParts(d)
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? ''
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
  return {
    year: Number(get('year')),
    month: Number(get('month')),
    day: Number(get('day')),
    hour: Number(get('hour')),
    weekday: weekdays.indexOf(get('weekday')),
  }
}

/** A day as YYYY-MM-DD on the Indian calendar (the format of the API's from/to). */
export function istDay(d: Date = new Date()): string {
  const { year, month, day } = istParts(d)
  return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`
}

/** A YYYY-MM-DD day moved by whole days. */
export function addDays(day: string, days: number): string {
  const d = new Date(`${day}T00:00:00Z`)
  d.setUTCDate(d.getUTCDate() + days)
  return d.toISOString().slice(0, 10)
}

/** The Monday of the current week on the Indian calendar (a week starts Monday 00:00 IST). */
export function istMonday(d: Date = new Date()): string {
  return addDays(istDay(d), -istParts(d).weekday)
}

/** "just now", "14 min ago", "3 h ago", "yesterday", or a date like "2 Oct". */
export function timeAgo(iso: string, now: Date = new Date()): string {
  const diff = now.getTime() - new Date(iso).getTime()
  if (diff < MINUTE) return 'just now'
  if (diff < HOUR) return `${Math.floor(diff / MINUTE)} min ago`
  if (diff < DAY) return `${Math.floor(diff / HOUR)} h ago`
  if (diff < 2 * DAY) return 'yesterday'
  return shortDate(iso)
}

/** A date like "4 Oct". */
export function shortDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'short',
    timeZone: TIME_ZONE,
  })
}

/** "22 h left", "18 min left"; null once the time has passed. */
export function timeLeft(iso: string, now: Date = new Date()): string | null {
  const diff = new Date(iso).getTime() - now.getTime()
  if (diff <= 0) return null
  if (diff < HOUR) return `${Math.max(1, Math.ceil(diff / MINUTE))} min left`
  return `${Math.floor(diff / HOUR)} h left`
}

/** How long something has waited: "under 1 h", "5 h", "1 day", "9 days". */
export function waitedFor(iso: string, now: Date = new Date()): string {
  const diff = now.getTime() - new Date(iso).getTime()
  if (diff < HOUR) return 'under 1 h'
  if (diff < DAY) return `${Math.floor(diff / HOUR)} h`
  const days = Math.floor(diff / DAY)
  return `${days} ${days === 1 ? 'day' : 'days'}`
}

/** Whole days since a time (0 for under a day). */
export function daysSince(iso: string, now: Date = new Date()): number {
  return Math.floor((now.getTime() - new Date(iso).getTime()) / DAY)
}

/** An exact time in Indian time: "4 Nov 15:15:42". Used for every timestamp shown. */
export function dateTime(iso: string): string {
  const d = new Date(iso)
  const date = d.toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'short',
    timeZone: TIME_ZONE,
  })
  const time = d.toLocaleTimeString('en-GB', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
    timeZone: TIME_ZONE,
  })
  return `${date} ${time}`
}

/** A day picked in a date field (YYYY-MM-DD) as "18 Nov". */
export function dayLabel(day: string): string {
  return new Date(`${day}T00:00:00Z`).toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'short',
    timeZone: 'UTC',
  })
}
