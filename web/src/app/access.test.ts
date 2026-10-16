import { describe, expect, it } from 'vitest'
import type { UnitRole } from '../api/me'
import { adminUnits, currentAdminUnit, dashboardRole } from './access'

const unit = (over: Partial<UnitRole>): UnitRole => ({
  bu_id: 'bu-1',
  name: 'Plant 04',
  role: 'bu_admin',
  is_primary: false,
  ...over,
})

describe('dashboardRole', () => {
  it('GIVEN an enterprise_admin row THEN the EA dashboard, even with BU Admin rows too', () => {
    const me = {
      units: [unit({ role: 'bu_admin' }), unit({ role: 'enterprise_admin', bu_id: null })],
    }
    expect(dashboardRole(me)).toBe('enterprise_admin')
  })

  it('GIVEN only bu_admin rows THEN the BU Admin dashboard', () => {
    expect(dashboardRole({ units: [unit({})] })).toBe('bu_admin')
  })

  it('GIVEN only field_technician rows THEN no dashboard access', () => {
    expect(dashboardRole({ units: [unit({ role: 'field_technician' })] })).toBeNull()
  })
})

describe('adminUnits / currentAdminUnit', () => {
  const p04 = unit({ bu_id: 'p04', name: 'Plant 04' })
  const p05 = unit({ bu_id: 'p05', name: 'Plant 05', is_primary: true })
  const tech = unit({ bu_id: 'p07', name: 'Plant 07', role: 'field_technician' })

  it('GIVEN mixed roles THEN only BU Admin units are listed', () => {
    expect(adminUnits({ units: [p04, tech, p05] })).toEqual([p04, p05])
  })

  it('GIVEN the active unit is one they run THEN it is current', () => {
    expect(currentAdminUnit({ units: [p04, p05], active_bu_id: 'p04' })).toBe(p04)
  })

  it('GIVEN the active unit is a technician unit THEN falls back to the primary unit', () => {
    expect(currentAdminUnit({ units: [p04, tech, p05], active_bu_id: 'p07' })).toBe(p05)
  })

  it('GIVEN no BU Admin units THEN null', () => {
    expect(currentAdminUnit({ units: [tech], active_bu_id: null })).toBeNull()
  })
})
