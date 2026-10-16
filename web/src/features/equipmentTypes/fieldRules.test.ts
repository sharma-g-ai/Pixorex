import { describe, expect, it } from 'vitest'
import type { Field } from '../../api/equipmentTypes'
import {
  fieldFormSchema,
  fieldToForm,
  formToField,
  labelTaken,
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
  is_critical: true,
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
      is_critical: false,
      format_rule: null,
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

  it('summarises a type and its threshold', () => {
    expect(typeSummary({ field_count: 1, status: 'not_published' })).toBe('1 field · Not published')
    expect(percent(undefined)).toBe('85%')
  })
})
