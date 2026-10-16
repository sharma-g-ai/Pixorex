const MINUTE = 60_000
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR

/** "just now", "14 min ago", "3 h ago", "yesterday", or a date like "2 Oct". */
export function timeAgo(iso: string, now: Date = new Date()): string {
  const diff = now.getTime() - new Date(iso).getTime()
  if (diff < MINUTE) return 'just now'
  if (diff < HOUR) return `${Math.floor(diff / MINUTE)} min ago`
  if (diff < DAY) return `${Math.floor(diff / HOUR)} h ago`
  if (diff < 2 * DAY) return 'yesterday'
  return new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })
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
