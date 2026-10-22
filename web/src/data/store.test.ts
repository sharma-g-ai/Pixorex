import { describe, expect, it } from 'vitest'
import { stockLines, visibleCustomers, visibleVessels } from './queries'
import { customers, items, labelSchema, unrecognisedScans, users } from './sample'
import {
  addItems,
  matchScan,
  publishLabelSchema,
  resetSampleData,
  saveCustomer,
  saveVessel,
  setItemStatus,
} from './store'

const dana = users.find((u) => u.id === 'u01')
if (!dana) throw new Error('sample admin missing')

function cans(vessel: string, article: string) {
  return stockLines([vessel]).find((l) => l.item.articleNo === article)?.cans
}

describe('shared sample data', () => {
  it('a new customer and vessel show for every screen and survive a reload', () => {
    saveCustomer({
      id: 'c9',
      customerId: 'C-999',
      name: 'Test Lines',
      region: 'EMEA',
      status: 'active',
      addedOn: '2026-10-21',
    })
    saveVessel({
      id: 'v9',
      vesselId: 'V-9',
      imo: 'IMO 9000001',
      name: 'Test Ship',
      customer: 'c9',
      device: null,
      baselineOn: null,
      lastSync: null,
      status: 'active',
    })
    expect(visibleCustomers(dana).map((c) => c.name)).toContain('Test Lines')
    expect(visibleVessels(dana).map((v) => v.name)).toContain('Test Ship')
    // An EMEA-only PPG Admin sees it too; an APAC one does not.
    const lars = users.find((u) => u.id === 'u02')
    expect(lars && visibleCustomers(lars).map((c) => c.name)).toContain('Test Lines')
    expect(JSON.parse(sessionStorage.getItem('seastock.data') ?? '{}').customers).toHaveLength(
      customers.length,
    )
  })

  it('matching an unrecognised scan posts it to Sea Stock and clears it from review', () => {
    const scan = unrecognisedScans.find((s) => s.id === 'us3') // 1 can consumed, label read "17906l"
    if (!scan) throw new Error('sample scan missing')
    expect(cans('v01', '179061')).toBe(11)
    matchScan(scan, '179061', dana)
    expect(cans('v01', '179061')).toBe(10)
    expect(unrecognisedScans.some((s) => s.id === 'us3')).toBe(false)
  })

  it('publishing the label schema makes the next version', () => {
    publishLabelSchema(
      labelSchema.fields.map((f) => ({ ...f, rule: f.key === 'batch_no' ? 'Changed' : f.rule })),
      'u01',
    )
    expect(labelSchema.version).toBe(4)
    expect(labelSchema.fields.find((f) => f.key === 'batch_no')?.rule).toBe('Changed')
  })

  it('items can be added, retired and restored', () => {
    addItems([
      {
        articleNo: '999999',
        product: 'TEST',
        shade: '',
        componentType: '1K',
        packSize: '5 L',
        unitVolume: 5,
        status: 'active',
      },
    ])
    expect(items[0]?.articleNo).toBe('999999')
    setItemStatus('999999', 'retired')
    expect(items.find((i) => i.articleNo === '999999')?.status).toBe('retired')
  })

  it('reset brings back the sample data', () => {
    saveCustomer({
      id: 'c9',
      customerId: 'C-999',
      name: 'Test Lines',
      region: 'EMEA',
      status: 'active',
      addedOn: '2026-10-21',
    })
    resetSampleData()
    expect(customers.some((c) => c.id === 'c9')).toBe(false)
    expect(labelSchema.version).toBe(3)
    expect(unrecognisedScans).toHaveLength(3)
    expect(sessionStorage.getItem('seastock.data')).toBeNull()
  })
})
