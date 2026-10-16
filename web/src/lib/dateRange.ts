export type DatePreset = 'today' | '7d' | '30d' | '90d'

export const datePresetLabels: Record<DatePreset, string> = {
  today: 'Today',
  '7d': 'Last 7 days',
  '30d': 'Last 30 days',
  '90d': 'Last 90 days',
}

const presetDays: Record<DatePreset, number> = { today: 0, '7d': 6, '30d': 29, '90d': 89 }

/** "Last 7 days" as the API's from/to dates (YYYY-MM-DD, both inclusive, UTC). */
export function dateRange(
  preset: DatePreset,
  now: Date = new Date(),
): { from: string; to: string } {
  const from = new Date(now)
  from.setUTCDate(from.getUTCDate() - presetDays[preset])
  return { from: isoDate(from), to: isoDate(now) }
}

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10)
}
