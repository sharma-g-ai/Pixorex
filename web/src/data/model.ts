/**
 * The Sea Stock data model: BRD v1.3 (21 Oct 2026) and SeaStock Data Models V2 (16 tables, with the
 * data model review of 2 Nov 2026). Domain numbers point to the data model.
 * Static screens only: this is sample data, not the API (see contracts/).
 */

/** Domain 1: a shipping company PPG supplies. No region (BRD v1.3: roll-up by customer only). */
export interface Customer {
  id: string
  /** The customer ID in PPG systems (customer_code). */
  customerCode: string
  name: string
  status: 'active' | 'inactive'
  addedOn: string
}

/** Domain 1: one ship. The IMO number is the vessel ID; a vessel is never identified by name. */
export interface Vessel {
  id: string
  /** 7 digits with a valid check digit, e.g. "9812341". */
  imo: string
  name: string
  customer: string
  /** Sent to the tablet at sync: scan labels, or enter receipts by hand. */
  receivingMode: 'scan' | 'manual'
  /** When the first baseline batch posted (FR-08). Null: not done yet. */
  baselineOn: string | null
  /** Set only by a succeeded sync session (FR-20). */
  lastSync: string | null
  status: 'active' | 'inactive'
  /** The vessel is the tablet's user: its sign-in account (no crew accounts). */
  passwordChangedAt: string | null
  lastSignInAt: string | null
}

/** Domain 2: one registered tablet. It belongs to a vessel only through an assignment. */
export interface Device {
  id: string
  platform: 'Android' | 'iOS'
  model: string
  /** One of the guaranteed tablets; an unlisted model is a warning, not a block. */
  modelSupported: boolean
  osVersion: string
  appVersion: string
  status: 'active' | 'retired' | 'revoked'
  enrolledAt: string
  firstSyncedAt: string | null
  /** An admin prepared it for retirement: it retires after its next succeeded sync. */
  retireRequestedAt: string | null
  retiredAt: string | null
  revokedAt: string | null
  revokeReason: string | null
}

/** Domain 2: the one-off enrolment of a tablet to a vessel. A tablet is enrolled once; one active row per vessel. */
export interface Assignment {
  id: string
  vessel: string
  device: string
  assignedAt: string
  /** Null = active. */
  unassignedAt: string | null
  unassignReason: 'device_retired' | 'device_revoked' | null
}

/**
 * Domain 2: one-time code that binds a tablet to one vessel (QR or typed). Only its hash is stored,
 * so the code itself is shown once, to the admin who issues it, and is never read back.
 */
export interface EnrolmentCode {
  id: string
  vessel: string
  issuedBy: string
  issuedAt: string
  /** 72 hours by default. */
  expiresAt: string
  status: 'issued' | 'used' | 'cancelled'
}

/** One component (1K) or two components (2K: Base or Hardener) (D-10). */
export type ComponentType = 'Base' | 'Hardener' | '1K'

/** Domain 3: one PPG product as sold. The master list only grows: articles are never retired or deleted. */
export interface Item {
  articleNo: string
  product: string
  /** Empty for hardeners and thinners. */
  shade: string
  productType: '1K' | '2K'
  componentType: ComponentType
  /** As printed, e.g. "20 L". */
  packSize: string
  /** Liters per can, used to turn cans into liters. */
  unitVolume: number
}

/** Domain 5 transaction types. */
export type TransactionType = 'receipt' | 'consumption' | 'adjustment' | 'baseline'

/** Domain 5 / FR-12 source. */
export type TransactionSource =
  | 'DN scan'
  | 'Label scan'
  | 'Manual entry'
  | 'Manual adjustment'
  | 'Review match'

/** Domain 5: one stock movement. Insert-only; signed (consumption is negative). */
export interface Transaction {
  id: string
  type: TransactionType
  vessel: string
  articleNo: string
  cans: number
  /** device = uploaded by the tablet (names no person); portal = recorded by an admin. */
  origin: 'device' | 'portal'
  /** The tablet, for device rows. */
  device: string | null
  /** The PPG Admin or Customer Admin, for portal rows. */
  recordedBy: string | null
  /** When the movement happened (tablet clock for device rows). */
  recordedAt: string
  /** Server clock: when it arrived. */
  receivedAt: string
  source: TransactionSource
  /** Required for adjustments. */
  reason?: string
  /** Delivery note number, for receipts. */
  dn?: string
}

/** FR-04 result of one tally line. */
export type LineResult = 'matched' | 'short' | 'over' | 'not-on-note' | 'not-received'

export interface DeliveryNoteLine {
  articleNo: string
  /** Quantity on the note; null = not on the note. */
  dnCans: number | null
  receivedCans: number
  result: LineResult
  reason?: string
}

/** Domain 4: one confirmed delivery note. Insert-only; no image kept (D-07). */
export interface DeliveryNote {
  dnNumber: string
  dnDate: string
  /** Always the enrolled tablet's vessel, never a value read from paper. */
  vessel: string
  device: string
  /** As read from the note (display; the IMO is checked, never used to choose the vessel). */
  imoOnNote: string | null
  vesselNameOnNote: string | null
  imoCheck: 'match' | 'mismatch' | 'not_read'
  customerReference: string
  lines: DeliveryNoteLine[]
  /** Tablet clock: DN scanned, receipt confirmed. */
  capturedAt: string
  confirmedAt: string
  /** Server clock. */
  receivedAt: string
}

/** Domain 1: two portal roles. The vessel signs in on its tablet; crew have no accounts. */
export type RoleKey = 'ppg-admin' | 'customer-admin'

/** A PPG Admin sees every customer; a Customer Admin exactly one. */
export type Scope = { kind: 'all' } | { kind: 'customer'; customer: string }

export interface User {
  id: string
  name: string
  email: string
  /** Optional (no document requires it). */
  title: string
  role: RoleKey
  scope: Scope
  status: 'active' | 'invited' | 'disabled'
  lastSignIn: string | null
  /** The latest emailed invite. */
  invite: { status: 'pending' | 'accepted' | 'expired' | 'cancelled'; sentAt: string; expiresAt: string } | null
}

/** Domain 5: a scanned item whose article number is not in the master list. Held, not in stock. */
export interface UnrecognisedScan {
  id: string
  vessel: string
  device: string
  kind: 'receipt' | 'consumption' | 'baseline'
  /** As read from the label. */
  rawArticleNo: string
  /** The other label fields as read. */
  rawLabel: { product?: string; shade?: string; batch?: string }
  cans: number
  recordedAt: string
  receivedAt: string
  dn?: string
  /** A matched scan is final and is kept, with who matched it. */
  status: 'open' | 'matched'
  matchedArticle: string | null
  matchedBy: string | null
  matchedAt: string | null
}

/** Domain 2: an uploaded event the server could not apply, held for an admin. */
export interface QuarantinedEvent {
  id: string
  vessel: string
  device: string
  eventType: 'delivery_note' | 'item' | 'adjustment' | 'unknown'
  errorCode: string
  errorDetail: string
  /** A readable line about the event as sent. */
  summary: string
  receivedAt: string
  status: 'open' | 'resolved' | 'dismissed'
  resolvedBy: string | null
  resolvedAt: string | null
  resolutionNote: string | null
}

/** Domain 6: who did what, when, from which account or tablet. Insert-only. */
export interface AuditEntry {
  id: string
  at: string
  actorType: 'user' | 'device' | 'system'
  /** User ID or device ID. */
  actor: string | null
  /** The vessel affected, for vessel and tablet events (scopes a Customer Admin's view). */
  vessel: string | null
  /** The customer affected (scopes a Customer Admin's view). */
  customer: string | null
  category:
    | 'users'
    | 'customers_vessels'
    | 'devices'
    | 'articles'
    | 'delivery_notes'
    | 'inventory'
    | 'sync'
  summary: string
}
