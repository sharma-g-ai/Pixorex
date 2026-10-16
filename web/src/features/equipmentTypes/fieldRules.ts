import { z } from 'zod'
import type { DataType, EquipmentType, Field, FieldInput } from '../../api/equipmentTypes'
import type { BadgeStatus } from '../../components/Badge'

export const dataTypeLabels: Record<DataType, string> = {
  text: 'Text',
  number: 'Number',
  date: 'Date',
  dropdown: 'Dropdown',
  boolean: 'Yes / No',
}

/** Default flag threshold for AI confidence (data model: flag_below_confidence 0.85). */
export const DEFAULT_FLAG_BELOW = 0.85

/** Register row status (canvas BU 24). */
export function typeStatus(type: Pick<EquipmentType, 'status'>): BadgeStatus {
  return type.status === 'published'
    ? { label: 'Published · locked', tone: 'success' }
    : { label: 'Not published', tone: 'warning' }
}

/** "4 fields · Published" under a type in the register. */
export function typeSummary(type: Pick<EquipmentType, 'field_count' | 'status'>): string {
  const fields = `${type.field_count} ${type.field_count === 1 ? 'field' : 'fields'}`
  return type.status === 'published' ? `${fields} · Published` : `${fields} · Not published`
}

/** Confidence threshold as a percentage for display ("85%"). */
export function percent(value: number | undefined): string {
  return `${Math.round((value ?? DEFAULT_FLAG_BELOW) * 100)}%`
}

/** Add / edit field form (canvas BU 24 field dialog; contract 2.15 rules). */
export const fieldFormSchema = z
  .object({
    label: z.string().trim().min(1, 'Enter the field name.'),
    data_type: z.enum(['text', 'number', 'date', 'dropdown', 'boolean']),
    options: z.array(z.string()),
    is_required: z.boolean(),
    is_critical: z.boolean(),
    format_rule: z.string().trim(),
    flag_percent: z.number().min(0, 'Use 0 to 100.').max(100, 'Use 0 to 100.'),
  })
  .superRefine((v, ctx) => {
    const choices = v.options.map((o) => o.trim()).filter(Boolean)
    if (v.data_type === 'dropdown' && choices.length < 2) {
      ctx.addIssue({ code: 'custom', path: ['options'], message: 'Add at least 2 choices.' })
    }
  })

export type FieldFormValues = z.infer<typeof fieldFormSchema>

export function fieldToForm(field?: Field): FieldFormValues {
  return {
    label: field?.label ?? '',
    data_type: field?.data_type ?? 'text',
    options: field?.options ?? ['', ''],
    is_required: field?.is_required ?? true,
    is_critical: field?.is_critical ?? false,
    format_rule: field?.format_rule ?? '',
    flag_percent: Math.round((field?.flag_below_confidence ?? DEFAULT_FLAG_BELOW) * 100),
  }
}

/** The request body for contracts 2.15 / 2.16. */
export function formToField(v: FieldFormValues): FieldInput {
  const choices = v.options.map((o) => o.trim()).filter(Boolean)
  return {
    label: v.label.trim(),
    data_type: v.data_type,
    ...(v.data_type === 'dropdown' ? { options: choices } : {}),
    is_required: v.is_required,
    is_critical: v.is_critical,
    format_rule: v.format_rule.trim() || null,
    flag_below_confidence: v.flag_percent / 100,
  }
}

/** True when another field of the type already has this label (contract 2.15: 409). */
export function labelTaken(fields: Field[], label: string, exceptId?: string): boolean {
  const wanted = label.trim().toLowerCase()
  return fields.some((f) => f.field_id !== exceptId && f.label.trim().toLowerCase() === wanted)
}

/** True when the register already has a type with this name (contract 2.11: 409). */
export function typeNameTaken(types: EquipmentType[], name: string, exceptId?: string): boolean {
  const wanted = name.trim().toLowerCase()
  return types.some((t) => t.type_id !== exceptId && t.name.trim().toLowerCase() === wanted)
}

/** Field ids after moving one up or down; unchanged at the ends. */
export function moved(ids: string[], index: number, by: -1 | 1): string[] {
  const target = index + by
  if (target < 0 || target >= ids.length) return ids
  const next = [...ids]
  const a = next[index]
  const b = next[target]
  if (a === undefined || b === undefined) return ids
  next[index] = b
  next[target] = a
  return next
}
