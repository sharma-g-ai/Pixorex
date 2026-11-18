import { dayLabel } from '../lib/time'
import type { DayRange } from './ColumnFilter'

/** "Schema: pump label, motor nameplate" or "Captured by: 3 selected". */
export function listChip(name: string, labels: string[]): string {
  return `${name}: ${labels.length <= 2 ? labels.join(', ') : `${labels.length} selected`}`
}

/** "Date: 12 Nov – 16 Nov", "Date: from 12 Nov" or "Date: until 16 Nov". */
export function rangeChip(name: string, { from, to }: DayRange): string {
  if (from && to) return `${name}: ${dayLabel(from)} – ${dayLabel(to)}`
  if (from) return `${name}: from ${dayLabel(from)}`
  return `${name}: until ${dayLabel(to)}`
}
