import { useState } from 'react'
import { errorMessage } from '../../api/client'
import {
  useCreateType,
  useSuggestFields,
  type EquipmentType,
  type SuggestedField,
} from '../../api/equipmentTypes'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { ChoiceCard } from '../../components/ChoiceCard'
import { Dialog } from '../../components/Dialog'
import { TextField } from '../../components/TextField'
import { DEFAULT_FLAG_BELOW, dataTypeLabels, typeNameTaken } from './fieldRules'

interface AiAssistDialogProps {
  buId: string
  types: EquipmentType[]
  onClose: () => void
  onCreated: (type: EquipmentType) => void
}

/**
 * "Suggest fields from a photo" (canvas BU 24; contracts 2.20 then 2.11). The AI only
 * suggests; nothing is saved until the BU Admin ticks fields and creates the type.
 */
export function AiAssistDialog({ buId, types, onClose, onCreated }: AiAssistDialogProps) {
  const [name, setName] = useState('')
  const [photo, setPhoto] = useState<File | null>(null)
  const [suggested, setSuggested] = useState<SuggestedField[] | null>(null)
  const [picked, setPicked] = useState<Set<number>>(new Set())
  const [error, setError] = useState<string | null>(null)
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const suggest = useSuggestFields(buId)
  const create = useCreateType(buId)

  const nameError = !name.trim()
    ? 'Enter a name.'
    : typeNameTaken(types, name)
      ? 'A type with this name is already in the register.'
      : null

  const readPhoto = async () => {
    if (nameError) return setError(nameError)
    if (!photo) return setError('Choose a photo of the label.')
    setError(null)
    try {
      const fields = await suggest.mutateAsync({ name: name.trim(), image: photo })
      setSuggested(fields)
      setPicked(new Set(fields.map((_, i) => i)))
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  const createType = async () => {
    const fields = (suggested ?? []).filter((_, i) => picked.has(i))
    if (fields.length === 0) return setError('Tick at least one field.')
    setError(null)
    try {
      const type = await create.mutateAsync({
        body: {
          name: name.trim(),
          created_via: 'ai_assist',
          fields: fields.map((f) => ({
            label: f.label,
            data_type: f.data_type,
            is_required: false,
            is_critical: false,
            flag_below_confidence: DEFAULT_FLAG_BELOW,
          })),
        },
        idempotencyKey,
      })
      onCreated(type)
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  const toggle = (i: number, on: boolean) =>
    setPicked((s) => {
      const next = new Set(s)
      if (on) next.add(i)
      else next.delete(i)
      return next
    })

  return (
    <Dialog
      title="Suggest fields from a photo"
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          {suggested ? (
            <Button disabled={create.isPending} onClick={() => void createType()}>
              {create.isPending ? 'Creating…' : `Create type with ${picked.size} fields`}
            </Button>
          ) : (
            <Button disabled={suggest.isPending} onClick={() => void readPhoto()}>
              {suggest.isPending ? 'Reading the photo…' : 'Read from photo'}
            </Button>
          )}
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <TextField
          label="New type name"
          value={name}
          disabled={!!suggested}
          onChange={(e) => setName(e.target.value)}
        />
        {!suggested && (
          <div>
            <label
              htmlFor="ai-photo"
              className="mb-1.5 block text-small font-semibold text-ink-muted"
            >
              Photo of the label
            </label>
            <input
              id="ai-photo"
              type="file"
              accept="image/jpeg,image/png"
              className="text-body"
              onChange={(e) => setPhoto(e.target.files?.[0] ?? null)}
            />
          </div>
        )}
        {suggested && (
          <fieldset className="flex max-h-72 flex-col gap-2 overflow-y-auto">
            <legend className="mb-1.5 text-small">
              The AI found these fields on the label. Tick the ones to add — you can edit or delete
              any of them afterwards.
            </legend>
            {suggested.map((f, i) => (
              <ChoiceCard
                key={`${f.label}-${i}`}
                type="checkbox"
                title={f.label}
                description={dataTypeLabels[f.data_type]}
                checked={picked.has(i)}
                onChange={(e) => toggle(i, e.target.checked)}
              />
            ))}
          </fieldset>
        )}
        <p className="text-xs text-ink-subtle">
          The type is created as Not published with the fields you tick. Check them, then publish.
        </p>
        {error && <Alert tone="danger">{error}</Alert>}
      </div>
    </Dialog>
  )
}
