import type { Escalation } from '../../api/escalations'

/** Escalated scans of one unit, oldest first (canvas EA 04 unit cards). */
export interface UnitEscalations {
  buId: string
  buName: string
  items: Escalation[]
  /** When the longest-waiting scan was escalated. */
  oldest: string
  noBuAdmin: boolean
}

/** Groups escalations by unit; the unit with the most scans comes first. */
export function groupByUnit(items: Escalation[]): UnitEscalations[] {
  const units = new Map<string, Escalation[]>()
  for (const item of items) units.set(item.bu_id, [...(units.get(item.bu_id) ?? []), item])
  return [...units.values()]
    .map((list) => {
      const sorted = [...list].sort((a, b) => a.escalated_at.localeCompare(b.escalated_at))
      const first = sorted[0] as Escalation
      return {
        buId: first.bu_id,
        buName: first.bu_name,
        items: sorted,
        oldest: first.escalated_at,
        noBuAdmin: sorted.some((e) => e.reason === 'no_bu_admin'),
      }
    })
    .sort((a, b) => b.items.length - a.items.length)
}

/** "Over 24 h with R. Kowalski" or "No BU Admin". */
export function whyText(reason: Escalation['reason'], buAdminName?: string): string {
  if (reason === 'no_bu_admin') return 'No BU Admin'
  return buAdminName ? `Over 24 h with ${buAdminName}` : 'Over 24 h with the BU Admin'
}
