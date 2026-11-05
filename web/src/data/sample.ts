/**
 * Sample data for the static screens. Names, IDs and e-mail addresses are made up;
 * product names and article numbers follow the BRD examples (DN 5324641215, SIGMACOVER 350,
 * article 179061) and are placeholders until PPG provides the master item list (D-02).
 * All times are UTC.
 */
import type {
  Assignment,
  AuditEntry,
  Customer,
  DeliveryNote,
  Device,
  EnrolmentCode,
  Item,
  QuarantinedEvent,
  Transaction,
  UnrecognisedScan,
  User,
  Vessel,
} from './model'

/** "Now" for the static screens. */
export const NOW = '2026-10-21T16:00'

export const customers: Customer[] = [
  { id: 'c1', customerCode: 'C-104512', name: 'Nordhavn Bulk Carriers', status: 'active', addedOn: '2026-09-22' },
  { id: 'c2', customerCode: 'C-104530', name: 'Meridian Container Lines', status: 'active', addedOn: '2026-09-22' },
  { id: 'c3', customerCode: 'C-208114', name: 'Pacific Crest Tankers', status: 'active', addedOn: '2026-09-24' },
  { id: 'c4', customerCode: 'C-208190', name: 'Straits Offshore Services', status: 'active', addedOn: '2026-10-15' },
  { id: 'c5', customerCode: 'C-310077', name: 'Atlantic Gulf Marine', status: 'active', addedOn: '2026-09-26' },
]

/** IMO number with its check digit (weights 7..2 over the first six digits). */
export function imoWithCheckDigit(six: string): string {
  const sum = [...six].reduce((acc, d, i) => acc + Number(d) * (7 - i), 0)
  return `${six}${sum % 10}`
}

function vessel(id: string, six: string, name: string, customer: string, baselineOn: string | null, lastSync: string | null, extra: Partial<Vessel> = {}): Vessel {
  return { id, imo: imoWithCheckDigit(six), name, customer, receivingMode: 'scan', baselineOn, lastSync, status: 'active', passwordChangedAt: '2026-10-01T06:00', lastSignInAt: lastSync, ...extra }
}

export const vessels: Vessel[] = [
  vessel('v01', '981234', 'Nordhavn Aurora', 'c1', '2026-10-01', '2026-10-21T08:12'),
  vessel('v02', '981235', 'Nordhavn Borealis', 'c1', '2026-10-01', '2026-10-20T22:40'),
  vessel('v03', '979041', 'Nordhavn Fjord', 'c1', '2026-10-02', '2026-10-19T06:15'),
  vessel('v04', '979042', 'Nordhavn Skagen', 'c1', '2026-10-02', '2026-10-14T11:30', { passwordChangedAt: '2026-10-12T09:00' }),
  vessel('v05', '984660', 'Meridian Valencia', 'c2', '2026-10-01', '2026-10-21T05:50'),
  vessel('v06', '984661', 'Meridian Genoa', 'c2', '2026-10-03', '2026-10-18T13:05', { receivingMode: 'manual' }),
  vessel('v07', '977120', 'Pacific Crest Osprey', 'c3', '2026-10-01', '2026-10-20T03:20'),
  vessel('v08', '977121', 'Pacific Crest Kestrel', 'c3', '2026-10-02', '2026-10-17T09:45'),
  vessel('v09', '980335', 'Pacific Crest Harrier', 'c3', '2026-10-04', '2026-10-21T01:10'),
  vessel('v10', '975523', 'Gulf Pioneer', 'c5', '2026-10-01', '2026-10-21T10:25'),
  vessel('v11', '975524', 'Gulf Sentinel', 'c5', '2026-10-03', '2026-10-12T16:00'),
  vessel('v12', '986771', 'Straits Endeavour', 'c4', null, null, { passwordChangedAt: null, lastSignInAt: null }),
]

function device(id: string, platform: Device['platform'], model: string, appVersion: string, enrolledAt: string, firstSyncedAt: string | null, extra: Partial<Device> = {}): Device {
  return { id, platform, model, modelSupported: true, osVersion: platform === 'Android' ? '14' : '17.6', appVersion, status: 'active', enrolledAt, firstSyncedAt, retireRequestedAt: null, retiredAt: null, revokedAt: null, revokeReason: null, ...extra }
}

export const devices: Device[] = [
  device('TAB-0101', 'Android', 'Samsung Galaxy Tab Active5', '1.0.3', '2026-09-30T07:00', '2026-10-01T09:00'),
  device('TAB-0102', 'Android', 'Samsung Galaxy Tab Active5', '1.0.3', '2026-09-30T07:20', '2026-10-01T10:00'),
  device('TAB-0103', 'iOS', 'iPad (10th generation)', '1.0.3', '2026-10-01T06:00', '2026-10-02T09:00'),
  device('TAB-0104', 'Android', 'Samsung Galaxy Tab Active5', '1.0.2', '2026-10-01T06:30', '2026-10-02T09:30'),
  device('TAB-0201', 'iOS', 'iPad (10th generation)', '1.0.3', '2026-09-30T08:00', '2026-10-01T11:00'),
  device('TAB-0202', 'iOS', 'iPad (10th generation)', '1.0.3', '2026-10-02T08:00', '2026-10-03T12:00'),
  device('TAB-0301', 'Android', 'Samsung Galaxy Tab Active5', '1.0.3', '2026-09-30T02:00', '2026-10-01T03:00'),
  device('TAB-0302', 'Android', 'Lenovo Tab M10 (3rd gen)', '1.0.3', '2026-10-01T02:00', '2026-10-02T04:00', { modelSupported: false }),
  device('TAB-0303', 'iOS', 'iPad (10th generation)', '1.0.3', '2026-10-03T02:00', '2026-10-04T05:00'),
  device('TAB-0501', 'Android', 'Samsung Galaxy Tab Active5', '1.0.3', '2026-09-30T12:00', '2026-10-01T15:00'),
  device('TAB-0502', 'Android', 'Samsung Galaxy Tab Active5', '1.0.1', '2026-10-02T12:00', '2026-10-03T16:00'),
  device('TAB-0099', 'Android', 'Samsung Galaxy Tab Active3', '1.0.1', '2026-09-25T07:00', '2026-09-26T08:00', { status: 'retired', retireRequestedAt: '2026-09-29T09:00', retiredAt: '2026-09-30T06:00' }),
]

export const assignments: Assignment[] = [
  ...[['v01', 'TAB-0101'], ['v02', 'TAB-0102'], ['v03', 'TAB-0103'], ['v04', 'TAB-0104'], ['v05', 'TAB-0201'], ['v06', 'TAB-0202'],
    ['v07', 'TAB-0301'], ['v08', 'TAB-0302'], ['v09', 'TAB-0303'], ['v10', 'TAB-0501'], ['v11', 'TAB-0502']].map(([v, d]) => ({
    id: `as-${v}`,
    vessel: v as string,
    device: d as string,
    assignedAt: devices.find((x) => x.id === d)?.enrolledAt ?? NOW,
    unassignedAt: null,
    unassignReason: null,
  })),
  { id: 'as-old', vessel: 'v01', device: 'TAB-0099', assignedAt: '2026-09-25T07:00', unassignedAt: '2026-09-30T06:00', unassignReason: 'device_retired' },
]

export const enrolmentCodes: EnrolmentCode[] = [
  { id: 'ec1', vessel: 'v12', issuedBy: 'u02', issuedAt: '2026-10-20T09:00', expiresAt: '2026-10-23T09:00', status: 'issued' },
]

export const items: Item[] = [
  { articleNo: '179061', product: 'SIGMACOVER 350', shade: 'Grey 5177', productType: '2K', componentType: 'Base', packSize: '20 L', unitVolume: 20 },
  { articleNo: '179063', product: 'SIGMACOVER 350', shade: 'Red brown 6179', productType: '2K', componentType: 'Base', packSize: '20 L', unitVolume: 20 },
  { articleNo: '179062', product: 'SIGMACOVER 350', shade: '', productType: '2K', componentType: 'Hardener', packSize: '5 L', unitVolume: 5 },
  { articleNo: '184102', product: 'SIGMADUR 550', shade: 'White 7000', productType: '2K', componentType: 'Base', packSize: '20 L', unitVolume: 20 },
  { articleNo: '184105', product: 'SIGMADUR 550', shade: 'Signal red 3000', productType: '2K', componentType: 'Base', packSize: '5 L', unitVolume: 5 },
  { articleNo: '184103', product: 'SIGMADUR 550', shade: '', productType: '2K', componentType: 'Hardener', packSize: '2.5 L', unitVolume: 2.5 },
  { articleNo: '181201', product: 'SIGMAPRIME 200', shade: 'Yellow green', productType: '2K', componentType: 'Base', packSize: '20 L', unitVolume: 20 },
  { articleNo: '181202', product: 'SIGMAPRIME 200', shade: '', productType: '2K', componentType: 'Hardener', packSize: '5 L', unitVolume: 5 },
  { articleNo: '187401', product: 'SIGMAGUARD CSF 585', shade: 'Off-white', productType: '2K', componentType: 'Base', packSize: '20 L', unitVolume: 20 },
  { articleNo: '187402', product: 'SIGMAGUARD CSF 585', shade: '', productType: '2K', componentType: 'Hardener', packSize: '5 L', unitVolume: 5 },
  { articleNo: '100292', product: 'PPG THINNER 91-92', shade: '', productType: '1K', componentType: '1K', packSize: '20 L', unitVolume: 20 },
  { articleNo: '100293', product: 'PPG THINNER 21-06', shade: '', productType: '1K', componentType: '1K', packSize: '20 L', unitVolume: 20 },
  { articleNo: '175510', product: 'SIGMACOVER 280', shade: 'Grey 5177', productType: '2K', componentType: 'Base', packSize: '20 L', unitVolume: 20 },
  { articleNo: '175511', product: 'SIGMACOVER 280', shade: '', productType: '2K', componentType: 'Hardener', packSize: '5 L', unitVolume: 5 },
]

const accepted = (sentAt: string) => ({ status: 'accepted' as const, sentAt, expiresAt: sentAt })

export const users: User[] = [
  { id: 'u01', name: 'Dana Whitfield', email: 'dana.whitfield@ppg.example', title: 'Sea Stock administrator', role: 'ppg-admin', scope: { kind: 'all' }, status: 'active', lastSignIn: '2026-10-21T14:05', invite: accepted('2026-09-20T08:00') },
  { id: 'u02', name: 'Lars Eriksen', email: 'lars.eriksen@ppg.example', title: 'Marine sales', role: 'ppg-admin', scope: { kind: 'all' }, status: 'active', lastSignIn: '2026-10-20T09:31', invite: accepted('2026-09-21T08:00') },
  { id: 'u03', name: 'Mei Lin Tan', email: 'meilin.tan@ppg.example', title: 'Marine sales', role: 'ppg-admin', scope: { kind: 'all' }, status: 'active', lastSignIn: '2026-10-21T02:47', invite: accepted('2026-09-21T08:10') },
  { id: 'u05', name: 'Tom Hughes', email: 'tom.hughes@ppg.example', title: 'Marine sales', role: 'ppg-admin', scope: { kind: 'all' }, status: 'disabled', lastSignIn: '2026-09-30T08:00', invite: accepted('2026-09-21T08:20') },
  { id: 'u06', name: 'Ingrid Solberg', email: 'ingrid.solberg@nordhavn.example', title: 'Fleet Manager', role: 'customer-admin', scope: { kind: 'customer', customer: 'c1' }, status: 'active', lastSignIn: '2026-10-21T07:58', invite: accepted('2026-09-22T09:00') },
  { id: 'u07', name: 'Piotr Nowak', email: 'piotr.nowak@nordhavn.example', title: 'Procurement', role: 'customer-admin', scope: { kind: 'customer', customer: 'c1' }, status: 'active', lastSignIn: '2026-10-20T12:20', invite: accepted('2026-09-22T09:05') },
  { id: 'u08', name: 'Sofia Marino', email: 'sofia.marino@meridian.example', title: 'Fleet Manager', role: 'customer-admin', scope: { kind: 'customer', customer: 'c2' }, status: 'active', lastSignIn: '2026-10-18T10:02', invite: accepted('2026-09-22T10:00') },
  { id: 'u09', name: 'Arjun Rao', email: 'arjun.rao@pacificcrest.example', title: 'Fleet Manager', role: 'customer-admin', scope: { kind: 'customer', customer: 'c3' }, status: 'active', lastSignIn: '2026-10-21T03:15', invite: accepted('2026-09-24T03:00') },
  { id: 'u10', name: 'Nur Aisyah', email: 'nur.aisyah@straits.example', title: 'Procurement', role: 'customer-admin', scope: { kind: 'customer', customer: 'c4' }, status: 'invited', lastSignIn: null, invite: { status: 'pending', sentAt: '2026-10-20T04:00', expiresAt: '2026-10-27T04:00' } },
  { id: 'u11', name: 'Emily Brooks', email: 'emily.brooks@atlanticgulf.example', title: 'Fleet Manager', role: 'customer-admin', scope: { kind: 'customer', customer: 'c5' }, status: 'active', lastSignIn: '2026-10-20T15:40', invite: accepted('2026-09-26T14:00') },
  { id: 'u12', name: 'Priya Nair', email: 'priya.nair@meridian.example', title: 'Procurement', role: 'customer-admin', scope: { kind: 'customer', customer: 'c2' }, status: 'invited', lastSignIn: null, invite: { status: 'expired', sentAt: '2026-10-05T09:00', expiresAt: '2026-10-12T09:00' } },
]

/** The vessel's active tablet, from the assignments. */
export function activeDeviceOf(vesselId: string): string | null {
  return assignments.find((a) => a.vessel === vesselId && a.unassignedAt === null)?.device ?? null
}

export const deliveryNotes: DeliveryNote[] = [
  {
    dnNumber: '5324641215', dnDate: '2026-10-14', vessel: 'v01', device: 'TAB-0101', customerReference: 'PO 4500912273',
    imoOnNote: imoWithCheckDigit('981234'), vesselNameOnNote: 'NORDHAVN AURORA', imoCheck: 'match',
    capturedAt: '2026-10-14T15:20', confirmedAt: '2026-10-14T15:42', receivedAt: '2026-10-14T19:05',
    lines: [
      { articleNo: '179061', dnCans: 8, receivedCans: 8, result: 'matched' },
      { articleNo: '179062', dnCans: 6, receivedCans: 6, result: 'matched' },
      { articleNo: '184102', dnCans: 4, receivedCans: 3, result: 'short', reason: 'One can dented and leaking; not taken into the locker.' },
      { articleNo: '184103', dnCans: 4, receivedCans: 4, result: 'matched' },
      { articleNo: '100293', dnCans: 2, receivedCans: 3, result: 'over', reason: 'Three cans delivered; the note lists two.' },
      { articleNo: '181201', dnCans: null, receivedCans: 2, result: 'not-on-note', reason: 'Delivered with this order but not listed on the note.' },
    ],
  },
  {
    dnNumber: '5324650871', dnDate: '2026-10-09', vessel: 'v05', device: 'TAB-0201', customerReference: 'PO 4500913390',
    imoOnNote: imoWithCheckDigit('984660'), vesselNameOnNote: 'MERIDIAN VALENCIA', imoCheck: 'match',
    capturedAt: '2026-10-09T10:05', confirmedAt: '2026-10-09T10:20', receivedAt: '2026-10-09T18:44',
    lines: [
      { articleNo: '184102', dnCans: 6, receivedCans: 6, result: 'matched' },
      { articleNo: '184103', dnCans: 8, receivedCans: 8, result: 'matched' },
      { articleNo: '100292', dnCans: 4, receivedCans: 4, result: 'matched' },
    ],
  },
  {
    dnNumber: '5324655402', dnDate: '2026-10-11', vessel: 'v07', device: 'TAB-0301', customerReference: 'SO-88213',
    imoOnNote: null, vesselNameOnNote: 'PACIFIC CREST OSPREY', imoCheck: 'not_read',
    capturedAt: '2026-10-11T01:50', confirmedAt: '2026-10-11T02:05', receivedAt: '2026-10-12T04:30',
    lines: [
      { articleNo: '187401', dnCans: 10, receivedCans: 10, result: 'matched' },
      { articleNo: '187402', dnCans: 8, receivedCans: 8, result: 'matched' },
      { articleNo: '100293', dnCans: 4, receivedCans: 0, result: 'not-received', reason: 'Not on the barge; supplier to send with the next delivery.' },
      { articleNo: '189955', dnCans: 2, receivedCans: 2, result: 'matched' },
    ],
  },
  {
    dnNumber: '5324660119', dnDate: '2026-10-16', vessel: 'v10', device: 'TAB-0501', customerReference: 'PO 77120-GP',
    imoOnNote: imoWithCheckDigit('975523'), vesselNameOnNote: 'GULF PIONEER', imoCheck: 'match',
    capturedAt: '2026-10-16T13:55', confirmedAt: '2026-10-16T14:10', receivedAt: '2026-10-16T21:02',
    lines: [
      { articleNo: '179061', dnCans: 6, receivedCans: 6, result: 'matched' },
      { articleNo: '179062', dnCans: 4, receivedCans: 4, result: 'matched' },
      { articleNo: '100293', dnCans: 3, receivedCans: 3, result: 'matched' },
    ],
  },
  {
    dnNumber: '5324662580', dnDate: '2026-10-18', vessel: 'v02', device: 'TAB-0102', customerReference: 'PO 4500914028',
    imoOnNote: imoWithCheckDigit('981235'), vesselNameOnNote: 'NORDHAVN BOREALIS', imoCheck: 'match',
    capturedAt: '2026-10-18T08:40', confirmedAt: '2026-10-18T08:55', receivedAt: '2026-10-18T16:20',
    lines: [
      { articleNo: '179061', dnCans: 4, receivedCans: 4, result: 'matched' },
      { articleNo: '179062', dnCans: 4, receivedCans: 4, result: 'matched' },
      { articleNo: '184102', dnCans: 2, receivedCans: 2, result: 'matched' },
      { articleNo: '184103', dnCans: 2, receivedCans: 2, result: 'matched' },
    ],
  },
  {
    // The IMO on the paper is a sister ship's: received on this vessel anyway, listed for review.
    dnNumber: '5324664017', dnDate: '2026-10-20', vessel: 'v09', device: 'TAB-0303', customerReference: 'SO-88407',
    imoOnNote: imoWithCheckDigit('977121'), vesselNameOnNote: 'PACIFIC CREST KESTREL', imoCheck: 'mismatch',
    capturedAt: '2026-10-20T07:15', confirmedAt: '2026-10-20T07:30', receivedAt: '2026-10-21T01:10',
    lines: [
      { articleNo: '179063', dnCans: 6, receivedCans: 6, result: 'matched' },
      { articleNo: '179062', dnCans: 4, receivedCans: 5, result: 'over', reason: 'One extra hardener can delivered.' },
    ],
  },
]

/** Opening stock per vessel (FR-08), [article, cans]. */
const baselines: Record<string, [string, number][]> = {
  v01: [['179061', 10], ['179062', 8], ['184102', 6], ['184103', 6], ['100293', 4], ['181201', 4], ['181202', 3]],
  v02: [['179061', 6], ['179062', 5], ['184102', 4], ['184103', 4], ['100292', 3]],
  v03: [['179063', 8], ['179062', 6], ['187401', 4], ['187402', 4], ['100293', 2]],
  v04: [['179061', 4], ['179062', 3], ['100293', 2]],
  v05: [['184102', 10], ['184105', 6], ['184103', 12], ['100292', 5], ['181201', 6], ['181202', 5]],
  v06: [['184102', 5], ['184103', 2], ['100292', 2]],
  v07: [['187401', 12], ['187402', 10], ['100293', 6], ['179061', 4], ['179062', 3]],
  v08: [['187401', 8], ['187402', 7], ['100293', 4]],
  v09: [['179063', 6], ['179062', 5], ['184102', 4], ['184103', 4], ['100292', 3]],
  v10: [['179061', 9], ['179062', 7], ['184102', 6], ['184103', 6], ['100293', 4]],
  v11: [['181201', 5], ['181202', 4], ['184102', 3], ['184103', 3], ['100292', 2]],
}

/** Cans taken from the locker (FR-07): [vessel, article, cans, recorded at]. */
const consumption: [string, string, number, string][] = [
  ['v01', '179061', 2, '2026-10-03T09:10'], ['v01', '179062', 2, '2026-10-03T09:11'],
  ['v01', '179061', 3, '2026-10-10T08:40'], ['v01', '179062', 2, '2026-10-10T08:41'],
  ['v01', '100293', 1, '2026-10-10T08:42'], ['v01', '184102', 2, '2026-10-17T13:05'],
  ['v01', '184103', 2, '2026-10-17T13:06'], ['v01', '179061', 2, '2026-10-20T07:55'],
  ['v01', '179062', 1, '2026-10-20T07:56'],
  ['v02', '179061', 2, '2026-10-06T10:00'], ['v02', '179062', 1, '2026-10-06T10:01'],
  ['v02', '100292', 1, '2026-10-12T14:30'], ['v02', '184102', 1, '2026-10-19T09:15'],
  ['v02', '184103', 1, '2026-10-19T09:16'],
  ['v03', '179063', 4, '2026-10-08T07:20'], ['v03', '179062', 3, '2026-10-08T07:21'],
  ['v03', '187401', 2, '2026-10-15T11:00'], ['v03', '187402', 2, '2026-10-15T11:01'],
  ['v04', '179061', 3, '2026-10-05T08:00'], ['v04', '179062', 2, '2026-10-05T08:01'],
  ['v04', '100293', 1, '2026-10-05T08:02'],
  ['v05', '184102', 4, '2026-10-04T06:45'], ['v05', '184103', 5, '2026-10-04T06:46'],
  ['v05', '184105', 2, '2026-10-13T10:10'], ['v05', '184103', 1, '2026-10-13T10:11'],
  ['v05', '181201', 2, '2026-10-18T07:30'], ['v05', '181202', 2, '2026-10-18T07:31'],
  ['v06', '184102', 2, '2026-10-07T09:50'], ['v06', '184103', 4, '2026-10-07T09:51'],
  ['v06', '100292', 1, '2026-10-07T09:52'],
  ['v07', '187401', 5, '2026-10-06T01:15'], ['v07', '187402', 4, '2026-10-06T01:16'],
  ['v07', '100293', 2, '2026-10-06T01:17'], ['v07', '187401', 4, '2026-10-16T00:50'],
  ['v07', '187402', 3, '2026-10-16T00:51'],
  ['v08', '187401', 3, '2026-10-09T03:30'], ['v08', '187402', 3, '2026-10-09T03:31'],
  ['v08', '100293', 1, '2026-10-09T03:32'],
  ['v09', '179063', 3, '2026-10-12T02:20'], ['v09', '179062', 2, '2026-10-12T02:21'],
  ['v09', '184102', 1, '2026-10-19T05:40'],
  ['v10', '179061', 4, '2026-10-08T13:00'], ['v10', '179062', 3, '2026-10-08T13:01'],
  ['v10', '100293', 2, '2026-10-08T13:02'], ['v10', '184102', 2, '2026-10-18T15:20'],
  ['v10', '184103', 2, '2026-10-18T15:21'],
  ['v11', '181201', 2, '2026-10-11T12:30'], ['v11', '181202', 2, '2026-10-11T12:31'],
  ['v11', '100292', 1, '2026-10-11T12:32'],
  // Recorded after the last sync: still on the tablet, so not shown in the portal.
  ['v11', '184102', 1, '2026-10-19T10:00'],
]

/** Stock corrections made on the tablet (FR-13): [vessel, article, cans, recorded at, reason]. */
const tabletAdjustments: [string, string, number, string, string][] = [
  ['v03', '187402', -1, '2026-10-17T10:30', 'Can found damaged during a locker check; disposed of.'],
  ['v08', '100293', 1, '2026-10-13T05:00', 'Can found in the locker that was missed in the opening count.'],
]

function addHours(at: string, hours: number): string {
  const d = new Date(`${at}:00Z`)
  d.setUTCHours(d.getUTCHours() + hours)
  return d.toISOString().slice(0, 16)
}

/** When a tablet row reached the server: about a day later, never after the last sync. */
function receivedAt(vesselId: string, recordedAt: string): string | null {
  const last = vessels.find((v) => v.id === vesselId)?.lastSync
  if (!last || recordedAt > last) return null
  const next = addHours(recordedAt, 20)
  return next < last ? next : last
}

function buildTransactions(): Transaction[] {
  const out: Omit<Transaction, 'id'>[] = []
  const fromTablet = (t: Omit<Transaction, 'id' | 'origin' | 'device' | 'recordedBy' | 'receivedAt'>) => {
    const at = receivedAt(t.vessel, t.recordedAt)
    if (!at) return
    out.push({ ...t, origin: 'device', device: activeDeviceOf(t.vessel), recordedBy: null, receivedAt: at })
  }
  const known = (articleNo: string) => items.some((i) => i.articleNo === articleNo)

  for (const [vesselId, lines] of Object.entries(baselines)) {
    const on = vessels.find((v) => v.id === vesselId)?.baselineOn ?? '2026-10-01'
    lines.forEach(([articleNo, cans], i) =>
      fromTablet({ type: 'baseline', vessel: vesselId, articleNo, cans, recordedAt: `${on}T08:${String(10 + i).padStart(2, '0')}`, source: 'Label scan' }),
    )
  }
  for (const dn of deliveryNotes) {
    for (const line of dn.lines) {
      // Unknown article numbers are held as unrecognised scans, not posted.
      if (line.receivedCans === 0 || !known(line.articleNo)) continue
      fromTablet({ type: 'receipt', vessel: dn.vessel, articleNo: line.articleNo, cans: line.receivedCans, recordedAt: dn.confirmedAt, source: 'DN scan', dn: dn.dnNumber })
    }
  }
  for (const [vesselId, articleNo, cans, recordedAt] of consumption) {
    fromTablet({ type: 'consumption', vessel: vesselId, articleNo, cans: -cans, recordedAt, source: 'Label scan' })
  }
  for (const [vesselId, articleNo, cans, recordedAt, reason] of tabletAdjustments) {
    fromTablet({ type: 'adjustment', vessel: vesselId, articleNo, cans, recordedAt, source: 'Manual adjustment', reason })
  }
  // A correction made on the portal by a Customer Admin: names the person, no tablet.
  out.push({ type: 'adjustment', vessel: 'v02', articleNo: '184103', cans: 1, origin: 'portal', device: null, recordedBy: 'u06', recordedAt: '2026-10-20T11:00', receivedAt: '2026-10-20T11:00', source: 'Manual adjustment', reason: 'Crew confirmed by phone: one hardener can was left out of the 19 Oct count.' })
  return out
    .sort((a, b) => b.recordedAt.localeCompare(a.recordedAt))
    .map((t, i, all) => ({ ...t, id: `TX-${String(10000 + all.length - i)}` }))
}

/** The synced stock ledger (FR-11). Sea Stock is worked out from it. */
export const transactions: Transaction[] = buildTransactions()

/** Not in Sea Stock until a PPG Admin matches them to an article (no product-and-shade guessing). */
export const unrecognisedScans: UnrecognisedScan[] = [
  { id: 'us1', vessel: 'v07', device: 'TAB-0301', kind: 'receipt', rawArticleNo: '189955', rawLabel: { product: 'SIGMASHIELD 1200', shade: 'Grey' }, cans: 2, recordedAt: '2026-10-11T02:05', receivedAt: '2026-10-12T04:30', dn: '5324655402', status: 'open', matchedArticle: null, matchedBy: null, matchedAt: null },
  { id: 'us2', vessel: 'v10', device: 'TAB-0501', kind: 'consumption', rawArticleNo: '18452O', rawLabel: { product: 'SIGMADUR 520', shade: 'Black 9000' }, cans: 1, recordedAt: '2026-10-18T15:25', receivedAt: '2026-10-19T11:25', status: 'open', matchedArticle: null, matchedBy: null, matchedAt: null },
  { id: 'us3', vessel: 'v01', device: 'TAB-0101', kind: 'consumption', rawArticleNo: '17906l', rawLabel: { product: 'SIGMACOVER 350', shade: 'Grey 5177' }, cans: 1, recordedAt: '2026-10-20T07:58', receivedAt: '2026-10-21T03:58', status: 'open', matchedArticle: null, matchedBy: null, matchedAt: null },
]

/** Uploaded events the server could not apply, held for an admin. */
export const quarantinedEvents: QuarantinedEvent[] = [
  { id: 'qe1', vessel: 'v05', device: 'TAB-0201', eventType: 'delivery_note', errorCode: 'duplicate_dn_number', errorDetail: 'DN 5324650871 was already received on this vessel on 9 Oct.', summary: 'Delivery note 5324650871, 3 lines, 18 cans', receivedAt: '2026-10-21T05:50', status: 'open', resolvedBy: null, resolvedAt: null, resolutionNote: null },
  { id: 'qe2', vessel: 'v08', device: 'TAB-0302', eventType: 'adjustment', errorCode: 'reason_required', errorDetail: 'An adjustment needs a reason.', summary: 'Adjustment −2 cans of 187401 SIGMAGUARD CSF 585', receivedAt: '2026-10-17T09:45', status: 'open', resolvedBy: null, resolvedAt: null, resolutionNote: null },
  { id: 'qe3', vessel: 'v02', device: 'TAB-0102', eventType: 'item', errorCode: 'invalid_quantity', errorDetail: 'Quantity must be at least 1.', summary: 'Consumption 0 cans of 179061 SIGMACOVER 350', receivedAt: '2026-10-15T16:20', status: 'dismissed', resolvedBy: 'u01', resolvedAt: '2026-10-16T09:00', resolutionNote: 'Empty scan by mistake; nothing to post.' },
]

export const auditLog: AuditEntry[] = [
  { id: 'a01', at: '2026-10-21T14:05', actorType: 'user', actor: 'u01', vessel: null, customer: null, category: 'users', summary: 'Dana Whitfield signed in.' },
  { id: 'a02', at: '2026-10-21T10:25', actorType: 'device', actor: 'TAB-0501', vessel: 'v10', customer: 'c5', category: 'sync', summary: 'Gulf Pioneer synced: 4 events applied.' },
  { id: 'a03', at: '2026-10-21T05:50', actorType: 'device', actor: 'TAB-0201', vessel: 'v05', customer: 'c2', category: 'sync', summary: 'Meridian Valencia synced: 2 applied, 1 held (duplicate delivery note).' },
  { id: 'a04', at: '2026-10-20T11:00', actorType: 'user', actor: 'u06', vessel: 'v02', customer: 'c1', category: 'inventory', summary: 'Ingrid Solberg adjusted Nordhavn Borealis: +1 can of 184103 SIGMADUR 550.' },
  { id: 'a05', at: '2026-10-20T09:00', actorType: 'user', actor: 'u02', vessel: 'v12', customer: 'c4', category: 'devices', summary: 'Lars Eriksen issued an enrolment code for Straits Endeavour (expires 23 Oct).' },
  { id: 'a06', at: '2026-10-20T04:00', actorType: 'user', actor: 'u01', vessel: null, customer: 'c4', category: 'users', summary: 'Dana Whitfield invited Nur Aisyah as Customer Admin of Straits Offshore Services.' },
  { id: 'a07', at: '2026-10-16T09:00', actorType: 'user', actor: 'u01', vessel: 'v02', customer: 'c1', category: 'sync', summary: 'Dana Whitfield dismissed a held event from Nordhavn Borealis: empty scan by mistake.' },
  { id: 'a08', at: '2026-10-15T08:00', actorType: 'user', actor: 'u01', vessel: null, customer: 'c4', category: 'customers_vessels', summary: 'Dana Whitfield added customer Straits Offshore Services (C-208190).' },
  { id: 'a10', at: '2026-10-12T09:00', actorType: 'user', actor: 'u06', vessel: 'v04', customer: 'c1', category: 'customers_vessels', summary: 'Ingrid Solberg recorded a password reset for Nordhavn Skagen (crew change).' },
  { id: 'a11', at: '2026-10-02T06:30', actorType: 'device', actor: 'TAB-0104', vessel: 'v04', customer: 'c1', category: 'devices', summary: 'Tablet TAB-0104 enrolled on Nordhavn Skagen.' },
  { id: 'a12', at: '2026-09-30T06:00', actorType: 'system', actor: null, vessel: 'v01', customer: 'c1', category: 'devices', summary: 'Tablet TAB-0099 retired after its final sync.' },
]
