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

/** Dropdown and Yes / No are no longer offered for a new field; fields saved with them keep working. */
export const addableDataTypes = ['text', 'number', 'date'] as const satisfies readonly DataType[]

/** Longest description a field can have (the database holds 500 characters). */
export const MAX_DESCRIPTION = 500

/** Default flag threshold for AI confidence (data model: flag_below_confidence 0.85). */
export const DEFAULT_FLAG_BELOW = 0.85

/** Register row status (canvas BU 24). */
export function typeStatus(type: Pick<EquipmentType, 'status'>): BadgeStatus {
  return type.status === 'published'
    ? { label: 'Published · locked', tone: 'success' }
    : { label: 'Not published', tone: 'warning' }
}

/** "4 fields" under a type in the register (its badge already says Published or Draft). */
export function typeSummary(type: Pick<EquipmentType, 'field_count'>): string {
  return `${type.field_count} ${type.field_count === 1 ? 'field' : 'fields'}`
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
    description: z
      .string()
      .trim()
      .max(MAX_DESCRIPTION, `Use ${MAX_DESCRIPTION} characters or fewer.`),
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
    description: field?.description ?? '',
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
    description: v.description.trim() || null,
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
