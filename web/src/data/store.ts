/**
 * The sample data as one shared store, so a change on one screen shows on every screen.
 * Changes are kept for the browser tab (sessionStorage) and can be reset to the sample data.
 * Every admin action also writes an audit row (data model Domain 6).
 * Static screens only: there is no API behind this (see contracts/).
 */
import { useSyncExternalStore } from 'react'
import type { Assignment, AuditEntry, Customer, Item, Transaction, UnrecognisedScan, User, Vessel } from './model'
import {
  assignments,
  auditLog,
  customers,
  deliveryNotes,
  devices,
  enrolmentCodes,
  items,
  NOW,
  quarantinedEvents,
  transactions,
  unrecognisedScans,
  users,
  vessels,
} from './sample'

const KEY = 'seastock.data.v3'

function snapshot() {
  return {
    customers, vessels, devices, assignments, enrolmentCodes, users, items, transactions,
    unrecognisedScans, quarantinedEvents, deliveryNotes, auditLog,
  }
}

type Snapshot = ReturnType<typeof snapshot>

const initial: Snapshot = structuredClone(snapshot())

/** Replaces the contents of every sample array in place, so every import sees the change. */
function load(data: Snapshot) {
  const fill = <T>(target: T[], from: T[]) => target.splice(0, target.length, ...structuredClone(from))
  fill(customers, data.customers)
  fill(vessels, data.vessels)
  fill(devices, data.devices)
  fill(assignments, data.assignments)
  fill(enrolmentCodes, data.enrolmentCodes)
  fill(users, data.users)
  fill(items, data.items)
  fill(transactions, data.transactions)
  fill(unrecognisedScans, data.unrecognisedScans)
  fill(quarantinedEvents, data.quarantinedEvents)
  fill(deliveryNotes, data.deliveryNotes)
  fill(auditLog, data.auditLog)
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

let seq = 0
const newId = (prefix: string) => `${prefix}-${Date.now().toString(36)}-${(seq += 1)}`

function audit(by: User, category: AuditEntry['category'], summary: string, vessel: string | null = null, customer: string | null = null) {
  const v = vessels.find((x) => x.id === vessel)
  auditLog.unshift({ id: newId('a'), at: NOW, actorType: 'user', actor: by.id, vessel, customer: customer ?? v?.customer ?? null, category, summary: `${by.name} ${summary}` })
}

function upsert<T>(list: T[], row: T, same: (a: T) => boolean): 'added' | 'changed' {
  const i = list.findIndex(same)
  if (i >= 0) {
    list[i] = row
    return 'changed'
  }
  list.push(row)
  return 'added'
}

// ---- Customers and vessels ----

export function saveCustomer(c: Customer, by: User) {
  const what = upsert(customers, c, (x) => x.id === c.id)
  audit(by, 'customers_vessels', `${what === 'added' ? 'added' : 'edited'} customer ${c.name} (${c.customerCode}).`, null, c.id)
  changed()
}

export function saveVessel(v: Vessel, by: User) {
  const what = upsert(vessels, v, (x) => x.id === v.id)
  audit(by, 'customers_vessels', `${what === 'added' ? 'added' : 'edited'} vessel ${v.name} (IMO ${v.imo}).`, v.id)
  changed()
}

/** All-or-nothing import keyed on customer_code (import_customers). */
export function importCustomers(rows: Customer[], by: User) {
  for (const r of rows) upsert(customers, r, (x) => x.customerCode === r.customerCode)
  audit(by, 'customers_vessels', `imported ${rows.length} customers from Excel.`)
  changed()
}

/** All-or-nothing import keyed on IMO number (import_vessels). */
export function importVessels(rows: Vessel[], by: User) {
  for (const r of rows) upsert(vessels, r, (x) => x.imo === r.imo)
  audit(by, 'customers_vessels', `imported ${rows.length} vessels from Excel.`, null, rows[0]?.customer ?? null)
  changed()
}

/** record_vessel_password_reset(): at crew change. */
export function recordPasswordReset(vesselId: string, by: User) {
  const v = vessels.find((x) => x.id === vesselId)
  if (!v) return
  v.passwordChangedAt = NOW
  audit(by, 'customers_vessels', `recorded a password reset for ${v.name} (crew change).`, v.id)
  changed()
}

// ---- Tablets ----

function code(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  const pick = () => chars[Math.floor(Math.random() * chars.length)]
  return `${Array.from({ length: 4 }, pick).join('')}-${Array.from({ length: 4 }, pick).join('')}`
}

/**
 * One open code per vessel: issuing a new one cancels the open one. Valid 72 hours. Only the hash
 * is stored, so the code is returned here once and never read back.
 */
export function issueEnrolmentCode(vesselId: string, by: User): string {
  for (const c of enrolmentCodes) if (c.vessel === vesselId && c.status === 'issued') c.status = 'cancelled'
  const value = code()
  const expires = new Date(`${NOW}:00Z`)
  expires.setUTCHours(expires.getUTCHours() + 72)
  enrolmentCodes.push({ id: newId('ec'), vessel: vesselId, issuedBy: by.id, issuedAt: NOW, expiresAt: expires.toISOString().slice(0, 16), status: 'issued' })
  const v = vessels.find((x) => x.id === vesselId)
  audit(by, 'devices', `issued an enrolment code for ${v?.name ?? vesselId}.`, vesselId)
  changed()
  return value
}

export function cancelEnrolmentCode(codeId: string, by: User) {
  const c = enrolmentCodes.find((x) => x.id === codeId)
  if (!c || c.status !== 'issued') return
  c.status = 'cancelled'
  audit(by, 'devices', 'cancelled an enrolment code.', c.vessel)
  changed()
}

function endAssignment(deviceId: string, reason: NonNullable<Assignment['unassignReason']>) {
  const a = assignments.find((x) => x.device === deviceId && x.unassignedAt === null)
  if (!a) return null
  a.unassignedAt = NOW
  a.unassignReason = reason
  return a
}

/**
 * request_device_retirement(): a working tablet being replaced stays active, uploads what it holds
 * at its next sync, and that sync retires it. Only then can a new tablet enrol. Set once.
 */
export function requestDeviceRetirement(deviceId: string, by: User) {
  const d = devices.find((x) => x.id === deviceId)
  if (!d || d.status !== 'active' || d.retireRequestedAt) return
  d.retireRequestedAt = NOW
  const a = assignments.find((x) => x.device === deviceId && x.unassignedAt === null)
  audit(by, 'devices', `prepared tablet ${d.id} for retirement after its next sync.`, a?.vessel ?? null)
  changed()
}

/** retire_device(): one click for a broken or lost tablet. Anything still on it is not uploaded. */
export function retireDevice(deviceId: string, by: User) {
  const d = devices.find((x) => x.id === deviceId)
  if (!d || d.status !== 'active') return
  d.status = 'retired'
  d.retiredAt = NOW
  const a = endAssignment(d.id, 'device_retired')
  audit(by, 'devices', `retired tablet ${d.id} at once.`, a?.vessel ?? null)
  changed()
}

/** Revoked is final and ends the tablet's assignment at once. */
export function revokeDevice(deviceId: string, reason: string, by: User) {
  const d = devices.find((x) => x.id === deviceId)
  if (!d || d.status !== 'active') return
  d.status = 'revoked'
  d.revokedAt = NOW
  d.revokeReason = reason
  const a = endAssignment(d.id, 'device_revoked')
  audit(by, 'devices', `revoked tablet ${d.id}: ${reason}`, a?.vessel ?? null)
  changed()
}

// ---- Users ----

export function saveUser(u: User, by: User) {
  const what = upsert(users, u, (x) => x.id === u.id)
  const customer = u.scope.kind === 'customer' ? u.scope.customer : null
  audit(by, 'users', what === 'added' ? `invited ${u.name} (${u.email}).` : `edited user ${u.name}.`, null, customer)
  changed()
}

export function resendInvite(userId: string, by: User) {
  const u = users.find((x) => x.id === userId)
  if (!u) return
  const expires = new Date(`${NOW}:00Z`)
  expires.setUTCDate(expires.getUTCDate() + 7)
  u.invite = { status: 'pending', sentAt: NOW, expiresAt: expires.toISOString().slice(0, 16) }
  audit(by, 'users', `re-sent the invite to ${u.name}.`, null, u.scope.kind === 'customer' ? u.scope.customer : null)
  changed()
}

export function cancelInvite(userId: string, by: User) {
  const u = users.find((x) => x.id === userId)
  if (!u?.invite || u.invite.status !== 'pending') return
  u.invite = { ...u.invite, status: 'cancelled' }
  audit(by, 'users', `cancelled the invite to ${u.name}.`, null, u.scope.kind === 'customer' ? u.scope.customer : null)
  changed()
}

// ---- Products ----

export function addItems(newItems: Item[], by: User) {
  items.unshift(...newItems)
  audit(by, 'articles', newItems.length === 1 ? `added article ${newItems[0]?.articleNo}.` : `loaded ${newItems.length} articles.`)
  changed()
}

// ---- Stock ----

function post(t: Omit<Transaction, 'id'>) {
  const next = Math.max(...transactions.map((x) => Number(x.id.slice(3))), 10000) + 1
  transactions.push({ ...t, id: `TX-${next}` })
  transactions.sort((a, b) => b.recordedAt.localeCompare(a.recordedAt))
}

/** A portal adjustment: names the person, no tablet. Reason required. */
export function adjustStock(vesselId: string, articleNo: string, cans: number, reason: string, by: User) {
  post({ type: 'adjustment', vessel: vesselId, articleNo, cans, origin: 'portal', device: null, recordedBy: by.id, recordedAt: NOW, receivedAt: NOW, source: 'Manual adjustment', reason })
  const v = vessels.find((x) => x.id === vesselId)
  audit(by, 'inventory', `adjusted ${v?.name ?? vesselId}: ${cans > 0 ? '+' : ''}${cans} ${Math.abs(cans) === 1 ? 'can' : 'cans'} of ${articleNo}.`, vesselId)
  changed()
}

/**
 * match_unrecognised_scan(): a PPG Admin matches a held scan to an article in the master list. It
 * posts as one transaction (origin portal, source review match, dated at the original scan) and
 * the scan stays, marked matched. A matched scan is final.
 */
export function matchScan(scan: UnrecognisedScan, articleNo: string, by: User) {
  const held = unrecognisedScans.find((s) => s.id === scan.id && s.status === 'open')
  if (!held) return
  held.status = 'matched'
  held.matchedArticle = articleNo
  held.matchedBy = by.id
  held.matchedAt = NOW
  post({ type: scan.kind, vessel: scan.vessel, articleNo, cans: scan.kind === 'consumption' ? -scan.cans : scan.cans, origin: 'portal', device: null, recordedBy: by.id, recordedAt: scan.recordedAt, receivedAt: NOW, source: 'Review match', reason: `Label read "${scan.rawArticleNo}"; matched to ${articleNo}.`, dn: scan.dn })
  audit(by, 'inventory', `matched a held scan ("${scan.rawArticleNo}") to article ${articleNo}.`, scan.vessel)
  changed()
}

/** Closing a held event posts nothing; the fix itself is done another way. */
export function closeHeldEvent(eventId: string, outcome: 'resolved' | 'dismissed', note: string, by: User) {
  const e = quarantinedEvents.find((x) => x.id === eventId)
  if (!e || e.status !== 'open') return
  e.status = outcome
  e.resolvedBy = by.id
  e.resolvedAt = NOW
  e.resolutionNote = note
  audit(by, 'sync', `${outcome} a held event (${e.errorCode}): ${note}`, e.vessel)
  changed()
}
