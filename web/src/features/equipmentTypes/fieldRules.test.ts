import { describe, expect, it } from 'vitest'
import type { Field } from '../../api/equipmentTypes'
import {
  addableDataTypes,
  dataTypeLabels,
  fieldFormSchema,
  fieldToForm,
  formToField,
  labelTaken,
  MAX_DESCRIPTION,
  moved,
  percent,
  typeSummary,
} from './fieldRules'

const field = (over: Partial<Field>): Field => ({
  field_id: 'f1',
  field_key: 'serial_number',
  label: 'Serial Number',
  data_type: 'text',
  is_required: true,
  sort_order: 1,
  origin: 'manual',
  ...over,
})

describe('field form', () => {
  it('GIVEN a dropdown with one choice THEN at least 2 are required', () => {
    const v = {
      ...fieldToForm(),
      label: 'Hazard Class',
      data_type: 'dropdown' as const,
      options: ['Flammable', ''],
    }
    const result = fieldFormSchema.safeParse(v)
    expect(result.success).toBe(false)
    expect(result.error?.issues[0]?.message).toBe('Add at least 2 choices.')
  })

  it('GIVEN a dropdown THEN choices are trimmed and blanks dropped; flag % becomes 0–1', () => {
    const body = formToField({
      ...fieldToForm(),
      label: ' Hazard Class ',
      data_type: 'dropdown',
      options: [' Flammable ', '', 'Toxic'],
      flag_percent: 90,
    })
    expect(body).toEqual({
      label: 'Hazard Class',
      data_type: 'dropdown',
      options: ['Flammable', 'Toxic'],
      is_required: true,
      description: null,
      flag_below_confidence: 0.9,
    })
  })

  it('GIVEN a text field THEN no options are sent', () => {
    expect(
      formToField({ ...fieldToForm(), label: 'Model', options: ['x', 'y'] }),
    ).not.toHaveProperty('options')
  })

  it('GIVEN an existing field THEN the form starts from its values', () => {
    expect(fieldToForm(field({ flag_below_confidence: 0.7 })).flag_percent).toBe(70)
  })

  it('GIVEN a new field THEN it starts required, with an empty description', () => {
    expect(fieldToForm()).toMatchObject({ is_required: true, description: '', data_type: 'text' })
  })

  it('sends neither "critical" nor a format rule any more', () => {
    const body = formToField({ ...fieldToForm(), label: 'Model' })
    expect(body).not.toHaveProperty('is_critical')
    expect(body).not.toHaveProperty('format_rule')
  })
})

describe('field description', () => {
  it('GIVEN a description THEN it is trimmed and sent', () => {
    const body = formToField({
      ...fieldToForm(),
      label: 'PO#',
      description: '  Purchase order number printed on the label  ',
    })
    expect(body.description).toBe('Purchase order number printed on the label')
  })

  it('GIVEN a blank description THEN none is sent', () => {
    expect(
      formToField({ ...fieldToForm(), label: 'PO#', description: '   ' }).description,
    ).toBeNull()
  })

  it('GIVEN an existing field THEN the form starts with its description', () => {
    expect(fieldToForm(field({ description: 'After S/N' })).description).toBe('After S/N')
    expect(fieldToForm(field({ description: null })).description).toBe('')
    expect(fieldToForm(field({})).description).toBe('')
  })

  it('GIVEN 500 characters THEN it is accepted; 501 is refused with a reason', () => {
    const base = { ...fieldToForm(), label: 'Notes' }
    expect(
      fieldFormSchema.safeParse({ ...base, description: 'x'.repeat(MAX_DESCRIPTION) }).success,
    ).toBe(true)
    const result = fieldFormSchema.safeParse({ ...base, description: 'x'.repeat(501) })
    expect(result.success).toBe(false)
    expect(result.error?.issues[0]?.message).toBe('Use 500 characters or fewer.')
  })
})

describe('types of value', () => {
  it('GIVEN a new field THEN only Text, Number and Date are offered', () => {
    expect([...addableDataTypes]).toEqual(['text', 'number', 'date'])
  })

  it('GIVEN fields saved as Dropdown or Yes / No THEN they still have a name to show', () => {
    expect(dataTypeLabels.dropdown).toBe('Dropdown')
    expect(dataTypeLabels.boolean).toBe('Yes / No')
  })
})

describe('helpers', () => {
  it('finds a label already used, ignoring case and the field being edited', () => {
    const fields = [field({})]
    expect(labelTaken(fields, 'serial number')).toBe(true)
    expect(labelTaken(fields, 'serial number', 'f1')).toBe(false)
  })

  it('moves a field up or down, not past the ends', () => {
    expect(moved(['a', 'b', 'c'], 1, -1)).toEqual(['b', 'a', 'c'])
    expect(moved(['a', 'b', 'c'], 2, 1)).toEqual(['a', 'b', 'c'])
  })

  it('summarises a type by its field count only (the badge says Published or Draft)', () => {
    expect(typeSummary({ field_count: 1 })).toBe('1 field')
    expect(typeSummary({ field_count: 7 })).toBe('7 fields')
    expect(typeSummary({ field_count: 0 })).toBe('0 fields')
    expect(percent(undefined)).toBe('85%')
  })
})
