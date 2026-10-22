/**
 * The sample data as one shared store, so a change on one screen shows on every screen.
 * Changes are kept for the browser tab (sessionStorage) and can be reset to the sample data.
 * Static screens only: there is no API behind this.
 */
import { useSyncExternalStore } from 'react'
import type {
  Customer,
  Item,
  LabelField,
  Region,
  Transaction,
  UnrecognisedScan,
  User,
  Vessel,
} from './model'
import {
  customers,
  deliveryNotes,
  items,
  labelSchema,
  NOW,
  regions,
  transactions,
  unrecognisedScans,
  users,
  vessels,
} from './sample'

const KEY = 'seastock.data'

function snapshot() {
  return {
    customers,
    vessels,
    users,
    items,
    regions,
    transactions,
    unrecognisedScans,
    deliveryNotes,
    labelSchema: { ...labelSchema },
  }
}

type Snapshot = ReturnType<typeof snapshot>

const initial: Snapshot = structuredClone(snapshot())

/** Replaces the contents of every sample array in place, so every import sees the change. */
function load(data: Snapshot) {
  const fill = <T>(target: T[], from: T[]) =>
    target.splice(0, target.length, ...structuredClone(from))
  fill(customers, data.customers)
  fill(vessels, data.vessels)
  fill(users, data.users)
  fill(items, data.items)
  fill(regions, data.regions)
  fill(transactions, data.transactions)
  fill(unrecognisedScans, data.unrecognisedScans)
  fill(deliveryNotes, data.deliveryNotes)
  labelSchema.version = data.labelSchema.version
  labelSchema.publishedOn = data.labelSchema.publishedOn
  labelSchema.publishedBy = data.labelSchema.publishedBy
  fill(labelSchema.fields, data.labelSchema.fields)
}

try {
  const saved = sessionStorage.getItem(KEY)
  if (saved) load(JSON.parse(saved) as Snapshot)
} catch {
  // Nothing saved, or storage blocked: start from the sample data.
}

let version = 0
const listeners = new Set<() => void>()

function changed() {
  version += 1
  try {
    sessionStorage.setItem(KEY, JSON.stringify(snapshot()))
  } catch {
    // Storage blocked: changes last until reload.
  }
  listeners.forEach((l) => l())
}

/** Re-renders the calling component whenever the data changes. */
export function useStore(): number {
  return useSyncExternalStore(
    (listener) => {
      listeners.add(listener)
      return () => listeners.delete(listener)
    },
    () => version,
  )
}

/** Back to the sample data, e.g. before a demo. */
export function resetSampleData() {
  load(initial)
  try {
    sessionStorage.removeItem(KEY)
  } catch {
    // Storage blocked.
  }
  version += 1
  listeners.forEach((l) => l())
}

function upsert<T>(list: T[], row: T, same: (a: T) => boolean) {
  const i = list.findIndex(same)
  if (i >= 0) list[i] = row
  else list.push(row)
  changed()
}

export const saveCustomer = (c: Customer) => upsert(customers, c, (x) => x.id === c.id)
export const saveVessel = (v: Vessel) => upsert(vessels, v, (x) => x.id === v.id)
export const saveUser = (u: User) => upsert(users, u, (x) => x.id === u.id)
export const saveRegion = (r: Region) => upsert(regions, r, (x) => x.code === r.code)

export function addItems(newItems: Item[]) {
  items.unshift(...newItems)
  changed()
}

export function setItemStatus(articleNo: string, status: Item['status']) {
  const item = items.find((i) => i.articleNo === articleNo)
  if (!item) return
  item.status = status
  changed()
}

export function publishLabelSchema(fields: LabelField[], by: string) {
  labelSchema.fields.splice(0, labelSchema.fields.length, ...structuredClone(fields))
  labelSchema.version += 1
  labelSchema.publishedOn = NOW
  labelSchema.publishedBy = by
  changed()
}

/**
 * A scan the server could not match, now matched to an article by a PPG Admin: it leaves the
 * review list and posts to Sea Stock as the receipt or consumption it was.
 */
export function matchScan(scan: UnrecognisedScan, articleNo: string, by: User) {
  const i = unrecognisedScans.findIndex((s) => s.id === scan.id)
  if (i < 0) return
  unrecognisedScans.splice(i, 1)
  const vessel = vessels.find((v) => v.id === scan.vessel)
  const next = Math.max(...transactions.map((t) => Number(t.id.slice(3))), 10000) + 1
  const posted: Transaction = {
    id: `TX-${next}`,
    type: scan.type,
    vessel: scan.vessel,
    articleNo,
    cans: scan.type === 'consumption' ? -scan.cans : scan.cans,
    user: scan.user,
    device: vessel?.device?.id ?? '',
    recordedAt: scan.recordedAt,
    syncedAt: NOW,
    source: 'Label scan',
    reason: `Matched to article ${articleNo} by ${by.name}; label read "${scan.readArticleNo ?? 'unreadable'}".`,
  }
  transactions.push(posted)
  transactions.sort((a, b) => b.recordedAt.localeCompare(a.recordedAt))
  changed()
}
