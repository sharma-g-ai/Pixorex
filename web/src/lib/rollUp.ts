import type { RoleKey, Vessel } from '../data/model'
import { customerById } from '../data/queries'

/** FR-24: reporting at vessel, customer and PPG level (no region in BRD v1.3), plus by product. */
export type RollUp = 'product' | 'vessel' | 'customer'

export const rollUpLabels: Record<RollUp, string> = {
  product: 'Product',
  vessel: 'Vessel',
  customer: 'Customer',
}

/** Roll-ups each role may use: a Customer Admin sees one customer, so no customer roll-up. */
export const rollUpsFor: Record<RoleKey, RollUp[]> = {
  'ppg-admin': ['product', 'vessel', 'customer'],
  'customer-admin': ['product', 'vessel'],
}

/** The vessel's group for a vessel or customer roll-up. */
export function groupOfVessel(v: Vessel, by: 'vessel' | 'customer'): { key: string; name: string } {
  if (by === 'vessel') return { key: v.id, name: v.name }
  const c = customerById(v.customer)
  return { key: c?.id ?? '', name: c?.name ?? '' }
}
