import { describe, expect, it } from 'vitest'
import { activeDevice, imoReviewFor, openEnrolmentCode, scanForLine, stockLines, unrecognisedFor, visibleCustomers, visibleDevices, visibleVessels } from './queries'
import { assignments, auditLog, customers, devices, items, quarantinedEvents, unrecognisedScans, users } from './sample'
import {
  addItems,
  adjustStock,
  closeHeldEvent,
  issueEnrolmentCode,
  matchScan,
  requestDeviceRetirement,
  resetSampleData,
  retireDevice,
  revokeDevice,
  saveCustomer,
  saveVessel,
} from './store'

function user(id: string) {
  const u = users.find((x) => x.id === id)
  if (!u) throw new Error(`sample user ${id} missing`)
  return u
}
const dana = user('u01') // PPG Admin
const ingrid = user('u06') // Customer Admin, Nordhavn (c1)

function cans(vessel: string, article: string) {
  return stockLines([vessel]).find((l) => l.item.articleNo === article)?.cans
}

const testCustomer = { id: 'c9', customerCode: 'C-999', name: 'Test Lines', status: 'active', addedOn: '2026-10-21' } as const

describe('shared sample data', () => {
  it('a new customer and vessel show on every screen, survive a reload and are audited', () => {
    saveCustomer(testCustomer, dana)
    saveVessel(
      { id: 'v9', imo: '9000003', name: 'Test Ship', customer: 'c9', receivingMode: 'scan', baselineOn: null, lastSync: null, status: 'active', passwordChangedAt: null, lastSignInAt: null },
      dana,
    )
    expect(visibleCustomers(dana).map((c) => c.name)).toContain('Test Lines')
    expect(visibleVessels(dana).map((v) => v.name)).toContain('Test Ship')
    // A Customer Admin sees only their own customer.
    expect(visibleCustomers(ingrid).map((c) => c.id)).toEqual(['c1'])
    expect(visibleVessels(ingrid).some((v) => v.name === 'Test Ship')).toBe(false)
    expect(JSON.parse(sessionStorage.getItem('seastock.data.v3') ?? '{}').customers).toHaveLength(customers.length)
    expect(auditLog[0]?.summary).toContain('Test Ship')
  })

  it('matching an unrecognised scan posts it to Sea Stock and clears it from review', () => {
    const scan = unrecognisedScans.find((s) => s.id === 'us3') // 1 can consumed, label read "17906l"
    if (!scan) throw new Error('sample scan missing')
    const before = cans('v01', '179061') ?? 0
    matchScan(scan, '179061', dana)
    expect(cans('v01', '179061')).toBe(before - 1)
    expect(unrecognisedFor(['v01']).some((s) => s.id === 'us3')).toBe(false)
    // The matched scan is kept, final, with who matched it.
    const kept = unrecognisedScans.find((s) => s.id === 'us3')
    expect(kept).toMatchObject({ status: 'matched', matchedArticle: '179061', matchedBy: 'u01' })
    matchScan(scan, '179062', dana)
    expect(kept?.matchedArticle).toBe('179061')
  })

  it('a delivery note line held as a scan finds its scan', () => {
    expect(scanForLine('5324655402', '189955')?.id).toBe('us1')
    expect(scanForLine('5324655402', '187401')).toBeUndefined()
  })

  it('notes are reviewed unless the IMO matches: a mismatch or an IMO not read', () => {
    expect(imoReviewFor(['v09']).map((d) => d.imoCheck)).toEqual(['mismatch'])
    expect(imoReviewFor(['v07']).map((d) => d.imoCheck)).toEqual(['not_read'])
    expect(imoReviewFor(['v01'])).toEqual([])
  })

  it('a portal adjustment changes stock and records who made it', () => {
    const before = cans('v02', '179061') ?? 0
    adjustStock('v02', '179061', -2, 'Damaged cans', ingrid)
    expect(cans('v02', '179061')).toBe(before - 2)
    expect(auditLog[0]?.summary).toContain('Ingrid')
  })

  it('a new enrolment code cancels the open one; revoking a tablet unpairs it', () => {
    const first = openEnrolmentCode('v12')
    expect(first).toBeDefined()
    const code = issueEnrolmentCode('v12', dana)
    expect(code).toMatch(/^[A-Z2-9]{4}-[A-Z2-9]{4}$/)
    expect(first?.status).toBe('cancelled')
    expect(openEnrolmentCode('v12')?.id).not.toBe(first?.id)
    // Only the hash is stored: the code is not kept to read back.
    expect(JSON.stringify(openEnrolmentCode('v12'))).not.toContain(code)

    expect(activeDevice('v01')?.id).toBe('TAB-0101')
    revokeDevice('TAB-0101', 'Lost overboard', ingrid)
    expect(activeDevice('v01')).toBeUndefined()
    expect(visibleDevices(ingrid).some((d) => d.id === 'TAB-0101')).toBe(true)
    expect(visibleDevices(ingrid).some((d) => d.id === 'TAB-0201')).toBe(false)
  })

  it('preparing a tablet keeps it active and paired until its final sync', () => {
    requestDeviceRetirement('TAB-0101', ingrid)
    const d = devices.find((x) => x.id === 'TAB-0101')
    expect(d?.status).toBe('active')
    expect(d?.retireRequestedAt).not.toBeNull()
    expect(activeDevice('v01')?.id).toBe('TAB-0101')
    expect(auditLog[0]?.summary).toContain('prepared tablet TAB-0101')
  })

  it('retire now ends the pairing at once, with its reason, and is final', () => {
    retireDevice('TAB-0101', ingrid)
    const d = devices.find((x) => x.id === 'TAB-0101')
    expect(d?.status).toBe('retired')
    expect(d?.retiredAt).not.toBeNull()
    expect(activeDevice('v01')).toBeUndefined()
    expect(assignments.find((a) => a.device === 'TAB-0101')?.unassignReason).toBe('device_retired')
    // Retired is final: neither revoke nor prepare changes it.
    revokeDevice('TAB-0101', 'Too late', ingrid)
    requestDeviceRetirement('TAB-0101', ingrid)
    expect(d?.status).toBe('retired')
    expect(d?.retireRequestedAt).toBeNull()
  })

  it('revoking records the reason on the tablet and device_revoked on the pairing', () => {
    revokeDevice('TAB-0102', 'Stolen', dana)
    expect(devices.find((x) => x.id === 'TAB-0102')?.revokeReason).toBe('Stolen')
    expect(assignments.find((a) => a.device === 'TAB-0102')?.unassignReason).toBe('device_revoked')
  })

  it('a tablet is enrolled once', () => {
    const enrolled = assignments.map((a) => a.device)
    expect(new Set(enrolled).size).toBe(enrolled.length)
  })

  it('closing a held event keeps it, with the outcome and note', () => {
    closeHeldEvent('qe1', 'dismissed', 'Sent twice; first copy applied', dana)
    const e = quarantinedEvents.find((x) => x.id === 'qe1')
    expect(e?.status).toBe('dismissed')
    expect(e?.resolvedBy).toBe('u01')
  })

  it('items can be added', () => {
    addItems(
      [{ articleNo: '999999', product: 'TEST', shade: '', productType: '1K', componentType: '1K', packSize: '5 L', unitVolume: 5 }],
      dana,
    )
    expect(items[0]?.articleNo).toBe('999999')
  })

  it('reset brings back the sample data', () => {
    saveCustomer(testCustomer, dana)
    resetSampleData()
    expect(customers.some((c) => c.id === 'c9')).toBe(false)
    expect(unrecognisedScans).toHaveLength(3)
    expect(activeDevice('v01')?.id).toBe('TAB-0101')
    expect(sessionStorage.getItem('seastock.data.v3')).toBeNull()
  })
})
