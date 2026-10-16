import { describe, expect, it } from 'vitest'
import { createUnitSchema, emptyCreateUnit, toCreateUnitBody } from './createUnitForm'

const valid = { ...emptyCreateUnit, name: 'PPG Plant 12', facility_name: 'Plant 12 — Akron, OH' }

const fieldsWithErrors = (values: unknown) => {
  const result = createUnitSchema.safeParse(values)
  return result.success ? [] : result.error.issues.map((i) => i.path.join('.'))
}

describe('createUnitSchema', () => {
  it('GIVEN empty names THEN both name fields are required', () => {
    expect(
      fieldsWithErrors({ ...valid, name: ' ', facility_name: '', invite_email: 'a@b.co' }),
    ).toEqual(['name', 'facility_name'])
  })

  it('GIVEN invite mode with a bad email THEN the email is rejected', () => {
    expect(fieldsWithErrors({ ...valid, invite_email: 'not-an-email' })).toEqual(['invite_email'])
  })

  it('GIVEN existing mode with nobody picked THEN a BU Admin is required', () => {
    expect(fieldsWithErrors({ ...valid, admin_mode: 'existing' })).toEqual(['user_id'])
  })
})

describe('toCreateUnitBody', () => {
  it('GIVEN invite mode THEN sends invite_email only', () => {
    expect(toCreateUnitBody({ ...valid, invite_email: 'd.okafor@ppg.com', user_id: 'x' })).toEqual({
      name: 'PPG Plant 12',
      facility_name: 'Plant 12 — Akron, OH',
      bu_admin: { invite_email: 'd.okafor@ppg.com' },
    })
  })

  it('GIVEN existing mode THEN sends user_id only', () => {
    expect(
      toCreateUnitBody({ ...valid, admin_mode: 'existing', invite_email: 'x', user_id: 'rk' })
        .bu_admin,
    ).toEqual({ user_id: 'rk' })
  })
})
