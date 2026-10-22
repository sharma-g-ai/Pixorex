/**
 * Sample data for the static screens. Names, IDs and e-mail addresses are made up;
 * product names and article numbers follow the BRD examples (DN 5324641215, SIGMACOVER 350,
 * article 179061) and are placeholders until PPG provides the master item list (D-02).
 * All times are UTC.
 */
import type {
  Customer,
  DeliveryNote,
  Item,
  LabelField,
  Region,
  Transaction,
  UnrecognisedScan,
  User,
  Vessel,
} from './model'

/** "Now" for the static screens. */
export const NOW = '2026-10-21T16:00'

export const regions: Region[] = [
  { code: 'APAC', name: 'Asia Pacific' },
  { code: 'EMEA', name: 'Europe, Middle East and Africa' },
  { code: 'USCA', name: 'United States and Canada' },
]

export const customers: Customer[] = [
  { id: 'c1', customerId: 'C-104512', name: 'Nordhavn Bulk Carriers', region: 'EMEA', status: 'active', addedOn: '2026-09-22' },
  { id: 'c2', customerId: 'C-104530', name: 'Meridian Container Lines', region: 'EMEA', status: 'active', addedOn: '2026-09-22' },
  { id: 'c3', customerId: 'C-208114', name: 'Pacific Crest Tankers', region: 'APAC', status: 'active', addedOn: '2026-09-24' },
  { id: 'c4', customerId: 'C-208190', name: 'Straits Offshore Services', region: 'APAC', status: 'active', addedOn: '2026-10-15' },
  { id: 'c5', customerId: 'C-310077', name: 'Atlantic Gulf Marine', region: 'USCA', status: 'active', addedOn: '2026-09-26' },
]

/** IMO number with its check digit (weights 7..2 over the first six digits). */
function imo(six: string): string {
  const sum = [...six].reduce((acc, d, i) => acc + Number(d) * (7 - i), 0)
  return `IMO ${six}${sum % 10}`
}

export const vessels: Vessel[] = [
  { id: 'v01', vesselId: 'V-50110', imo: imo('981234'), name: 'Nordhavn Aurora', customer: 'c1', device: { id: 'TAB-0101', platform: 'Android', appVersion: '1.0.3' }, baselineOn: '2026-10-01', lastSync: '2026-10-21T08:12', status: 'active' },
  { id: 'v02', vesselId: 'V-50111', imo: imo('981235'), name: 'Nordhavn Borealis', customer: 'c1', device: { id: 'TAB-0102', platform: 'Android', appVersion: '1.0.3' }, baselineOn: '2026-10-01', lastSync: '2026-10-20T22:40', status: 'active' },
  { id: 'v03', vesselId: 'V-50112', imo: imo('979041'), name: 'Nordhavn Fjord', customer: 'c1', device: { id: 'TAB-0103', platform: 'iOS', appVersion: '1.0.3' }, baselineOn: '2026-10-02', lastSync: '2026-10-19T06:15', status: 'active' },
  { id: 'v04', vesselId: 'V-50113', imo: imo('979042'), name: 'Nordhavn Skagen', customer: 'c1', device: { id: 'TAB-0104', platform: 'Android', appVersion: '1.0.2' }, baselineOn: '2026-10-02', lastSync: '2026-10-14T11:30', status: 'active' },
  { id: 'v05', vesselId: 'V-50210', imo: imo('984660'), name: 'Meridian Valencia', customer: 'c2', device: { id: 'TAB-0201', platform: 'iOS', appVersion: '1.0.3' }, baselineOn: '2026-10-01', lastSync: '2026-10-21T05:50', status: 'active' },
  { id: 'v06', vesselId: 'V-50211', imo: imo('984661'), name: 'Meridian Genoa', customer: 'c2', device: { id: 'TAB-0202', platform: 'iOS', appVersion: '1.0.3' }, baselineOn: '2026-10-03', lastSync: '2026-10-18T13:05', status: 'active' },
  { id: 'v07', vesselId: 'V-60310', imo: imo('977120'), name: 'Pacific Crest Osprey', customer: 'c3', device: { id: 'TAB-0301', platform: 'Android', appVersion: '1.0.3' }, baselineOn: '2026-10-01', lastSync: '2026-10-20T03:20', status: 'active' },
  { id: 'v08', vesselId: 'V-60311', imo: imo('977121'), name: 'Pacific Crest Kestrel', customer: 'c3', device: { id: 'TAB-0302', platform: 'Android', appVersion: '1.0.3' }, baselineOn: '2026-10-02', lastSync: '2026-10-17T09:45', status: 'active' },
  { id: 'v09', vesselId: 'V-60312', imo: imo('980335'), name: 'Pacific Crest Harrier', customer: 'c3', device: { id: 'TAB-0303', platform: 'iOS', appVersion: '1.0.3' }, baselineOn: '2026-10-04', lastSync: '2026-10-21T01:10', status: 'active' },
  { id: 'v10', vesselId: 'V-70410', imo: imo('975523'), name: 'Gulf Pioneer', customer: 'c5', device: { id: 'TAB-0501', platform: 'Android', appVersion: '1.0.3' }, baselineOn: '2026-10-01', lastSync: '2026-10-21T10:25', status: 'active' },
  { id: 'v11', vesselId: 'V-70411', imo: imo('975524'), name: 'Gulf Sentinel', customer: 'c5', device: { id: 'TAB-0502', platform: 'Android', appVersion: '1.0.1' }, baselineOn: '2026-10-03', lastSync: '2026-10-12T16:00', status: 'active' },
  { id: 'v12', vesselId: 'V-60420', imo: imo('986771'), name: 'Straits Endeavour', customer: 'c4', device: { id: 'TAB-0401', platform: 'Android', appVersion: '1.0.3' }, baselineOn: null, lastSync: null, status: 'active' },
]

export const items: Item[] = [
  { articleNo: '179061', product: 'SIGMACOVER 350', shade: 'Grey 5177', componentType: 'Base', packSize: '20 L', unitVolume: 20, status: 'active' },
  { articleNo: '179063', product: 'SIGMACOVER 350', shade: 'Red brown 6179', componentType: 'Base', packSize: '20 L', unitVolume: 20, status: 'active' },
  { articleNo: '179062', product: 'SIGMACOVER 350', shade: '', componentType: 'Hardener', packSize: '5 L', unitVolume: 5, status: 'active' },
  { articleNo: '184102', product: 'SIGMADUR 550', shade: 'White 7000', componentType: 'Base', packSize: '20 L', unitVolume: 20, status: 'active' },
  { articleNo: '184105', product: 'SIGMADUR 550', shade: 'Signal red 3000', componentType: 'Base', packSize: '5 L', unitVolume: 5, status: 'active' },
  { articleNo: '184103', product: 'SIGMADUR 550', shade: '', componentType: 'Hardener', packSize: '2.5 L', unitVolume: 2.5, status: 'active' },
  { articleNo: '181201', product: 'SIGMAPRIME 200', shade: 'Yellow green', componentType: 'Base', packSize: '20 L', unitVolume: 20, status: 'active' },
  { articleNo: '181202', product: 'SIGMAPRIME 200', shade: '', componentType: 'Hardener', packSize: '5 L', unitVolume: 5, status: 'active' },
  { articleNo: '187401', product: 'SIGMAGUARD CSF 585', shade: 'Off-white', componentType: 'Base', packSize: '20 L', unitVolume: 20, status: 'active' },
  { articleNo: '187402', product: 'SIGMAGUARD CSF 585', shade: '', componentType: 'Hardener', packSize: '5 L', unitVolume: 5, status: 'active' },
  { articleNo: '100292', product: 'PPG THINNER 91-92', shade: '', componentType: '1K', packSize: '20 L', unitVolume: 20, status: 'active' },
  { articleNo: '100293', product: 'PPG THINNER 21-06', shade: '', componentType: '1K', packSize: '20 L', unitVolume: 20, status: 'active' },
  { articleNo: '175510', product: 'SIGMACOVER 280', shade: 'Grey 5177', componentType: 'Base', packSize: '20 L', unitVolume: 20, status: 'retired' },
  { articleNo: '175511', product: 'SIGMACOVER 280', shade: '', componentType: 'Hardener', packSize: '5 L', unitVolume: 5, status: 'retired' },
]

export const users: User[] = [
  { id: 'u01', name: 'Dana Whitfield', email: 'dana.whitfield@ppg.example', title: 'Sea Stock administrator', role: 'ppg-admin', scope: { kind: 'all' }, status: 'active', lastSignIn: '2026-10-21T14:05' },
  { id: 'u02', name: 'Lars Eriksen', email: 'lars.eriksen@ppg.example', title: 'Marine sales', role: 'ppg-admin', scope: { kind: 'regions', regions: ['EMEA'] }, status: 'active', lastSignIn: '2026-10-20T09:31' },
  { id: 'u03', name: 'Mei Lin Tan', email: 'meilin.tan@ppg.example', title: 'Marine sales', role: 'ppg-admin', scope: { kind: 'customers', customers: ['c3', 'c4'] }, status: 'active', lastSignIn: '2026-10-21T02:47' },
  { id: 'u04', name: 'Carlos Rivera', email: 'carlos.rivera@ppg.example', title: 'Marine sales', role: 'ppg-admin', scope: { kind: 'regions', regions: ['USCA'] }, status: 'active', lastSignIn: '2026-10-19T17:12' },
  { id: 'u05', name: 'Tom Hughes', email: 'tom.hughes@ppg.example', title: 'Marine sales', role: 'ppg-admin', scope: { kind: 'regions', regions: ['EMEA'] }, status: 'disabled', lastSignIn: '2026-09-30T08:00' },
  { id: 'u06', name: 'Ingrid Solberg', email: 'ingrid.solberg@nordhavn.example', title: 'Fleet Manager', role: 'customer-admin', scope: { kind: 'customer', customer: 'c1' }, status: 'active', lastSignIn: '2026-10-21T07:58' },
  { id: 'u07', name: 'Piotr Nowak', email: 'piotr.nowak@nordhavn.example', title: 'Procurement', role: 'customer-admin', scope: { kind: 'customer', customer: 'c1' }, status: 'active', lastSignIn: '2026-10-20T12:20' },
  { id: 'u08', name: 'Sofia Marino', email: 'sofia.marino@meridian.example', title: 'Fleet Manager', role: 'customer-admin', scope: { kind: 'customer', customer: 'c2' }, status: 'active', lastSignIn: '2026-10-18T10:02' },
  { id: 'u09', name: 'Arjun Rao', email: 'arjun.rao@pacificcrest.example', title: 'Fleet Manager', role: 'customer-admin', scope: { kind: 'customer', customer: 'c3' }, status: 'active', lastSignIn: '2026-10-21T03:15' },
  { id: 'u10', name: 'Nur Aisyah', email: 'nur.aisyah@straits.example', title: 'Procurement', role: 'customer-admin', scope: { kind: 'customer', customer: 'c4' }, status: 'invited', lastSignIn: null },
  { id: 'u11', name: 'Emily Brooks', email: 'emily.brooks@atlanticgulf.example', title: 'Fleet Manager', role: 'customer-admin', scope: { kind: 'customer', customer: 'c5' }, status: 'active', lastSignIn: '2026-10-20T15:40' },
  { id: 'u12', name: 'Erik Lund', email: 'co.aurora@nordhavn.example', title: 'Chief Officer', role: 'ship-admin', scope: { kind: 'vessel', vessel: 'v01' }, status: 'active', lastSignIn: '2026-10-20T06:30' },
  { id: 'u13', name: 'Jonas Berg', email: 'co.borealis@nordhavn.example', title: 'Chief Officer', role: 'ship-admin', scope: { kind: 'vessel', vessel: 'v02' }, status: 'active', lastSignIn: '2026-10-19T05:10' },
  { id: 'u14', name: 'Mikkel Dahl', email: 'co.fjord@nordhavn.example', title: 'Chief Officer', role: 'ship-admin', scope: { kind: 'vessel', vessel: 'v03' }, status: 'active', lastSignIn: '2026-10-15T07:45' },
  { id: 'u15', name: 'Henrik Moe', email: 'co.skagen@nordhavn.example', title: 'Chief Officer', role: 'ship-admin', scope: { kind: 'vessel', vessel: 'v04' }, status: 'active', lastSignIn: '2026-10-05T08:20' },
  { id: 'u16', name: 'Marco Ferri', email: 'co.valencia@meridian.example', title: 'Chief Officer', role: 'ship-admin', scope: { kind: 'vessel', vessel: 'v05' }, status: 'active', lastSignIn: '2026-10-18T09:00' },
  { id: 'u17', name: 'Luca Bianchi', email: 'co.genoa@meridian.example', title: 'Chief Officer', role: 'ship-admin', scope: { kind: 'vessel', vessel: 'v06' }, status: 'active', lastSignIn: '2026-10-07T11:25' },
  { id: 'u18', name: 'Rizal Santos', email: 'co.osprey@pacificcrest.example', title: 'Chief Officer', role: 'ship-admin', scope: { kind: 'vessel', vessel: 'v07' }, status: 'active', lastSignIn: '2026-10-16T01:40' },
  { id: 'u19', name: 'Thanh Nguyen', email: 'co.kestrel@pacificcrest.example', title: 'Chief Officer', role: 'ship-admin', scope: { kind: 'vessel', vessel: 'v08' }, status: 'active', lastSignIn: '2026-10-13T04:10' },
  { id: 'u20', name: 'Kenji Sato', email: 'co.harrier@pacificcrest.example', title: 'Chief Officer', role: 'ship-admin', scope: { kind: 'vessel', vessel: 'v09' }, status: 'active', lastSignIn: '2026-10-20T00:35' },
  { id: 'u21', name: 'James Carter', email: 'co.pioneer@atlanticgulf.example', title: 'Chief Officer', role: 'ship-admin', scope: { kind: 'vessel', vessel: 'v10' }, status: 'active', lastSignIn: '2026-10-18T13:15' },
  { id: 'u22', name: 'Daniel Ortiz', email: 'co.sentinel@atlanticgulf.example', title: 'Chief Officer', role: 'ship-admin', scope: { kind: 'vessel', vessel: 'v11' }, status: 'active', lastSignIn: '2026-10-11T12:00' },
  { id: 'u23', name: 'Ahmad Faisal', email: 'co.endeavour@straits.example', title: 'Chief Officer', role: 'ship-admin', scope: { kind: 'vessel', vessel: 'v12' }, status: 'invited', lastSignIn: null },
]

/** The vessel user who records on each vessel's device. */
function crewOf(vessel: string): User {
  const user = users.find((u) => u.scope.kind === 'vessel' && u.scope.vessel === vessel)
  if (!user) throw new Error(`No vessel user for ${vessel}`)
  return user
}

export const deliveryNotes: DeliveryNote[] = [
  {
    dnNumber: '5324641215', dnDate: '2026-10-14', vessel: 'v01', customerReference: 'PO 4500912273',
    capturedBy: 'u12', capturedAt: '2026-10-14T15:42', syncedAt: '2026-10-14T19:05',
    lines: [
      { articleNo: '179061', dnCans: 8, receivedCans: 8, result: 'matched' },
      { articleNo: '179062', dnCans: 6, receivedCans: 6, result: 'matched' },
      { articleNo: '184102', dnCans: 4, receivedCans: 3, result: 'short', reason: 'One can dented and leaking; not taken into the locker.' },
      { articleNo: '184103', dnCans: 4, receivedCans: 4, result: 'matched' },
      { articleNo: '100293', dnCans: 2, receivedCans: 3, result: 'over', reason: 'Three cans delivered; the note lists two.' },
      { articleNo: '181201', dnCans: 0, receivedCans: 2, result: 'not-on-note', reason: 'Delivered with this order but not listed on the note.' },
    ],
  },
  {
    dnNumber: '5324650871', dnDate: '2026-10-09', vessel: 'v05', customerReference: 'PO 4500913390',
    capturedBy: 'u16', capturedAt: '2026-10-09T10:20', syncedAt: '2026-10-09T18:44',
    lines: [
      { articleNo: '184102', dnCans: 6, receivedCans: 6, result: 'matched' },
      { articleNo: '184103', dnCans: 8, receivedCans: 8, result: 'matched' },
      { articleNo: '100292', dnCans: 4, receivedCans: 4, result: 'matched' },
    ],
  },
  {
    dnNumber: '5324655402', dnDate: '2026-10-11', vessel: 'v07', customerReference: 'SO-88213',
    capturedBy: 'u18', capturedAt: '2026-10-11T02:05', syncedAt: '2026-10-12T04:30',
    lines: [
      { articleNo: '187401', dnCans: 10, receivedCans: 10, result: 'matched' },
      { articleNo: '187402', dnCans: 8, receivedCans: 8, result: 'matched' },
      { articleNo: '100293', dnCans: 4, receivedCans: 0, result: 'not-received', reason: 'Not on the barge; supplier to send with the next delivery.' },
    ],
  },
  {
    dnNumber: '5324660119', dnDate: '2026-10-16', vessel: 'v10', customerReference: 'PO 77120-GP',
    capturedBy: 'u21', capturedAt: '2026-10-16T14:10', syncedAt: '2026-10-16T21:02',
    lines: [
      { articleNo: '179061', dnCans: 6, receivedCans: 6, result: 'matched' },
      { articleNo: '179062', dnCans: 4, receivedCans: 4, result: 'matched' },
      { articleNo: '100293', dnCans: 3, receivedCans: 3, result: 'matched' },
    ],
  },
  {
    dnNumber: '5324662580', dnDate: '2026-10-18', vessel: 'v02', customerReference: 'PO 4500914028',
    capturedBy: 'u13', capturedAt: '2026-10-18T08:55', syncedAt: '2026-10-18T16:20',
    lines: [
      { articleNo: '179061', dnCans: 4, receivedCans: 4, result: 'matched' },
      { articleNo: '179062', dnCans: 4, receivedCans: 4, result: 'matched' },
      { articleNo: '184102', dnCans: 2, receivedCans: 2, result: 'matched' },
      { articleNo: '184103', dnCans: 2, receivedCans: 2, result: 'matched' },
    ],
  },
  {
    dnNumber: '5324664017', dnDate: '2026-10-20', vessel: 'v09', customerReference: 'SO-88407',
    capturedBy: 'u20', capturedAt: '2026-10-20T07:30', syncedAt: '2026-10-21T01:10',
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
  // Recorded after the last sync: still on the device, so not shown in the portal.
  ['v11', '184102', 1, '2026-10-19T10:00'],
]

/** Stock corrections outside a receipt (FR-13): [vessel, article, cans, recorded at, reason]. */
const adjustments: [string, string, number, string, string][] = [
  ['v03', '187402', -1, '2026-10-17T10:30', 'Can found damaged during a locker check; disposed of.'],
  ['v08', '100293', 1, '2026-10-13T05:00', 'Can found in the locker that was missed in the opening count.'],
]

function addHours(at: string, hours: number): string {
  const d = new Date(`${at}:00Z`)
  d.setUTCHours(d.getUTCHours() + hours)
  return d.toISOString().slice(0, 16)
}

/** When a transaction reached the server: about a day later, never after the last sync. */
function syncedAt(vessel: string, recordedAt: string): string | null {
  const last = vessels.find((v) => v.id === vessel)?.lastSync
  if (!last || recordedAt > last) return null
  const next = addHours(recordedAt, 20)
  return next < last ? next : last
}

function buildTransactions(): Transaction[] {
  const out: Omit<Transaction, 'id'>[] = []
  const push = (t: Omit<Transaction, 'id' | 'user' | 'device' | 'syncedAt'>) => {
    const synced = syncedAt(t.vessel, t.recordedAt)
    if (!synced) return
    const vessel = vessels.find((v) => v.id === t.vessel)
    out.push({ ...t, user: crewOf(t.vessel).id, device: vessel?.device?.id ?? '', syncedAt: synced })
  }

  for (const [vessel, lines] of Object.entries(baselines)) {
    const on = vessels.find((v) => v.id === vessel)?.baselineOn ?? '2026-10-01'
    lines.forEach(([articleNo, cans], i) =>
      push({ type: 'baseline', vessel, articleNo, cans, recordedAt: `${on}T08:${String(10 + i).padStart(2, '0')}`, source: 'Label scan' }),
    )
  }
  for (const dn of deliveryNotes) {
    for (const line of dn.lines) {
      if (line.receivedCans === 0) continue
      push({ type: 'receipt', vessel: dn.vessel, articleNo: line.articleNo, cans: line.receivedCans, recordedAt: dn.capturedAt, source: 'DN scan', dn: dn.dnNumber, reason: line.reason })
    }
  }
  for (const [vessel, articleNo, cans, recordedAt] of consumption) {
    push({ type: 'consumption', vessel, articleNo, cans: -cans, recordedAt, source: 'Label scan' })
  }
  for (const [vessel, articleNo, cans, recordedAt, reason] of adjustments) {
    push({ type: 'adjustment', vessel, articleNo, cans, recordedAt, source: 'Manual adjustment', reason })
  }
  return out
    .sort((a, b) => b.recordedAt.localeCompare(a.recordedAt))
    .map((t, i, all) => ({ ...t, id: `TX-${String(10000 + all.length - i)}` }))
}

/** The synced event stream (FR-11). Sea Stock is worked out from it. */
export const transactions: Transaction[] = buildTransactions()

/** Not posted to Sea Stock until someone matches them to the master item list. */
export const unrecognisedScans: UnrecognisedScan[] = [
  { id: 'us1', vessel: 'v07', readArticleNo: '189955', readProduct: 'SIGMASHIELD 1200', readShade: 'Grey', cans: 2, type: 'receipt', recordedAt: '2026-10-11T02:09', user: 'u18' },
  { id: 'us2', vessel: 'v10', readArticleNo: null, readProduct: 'SIGMADUR 520', readShade: 'Black 9000', cans: 1, type: 'consumption', recordedAt: '2026-10-18T15:25', user: 'u21' },
  { id: 'us3', vessel: 'v01', readArticleNo: '17906l', readProduct: 'SIGMACOVER 350', readShade: 'Grey 5177', cans: 1, type: 'consumption', recordedAt: '2026-10-20T07:58', user: 'u12' },
]

/** FR-27 label extraction schema (version shown on the Label schema screen). */
export const labelSchema = {
  version: 3,
  publishedOn: '2026-10-14T09:30',
  publishedBy: 'u01',
  fields: [
    { key: 'article_no', label: 'Article number', required: 'Always', role: 'Match key: ties the label to the DN line and the master item list', rule: '6 digits' },
    { key: 'product', label: 'Product', required: 'Always', role: 'Fallback match key, with shade, when the article number cannot be read', rule: 'Must be a product on the master item list' },
    { key: 'shade', label: 'Shade / colour', required: 'Where present', role: 'Fallback match key, with product', rule: 'Free text as printed, e.g. "Grey 5177"' },
    { key: 'component_type', label: 'Component type', required: 'Always', role: 'Base, Hardener or 1K', rule: 'See component rules below' },
    { key: 'pack_volume', label: 'Pack volume', required: 'Always', role: 'Turns cans into liters', rule: 'Number and unit, e.g. "20 L"' },
    { key: 'batch_no', label: 'Batch number', required: 'Where present', role: 'Secondary; kept with the transaction', rule: 'Letters and digits as printed' },
  ] as LabelField[],
  componentRules: [
    { when: 'Product is one component (1K), including thinners', then: 'Component type = 1K' },
    { when: 'Product is two components (2K)', then: 'Component type = Base or Hardener, as printed on the label' },
  ],
}
