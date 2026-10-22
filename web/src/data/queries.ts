import type { ComponentType, Customer, Item, RegionCode, Transaction, User, Vessel } from './model'
import { customers, items, NOW, transactions, unrecognisedScans, users, vessels } from './sample'

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

export function itemByArticle(articleNo: string): Item | undefined {
  return items.find((i) => i.articleNo === articleNo)
}

export function regionOfVessel(vessel: Vessel): RegionCode | undefined {
  return customerById(vessel.customer)?.region
}

// ---- Scope (FR-23, FR-24): what a user may see ----

export function visibleCustomers(user: User): Customer[] {
  const s = user.scope
  switch (s.kind) {
    case 'all':
      return customers
    case 'regions':
      return customers.filter((c) => s.regions.includes(c.region))
    case 'customers':
      return customers.filter((c) => s.customers.includes(c.id))
    case 'customer':
      return customers.filter((c) => c.id === s.customer)
    case 'vessel': {
      const vessel = vesselById(s.vessel)
      return customers.filter((c) => c.id === vessel?.customer)
    }
  }
}

export function visibleVessels(user: User): Vessel[] {
  if (user.scope.kind === 'vessel') {
    const id = user.scope.vessel
    return vessels.filter((v) => v.id === id)
  }
  const ids = new Set(visibleCustomers(user).map((c) => c.id))
  return vessels.filter((v) => ids.has(v.customer))
}

export function scopeLabel(user: User): string {
  const s = user.scope
  switch (s.kind) {
    case 'all':
      return 'All regions'
    case 'regions':
      return `Region: ${s.regions.join(', ')}`
    case 'customers':
      return s.customers.map((id) => customerById(id)?.name ?? id).join(', ')
    case 'customer':
      return customerById(s.customer)?.name ?? s.customer
    case 'vessel':
      return vesselById(s.vessel)?.name ?? s.vessel
  }
}

// ---- Sea Stock, worked out from the transaction stream ----

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
    const line = totals.get(key) ?? {
      vessel: t.vessel,
      item,
      cans: 0,
      liters: 0,
      lastChange: t.recordedAt,
    }
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

/** Stock rolled up across vessels by article (FR-25). */
export function stockByProduct(vesselIds: string[]): ProductLine[] {
  const byArticle = new Map<string, ProductLine>()
  for (const line of stockLines(vesselIds)) {
    const p = byArticle.get(line.item.articleNo) ?? {
      item: line.item,
      cans: 0,
      liters: 0,
      vessels: 0,
    }
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

export function totals(lines: { cans: number; liters: number }[]): {
  cans: number
  liters: number
} {
  return lines.reduce((acc, l) => ({ cans: acc.cans + l.cans, liters: acc.liters + l.liters }), {
    cans: 0,
    liters: 0,
  })
}

// ---- Consumption ----

export function transactionsFor(vesselIds: string[]): Transaction[] {
  const wanted = new Set(vesselIds)
  return transactions.filter((t) => wanted.has(t.vessel))
}

/** Consumption in a period (dates inclusive, YYYY-MM-DD), as positive cans and liters. */
export function consumptionLines(vesselIds: string[], from: string, to: string): Transaction[] {
  return transactionsFor(vesselIds).filter(
    (t) =>
      t.type === 'consumption' &&
      t.recordedAt.slice(0, 10) >= from &&
      t.recordedAt.slice(0, 10) <= to,
  )
}

export function consumedTotals(lines: Transaction[]): { cans: number; liters: number } {
  return totals(lines.map((t) => ({ cans: -t.cans, liters: -liters(t.articleNo, t.cans) })))
}

// ---- Review (BRD §13 mitigations) ----

export function negativeStock(vesselIds: string[]): StockLine[] {
  return stockLines(vesselIds).filter((l) => l.cans < 0)
}

export function unrecognisedFor(vesselIds: string[]) {
  const wanted = new Set(vesselIds)
  return unrecognisedScans.filter((s) => wanted.has(s.vessel))
}

// ---- Time ----

export function daysSince(at: string | null): number | null {
  if (!at) return null
  const ms =
    new Date(`${NOW}:00Z`).getTime() -
    new Date(`${at.length === 10 ? `${at}T00:00` : at}:00Z`).getTime()
  return Math.floor(ms / 86_400_000)
}

export function daysAgo(days: number): string {
  const d = new Date(`${NOW}:00Z`)
  d.setUTCDate(d.getUTCDate() - days)
  return d.toISOString().slice(0, 10)
}
