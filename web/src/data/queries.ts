import type { ComponentType, Customer, Device, EnrolmentCode, Item, Transaction, User, Vessel } from './model'
import {
  assignments,
  customers,
  deliveryNotes,
  devices,
  enrolmentCodes,
  imoWithCheckDigit,
  items,
  NOW,
  quarantinedEvents,
  transactions,
  unrecognisedScans,
  users,
  vessels,
} from './sample'

// ---- Look-ups ----

export function customerById(id: string): Customer | undefined {
  return customers.find((c) => c.id === id)
}

export function vesselById(id: string): Vessel | undefined {
  return vessels.find((v) => v.id === id)
}

export function userById(id: string): User | undefined {
  return users.find((u) => u.id === id)
}

export function deviceById(id: string): Device | undefined {
  return devices.find((d) => d.id === id)
}

export function itemByArticle(articleNo: string): Item | undefined {
  return items.find((i) => i.articleNo === articleNo)
}

/** The vessel's active tablet (one per vessel, D-12), or undefined. */
export function activeDevice(vesselId: string): Device | undefined {
  const a = assignments.find((x) => x.vessel === vesselId && x.unassignedAt === null)
  return a ? deviceById(a.device) : undefined
}

/** The vessel a tablet serves now, or undefined. */
export function vesselOfDevice(deviceId: string): Vessel | undefined {
  const a = assignments.find((x) => x.device === deviceId && x.unassignedAt === null)
  return a ? vesselById(a.vessel) : undefined
}

/** The vessel's unused enrolment code that has not expired, or undefined. */
export function openEnrolmentCode(vesselId: string): EnrolmentCode | undefined {
  return enrolmentCodes.find((c) => c.vessel === vesselId && c.status === 'issued' && c.expiresAt > NOW)
}

/** 7 digits, the last one the IMO check digit. */
export function isValidImo(imo: string): boolean {
  return /^\d{7}$/.test(imo) && imoWithCheckDigit(imo.slice(0, 6)) === imo
}

/** "IMO 9812341" */
export function imoLabel(imo: string): string {
  return `IMO ${imo}`
}

// ---- Scope: a PPG Admin sees every customer; a Customer Admin only their own ----

export function visibleCustomers(user: User): Customer[] {
  const s = user.scope
  return s.kind === 'all' ? customers : customers.filter((c) => c.id === s.customer)
}

export function visibleVessels(user: User): Vessel[] {
  const ids = new Set(visibleCustomers(user).map((c) => c.id))
  return vessels.filter((v) => ids.has(v.customer))
}

/** Tablets a user may manage: any for a PPG Admin; for a Customer Admin, those last paired to their vessels. */
export function visibleDevices(user: User): Device[] {
  if (user.scope.kind === 'all') return devices
  const ids = new Set(visibleVessels(user).map((v) => v.id))
  return devices.filter((d) => {
    const last = assignments.filter((a) => a.device === d.id).sort((a, b) => b.assignedAt.localeCompare(a.assignedAt))[0]
    return last !== undefined && ids.has(last.vessel)
  })
}

/** The vessel a tablet was last paired to, current or not. */
export function lastVesselOfDevice(deviceId: string): Vessel | undefined {
  const last = assignments.filter((a) => a.device === deviceId).sort((a, b) => b.assignedAt.localeCompare(a.assignedAt))[0]
  return last ? vesselById(last.vessel) : undefined
}

export function scopeLabel(user: User): string {
  const s = user.scope
  return s.kind === 'all' ? 'All customers' : (customerById(s.customer)?.name ?? s.customer)
}

// ---- Sea Stock, worked out from the ledger (vessel_stock) ----

export interface StockLine {
  vessel: string
  item: Item
  cans: number
  liters: number
  lastChange: string
}

export function liters(articleNo: string, cans: number): number {
  return cans * (itemByArticle(articleNo)?.unitVolume ?? 0)
}

/** Current Sea Stock per vessel and article (FR-09, FR-20). Zero lines are left out. */
export function stockLines(vesselIds: string[]): StockLine[] {
  const wanted = new Set(vesselIds)
  const totals = new Map<string, StockLine>()
  for (const t of transactions) {
    if (!wanted.has(t.vessel)) continue
    const item = itemByArticle(t.articleNo)
    if (!item) continue
    const key = `${t.vessel}|${t.articleNo}`
    const line = totals.get(key) ?? { vessel: t.vessel, item, cans: 0, liters: 0, lastChange: t.recordedAt }
    line.cans += t.cans
    line.liters = line.cans * item.unitVolume
    if (t.recordedAt > line.lastChange) line.lastChange = t.recordedAt
    totals.set(key, line)
  }
  return [...totals.values()].filter((l) => l.cans !== 0)
}

export interface ProductLine {
  item: Item
  cans: number
  liters: number
  vessels: number
}

/** Stock rolled up across vessels by article (FR-24). */
export function stockByProduct(vesselIds: string[]): ProductLine[] {
  const byArticle = new Map<string, ProductLine>()
  for (const line of stockLines(vesselIds)) {
    const p = byArticle.get(line.item.articleNo) ?? { item: line.item, cans: 0, liters: 0, vessels: 0 }
    p.cans += line.cans
    p.liters += line.liters
    p.vessels += 1
    byArticle.set(line.item.articleNo, p)
  }
  return [...byArticle.values()].sort(byProductOrder)
}

export function byProductOrder(a: { item: Item }, b: { item: Item }): number {
  const order: Record<ComponentType, number> = { Base: 0, Hardener: 1, '1K': 2 }
  return (
    a.item.product.localeCompare(b.item.product) ||
    order[a.item.componentType] - order[b.item.componentType] ||
    a.item.shade.localeCompare(b.item.shade)
  )
}

export function totals(lines: { cans: number; liters: number }[]): { cans: number; liters: number } {
  return lines.reduce((acc, l) => ({ cans: acc.cans + l.cans, liters: acc.liters + l.liters }), { cans: 0, liters: 0 })
}

// ---- Transactions and consumption ----

export function transactionsFor(vesselIds: string[]): Transaction[] {
  const wanted = new Set(vesselIds)
  return transactions.filter((t) => wanted.has(t.vessel))
}

/** True when a timestamp's day falls in [from, to] (YYYY-MM-DD, inclusive). */
export function inPeriod(at: string, from: string, to: string): boolean {
  const day = at.slice(0, 10)
  return day >= from && day <= to
}

/** Consumption in a period, as transactions (cans negative). */
export function consumptionLines(vesselIds: string[], from: string, to: string): Transaction[] {
  return transactionsFor(vesselIds).filter((t) => t.type === 'consumption' && inPeriod(t.recordedAt, from, to))
}

export function consumedTotals(lines: Transaction[]): { cans: number; liters: number } {
  return totals(lines.map((t) => ({ cans: -t.cans, liters: -liters(t.articleNo, t.cans) })))
}

/** Who recorded a transaction: the tablet for device rows, the admin for portal rows. */
export function recordedByLabel(t: Transaction): string {
  if (t.origin === 'portal') return userById(t.recordedBy ?? '')?.name ?? 'Portal'
  return t.device ?? 'Tablet'
}

// ---- Review (BRD §13; data model Domains 2, 4, 5) ----

export function negativeStock(vesselIds: string[]): StockLine[] {
  return stockLines(vesselIds).filter((l) => l.cans < 0)
}

export function unrecognisedFor(vesselIds: string[]) {
  const wanted = new Set(vesselIds)
  return unrecognisedScans.filter((s) => wanted.has(s.vessel))
}

export function openHeldEventsFor(vesselIds: string[]) {
  const wanted = new Set(vesselIds)
  return quarantinedEvents.filter((e) => wanted.has(e.vessel) && e.status === 'open')
}

/** Delivery notes whose IMO read from the paper does not match the vessel. */
export function imoMismatchesFor(vesselIds: string[]) {
  const wanted = new Set(vesselIds)
  return deliveryNotes.filter((d) => wanted.has(d.vessel) && d.imoCheck === 'mismatch')
}

// ---- Time ----

export function daysSince(at: string | null): number | null {
  if (!at) return null
  const ms = new Date(`${NOW}:00Z`).getTime() - new Date(`${at.length === 10 ? `${at}T00:00` : at}:00Z`).getTime()
  return Math.floor(ms / 86_400_000)
}

export function daysAgo(days: number): string {
  const d = new Date(`${NOW}:00Z`)
  d.setUTCDate(d.getUTCDate() - days)
  return d.toISOString().slice(0, 10)
}

export function hoursFrom(at: string, hours: number): string {
  const d = new Date(`${at}:00Z`)
  d.setUTCHours(d.getUTCHours() + hours)
  return d.toISOString().slice(0, 16)
}
