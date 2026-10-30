import { describe, expect, it } from 'vitest'
import { activeDevice, openEnrolmentCode, stockLines, visibleCustomers, visibleDevices, visibleVessels } from './queries'
import { auditLog, customers, items, labelSchema, quarantinedEvents, unrecognisedScans, users } from './sample'
import {
  addItems,
  adjustStock,
  closeHeldEvent,
  issueEnrolmentCode,
  matchScan,
  publishLabelSchema,
  resetSampleData,
  revokeDevice,
  saveCustomer,
  saveVessel,
  setItemStatus,
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
    expect(JSON.parse(sessionStorage.getItem('seastock.data.v2') ?? '{}').customers).toHaveLength(customers.length)
    expect(auditLog[0]?.summary).toContain('Test Ship')
  })

  it('matching an unrecognised scan posts it to Sea Stock and clears it from review', () => {
    const scan = unrecognisedScans.find((s) => s.id === 'us3') // 1 can consumed, label read "17906l"
    if (!scan) throw new Error('sample scan missing')
    const before = cans('v01', '179061') ?? 0
    matchScan(scan, '179061', dana)
    expect(cans('v01', '179061')).toBe(before - 1)
    expect(unrecognisedScans.some((s) => s.id === 'us3')).toBe(false)
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
    const code = issueEnrolmentCode('v12', false, dana)
    expect(openEnrolmentCode('v12')?.code).toBe(code)
    expect(first?.status).toBe('cancelled')

    expect(activeDevice('v01')?.id).toBe('TAB-0101')
    revokeDevice('TAB-0101', 'Lost overboard', ingrid)
    expect(activeDevice('v01')).toBeUndefined()
    expect(visibleDevices(ingrid).some((d) => d.id === 'TAB-0101')).toBe(true)
    expect(visibleDevices(ingrid).some((d) => d.id === 'TAB-0201')).toBe(false)
  })

  it('closing a held event keeps it, with the outcome and note', () => {
    closeHeldEvent('qe1', 'dismissed', 'Sent twice; first copy applied', dana)
    const e = quarantinedEvents.find((x) => x.id === 'qe1')
    expect(e?.status).toBe('dismissed')
    expect(e?.resolvedBy).toBe('u01')
  })

  it('publishing the label schema makes the next version', () => {
    publishLabelSchema(
      labelSchema.fields.map((f) => ({ ...f, rule: f.key === 'batch_no' ? 'Changed' : f.rule })),
      dana,
    )
    expect(labelSchema.version).toBe(4)
    expect(labelSchema.fields.find((f) => f.key === 'batch_no')?.rule).toBe('Changed')
  })

  it('items can be added, retired and restored', () => {
    addItems(
      [{ articleNo: '999999', product: 'TEST', shade: '', productType: '1K', componentType: '1K', packSize: '5 L', unitVolume: 5, status: 'active' }],
      dana,
    )
    expect(items[0]?.articleNo).toBe('999999')
    setItemStatus('999999', 'retired', dana)
    expect(items.find((i) => i.articleNo === '999999')?.status).toBe('retired')
  })

  it('reset brings back the sample data', () => {
    saveCustomer(testCustomer, dana)
    resetSampleData()
    expect(customers.some((c) => c.id === 'c9')).toBe(false)
    expect(labelSchema.version).toBe(3)
    expect(unrecognisedScans).toHaveLength(3)
    expect(activeDevice('v01')?.id).toBe('TAB-0101')
    expect(sessionStorage.getItem('seastock.data.v2')).toBeNull()
  })
})
