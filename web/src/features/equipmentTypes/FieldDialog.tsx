import { useState } from 'react'
import { errorMessage } from '../../api/client'
import { useAddField, useUpdateField, type DataType, type Field } from '../../api/equipmentTypes'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { buttonClasses } from '../../components/buttonClasses'
import { ChoiceCard } from '../../components/ChoiceCard'
import { Dialog } from '../../components/Dialog'
import { SelectField } from '../../components/SelectField'
import { TextAreaField } from '../../components/TextAreaField'
import { TextField } from '../../components/TextField'
import {
  addableDataTypes,
  dataTypeLabels,
  fieldFormSchema,
  fieldToForm,
  formToField,
  labelTaken,
  MAX_DESCRIPTION,
  type FieldFormValues,
} from './fieldRules'

interface FieldDialogProps {
  buId: string
  typeId: string
  typeName: string
  fields: Field[]
  /** The field to edit; none to add a new one. */
  field?: Field
  onClose: () => void
  onSaved: (label: string) => void
}

type Errors = Partial<Record<keyof FieldFormValues | 'form', string>>

/** Add or edit one field of a not-published type (canvas BU 24; contracts 2.15–2.16). */
export function FieldDialog({
  buId,
  typeId,
  typeName,
  fields,
  field,
  onClose,
  onSaved,
}: FieldDialogProps) {
  const [values, setValues] = useState<FieldFormValues>(() => fieldToForm(field))
  const [errors, setErrors] = useState<Errors>({})
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const add = useAddField(buId, typeId)
  const update = useUpdateField(buId, typeId)
  const busy = add.isPending || update.isPending
  const set = <K extends keyof FieldFormValues>(key: K, value: FieldFormValues[K]) =>
    setValues((v) => ({ ...v, [key]: value }))

  // A new field is Text, Number or Date. A field saved earlier as a Dropdown or Yes / No keeps
  // that type (and a dropdown its choices) while it is edited, so nothing is lost.
  const kept =
    field && !addableDataTypes.some((t) => t === field.data_type) ? field.data_type : null
  const typeOptions = [...addableDataTypes, ...(kept ? [kept] : [])].map((value) => ({
    value,
    label: dataTypeLabels[value],
  }))

  const save = async () => {
    const parsed = fieldFormSchema.safeParse(values)
    if (!parsed.success) {
      const next: Errors = {}
      for (const issue of parsed.error.issues)
        next[issue.path[0] as keyof FieldFormValues] ??= issue.message
      return setErrors(next)
    }
    if (labelTaken(fields, values.label, field?.field_id)) {
      return setErrors({ label: 'A field with this name already exists in this type.' })
    }
    setErrors({})
    const body = formToField(parsed.data)
    try {
      if (field) await update.mutateAsync({ fieldId: field.field_id, ...body })
      else await add.mutateAsync({ body, idempotencyKey })
      onSaved(body.label)
    } catch (err) {
      setErrors({ form: errorMessage(err) })
    }
  }

  return (
    <Dialog
      title={field ? 'Edit field' : `Add a field to ${typeName}`}
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button disabled={busy} onClick={() => void save()}>
            {busy ? 'Saving…' : field ? 'Save changes' : 'Add field'}
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <TextField
          label="Field name technicians see"
          value={values.label}
          onChange={(e) => set('label', e.target.value)}
          error={errors.label}
        />
        <SelectField
          label="Type of value"
          options={typeOptions}
          value={values.data_type}
          onChange={(e) => set('data_type', e.target.value as DataType)}
        />
        {values.data_type === 'dropdown' && (
          <fieldset className="flex flex-col gap-2">
            <legend className="mb-1.5 text-small font-semibold text-ink-muted">
              Choices technicians pick from
            </legend>
            {values.options.map((option, i) => (
              <div key={i} className="flex items-end gap-2">
                <TextField
                  label={`Choice ${i + 1}`}
                  hideLabel
                  className="grow"
                  value={option}
                  onChange={(e) =>
                    set(
                      'options',
                      values.options.map((o, j) => (j === i ? e.target.value : o)),
                    )
                  }
                />
                <button
                  type="button"
                  className={`${buttonClasses('danger-link')} pb-2.5`}
                  aria-label={`Remove choice ${i + 1}`}
                  onClick={() =>
                    set(
                      'options',
                      values.options.filter((_, j) => j !== i),
                    )
                  }
                >
                  Remove
                </button>
              </div>
            ))}
            <button
              type="button"
              className={`${buttonClasses('link')} self-start`}
              onClick={() => set('options', [...values.options, ''])}
            >
              + Add choice
            </button>
            {errors.options && <p className="text-xs text-danger">{errors.options}</p>}
          </fieldset>
        )}
        <fieldset className="flex gap-2">
          <legend className="mb-1.5 text-small font-semibold text-ink-muted">
            Must the technician fill it?
          </legend>
          <ChoiceCard
            name="required"
            title="Required"
            checked={values.is_required}
            onChange={() => set('is_required', true)}
          />
          <ChoiceCard
            name="required"
            title="Optional"
            checked={!values.is_required}
            onChange={() => set('is_required', false)}
          />
        </fieldset>
        <TextAreaField
          label="Description (optional)"
          placeholder="e.g. Purchase order number printed on the label"
          rows={2}
          maxLength={MAX_DESCRIPTION}
          value={values.description}
          onChange={(e) => set('description', e.target.value)}
          error={errors.description}
        />
        <TextField
          label="Flag below confidence (%)"
          type="number"
          min={0}
          max={100}
          value={values.flag_percent}
          onChange={(e) => set('flag_percent', Number(e.target.value))}
          error={errors.flag_percent}
        />
        {errors.form && <Alert tone="danger">{errors.form}</Alert>}
      </div>
    </Dialog>
  )
}
