const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

/** "2026-10-21" → "21 Oct 2026". */
export function formatDate(at: string): string {
  const [y, m, d] = at.slice(0, 10).split('-')
  return `${Number(d)} ${MONTHS[Number(m) - 1]} ${y}`
}

/** "2026-10-21T08:12" → "21 Oct 2026, 08:12". */
export function formatDateTime(at: string): string {
  return `${formatDate(at)}, ${at.slice(11, 16)}`
}

/** 1840 → "1,840 L"; 2.5 → "2.5 L". */
export function formatLiters(value: number): string {
  return `${value.toLocaleString('en-GB', { maximumFractionDigits: 1 })} L`
}

export function formatCans(value: number): string {
  return `${value.toLocaleString('en-GB')} ${Math.abs(value) === 1 ? 'can' : 'cans'}`
}

export function plural(count: number, one: string, many = `${one}s`): string {
  return `${count} ${count === 1 ? one : many}`
}

/** "3 days ago", "today", "never". */
export function formatAgo(days: number | null): string {
  if (days === null) return 'Never'
  if (days === 0) return 'Today'
  if (days === 1) return 'Yesterday'
  return `${days} days ago`
}
