/**
 * The Sea Stock data model, as the BRD (v1.2) describes it. Section numbers point to the BRD.
 * Static screens only: this is sample data, not a contract with an API.
 */

/** PPG sales regions (open item D-05). */
export type RegionCode = 'APAC' | 'EMEA' | 'USCA'

export interface Region {
  code: RegionCode
  name: string
}

/** §8 customer list: names and customer IDs as used in PPG systems, plus the region (FR-24). */
export interface Customer {
  id: string
  /** Customer ID in PPG systems. Format to be confirmed by PPG (D-03). */
  customerId: string
  name: string
  region: RegionCode
  status: 'active' | 'inactive'
  addedOn: string
}

/** §8 vessel list. One device per vessel (D-12), one paint locker per vessel (D-06). */
export interface Vessel {
  id: string
  /** Vessel ID in PPG systems. Format to be confirmed by PPG (D-03). */
  vesselId: string
  /** The DN header reads the IMO first, then the vessel name (FR-01). */
  imo: string
  name: string
  customer: string
  device: Device | null
  /** When the opening stock was captured (FR-08). Null: not done yet. */
  baselineOn: string | null
  /** Last time the device's queue reached the server (FR-20). */
  lastSync: string | null
  status: 'active' | 'inactive'
}

export interface Device {
  id: string
  platform: 'Android' | 'iOS'
  appVersion: string
}

/** One component (1K), or two components (2K) with a Base and a Hardener (D-10). */
export type ComponentType = 'Base' | 'Hardener' | '1K'

/** §8 master item list. */
export interface Item {
  articleNo: string
  product: string
  /** Shade or colour. Empty for hardeners, which carry no shade on the label. */
  shade: string
  componentType: ComponentType
  /** Pack size as printed, e.g. "20 L". */
  packSize: string
  /** Liters per can, used to turn cans into liters (§9: inventory in liters is derived). */
  unitVolume: number
  status: 'active' | 'retired'
}

/** §9 transaction types. */
export type TransactionType = 'receipt' | 'consumption' | 'adjustment' | 'baseline'

/** §9 / FR-12 source of a transaction. */
export type TransactionSource = 'DN scan' | 'Label scan' | 'Manual adjustment'

/** §9 transaction record. Quantities are signed: consumption is negative. */
export interface Transaction {
  id: string
  type: TransactionType
  vessel: string
  articleNo: string
  cans: number
  user: string
  device: string
  /** Device time when the crew recorded it. */
  recordedAt: string
  /** When it reached the server (FR-11). The portal only shows synced transactions. */
  syncedAt: string
  source: TransactionSource
  /** Required for adjustments (FR-13) and for receipt differences (FR-05). */
  reason?: string
  /** Delivery note number, for receipts. */
  dn?: string
}

/** FR-04 result of tallying one line. */
export type LineResult = 'matched' | 'short' | 'over' | 'not-on-note' | 'not-received'

export interface DeliveryNoteLine {
  articleNo: string
  /** Quantity on the delivery note; 0 when the item was not on the note. */
  dnCans: number
  /** Quantity confirmed into the locker. */
  receivedCans: number
  result: LineResult
  reason?: string
}

/** §9 delivery note record. Images are not kept (D-07). */
export interface DeliveryNote {
  dnNumber: string
  dnDate: string
  vessel: string
  customerReference: string
  lines: DeliveryNoteLine[]
  capturedBy: string
  capturedAt: string
  syncedAt: string
}

/** FR-23 roles: administrator and user at PPG and customer level; one vessel role (D-13). */
export type RoleKey = 'ppg-admin' | 'ppg-user' | 'customer-admin' | 'customer-user' | 'vessel-user'

export type Level = 'PPG' | 'Customer' | 'Vessel'

/** FR-22: a user is associated with a vessel, a customer or a PPG entity. */
export type Scope =
  | { kind: 'all' }
  | { kind: 'regions'; regions: RegionCode[] }
  | { kind: 'customers'; customers: string[] }
  | { kind: 'customer'; customer: string }
  | { kind: 'vessel'; vessel: string }

export interface User {
  id: string
  name: string
  email: string
  /** Job title from D-04, e.g. Chief Officer, Fleet Manager. */
  title: string
  role: RoleKey
  scope: Scope
  status: 'active' | 'invited' | 'disabled'
  lastSignIn: string | null
}

/** A scan the server could not match to the master item list (§13: flagged, not rejected). */
export interface UnrecognisedScan {
  id: string
  vessel: string
  /** What the label gave: article number if read, else product and shade (A-02 fallback). */
  readArticleNo: string | null
  readProduct: string
  readShade: string
  cans: number
  type: TransactionType
  recordedAt: string
  user: string
}

/** FR-27 label extraction field. */
export interface LabelField {
  key: string
  label: string
  required: 'Always' | 'Where present' | 'Base and 1K only'
  role: string
  rule: string
}
