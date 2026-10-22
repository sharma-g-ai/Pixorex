import type { Level, Vessel } from '../data/model'
import { customerById } from '../data/queries'

/** FR-25: report at vessel, customer, geography and PPG level, plus by product. */
export type RollUp = 'product' | 'vessel' | 'customer' | 'region'

export const rollUpLabels: Record<RollUp, string> = {
  product: 'Product',
  vessel: 'Vessel',
  customer: 'Customer',
  region: 'Region',
}

/** Roll-ups each level may use: a customer sees its vessels, a Chief Officer one vessel. */
export const rollUpsFor: Record<Level, RollUp[]> = {
  PPG: ['product', 'vessel', 'customer', 'region'],
  Customer: ['product', 'vessel'],
  Vessel: ['product'],
}

/** The vessel's group for a customer or region roll-up. */
export function groupOfVessel(
  v: Vessel,
  by: 'vessel' | 'customer' | 'region',
): { key: string; name: string } {
  const c = customerById(v.customer)
  if (by === 'vessel') return { key: v.id, name: v.name }
  if (by === 'customer') return { key: c?.id ?? '', name: c?.name ?? '' }
  return { key: c?.region ?? '', name: c?.region ?? '' }
}
