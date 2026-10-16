import { describe, expect, it } from 'vitest'
import type { BusinessUnit } from '../../api/businessUnits'
import { needsYou, otherUnitsOfAdmin } from './unitSummary'

const unit = (over: Partial<BusinessUnit>): BusinessUnit => ({
  bu_id: 'p04',
  name: 'Plant 04',
  facility_name: 'F4',
  bu_admin: null,
  locations_status: 'not_published',
  ...over,
})

const rk = { user_id: 'rk', full_name: 'R. Kowalski' }
const sa = { user_id: 'sa', full_name: 'S. Alvi' }
const p04 = unit({ bu_id: 'p04', name: 'Plant 04', bu_admin: rk, escalated_count: 2 })
const p05 = unit({ bu_id: 'p05', name: 'Plant 05', bu_admin: rk })
const p07 = unit({ bu_id: 'p07', name: 'Plant 07', bu_admin: sa, escalated_count: 5 })
const p11 = unit({ bu_id: 'p11', name: 'Plant 11', bu_admin: null, escalated_count: 1 })
const units = [p04, p05, p07, p11]

describe('otherUnitsOfAdmin', () => {
  it('GIVEN an admin running two units THEN lists the other one', () => {
    expect(otherUnitsOfAdmin(units, p04)).toEqual(['Plant 05'])
  })

  it('GIVEN an admin running one unit THEN lists none', () => {
    expect(otherUnitsOfAdmin(units, p07)).toEqual([])
  })

  it('GIVEN a unit without a BU Admin THEN lists none', () => {
    expect(otherUnitsOfAdmin(units, p11)).toEqual([])
  })
})

describe('needsYou', () => {
  it('GIVEN units THEN sums escalations and counts vacant BU Admin seats', () => {
    expect(needsYou(units)).toEqual({ escalated: 8, withoutBuAdmin: 1 })
  })

  it('GIVEN no units THEN zeros', () => {
    expect(needsYou([])).toEqual({ escalated: 0, withoutBuAdmin: 0 })
  })
})
