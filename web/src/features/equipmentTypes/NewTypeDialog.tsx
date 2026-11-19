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
import { PhotoPicker } from '../../components/PhotoPicker'
import { TextAreaField } from '../../components/TextAreaField'
import { TextField } from '../../components/TextField'
import { DEFAULT_FLAG_BELOW, MAX_DESCRIPTION, dataTypeLabels, typeNameTaken } from './fieldRules'

interface NewTypeDialogProps {
  buId: string
  types: EquipmentType[]
  onClose: () => void
  onCreated: (type: EquipmentType) => void
}

type Source = 'blank' | 'ai'

/** A field the AI found on the photo, with the description the admin may change. */
interface Suggestion extends SuggestedField {
  description: string
}

/**
 * "New equipment type" (canvas BU 24; contracts 2.11 and 2.20): start blank, or with AI assisted
 * schema discovery, where the AI reads one label photo and suggests fields, each with a
 * description. Nothing is saved until the admin ticks the fields to keep and creates the type.
 */
export function NewTypeDialog({ buId, types, onClose, onCreated }: NewTypeDialogProps) {
  const [name, setName] = useState('')
  const [source, setSource] = useState<Source>('blank')
  const [photo, setPhoto] = useState<File | null>(null)
  const [suggested, setSuggested] = useState<Suggestion[] | null>(null)
  const [picked, setPicked] = useState<Set<number>>(new Set())
  const [error, setError] = useState<string | null>(null)
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const create = useCreateType(buId)
  const suggest = useSuggestFields(buId)

  // While the AI reads the photo or the type is being saved, nothing in the popup can be changed
  // and it can't be closed.
  const busy = suggest.isPending || create.isPending
  const close = () => {
    if (!busy) onClose()
  }

  const nameError = !name.trim()
    ? 'Enter a name.'
    : typeNameTaken(types, name)
      ? 'A type with this name is already in the register.'
      : null

  const createBlank = async () => {
    if (nameError) return setError(nameError)
    try {
      onCreated(
        await create.mutateAsync({
          body: { name: name.trim(), created_via: 'blank' },
          idempotencyKey,
        }),
      )
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  const readPhoto = async () => {
    if (nameError) return setError(nameError)
    if (!photo) return setError('Choose an image of the label.')
    setError(null)
    try {
      const fields = await suggest.mutateAsync({ name: name.trim(), image: photo })
      setSuggested(fields.map((f) => ({ ...f, description: f.description ?? '' })))
      setPicked(new Set(fields.map((_, i) => i)))
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  const createFromPhoto = async () => {
    const fields = (suggested ?? []).filter((_, i) => picked.has(i))
    if (fields.length === 0) return setError('Tick at least one field.')
    setError(null)
    try {
      onCreated(
        await create.mutateAsync({
          body: {
            name: name.trim(),
            created_via: 'ai_assist',
            fields: fields.map((f) => ({
              label: f.label,
              data_type: f.data_type,
              is_required: false,
              description: f.description.trim() || null,
              flag_below_confidence: DEFAULT_FLAG_BELOW,
            })),
          },
          idempotencyKey,
        }),
      )
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
  const describe = (i: number, description: string) =>
    setSuggested((list) => list?.map((f, j) => (j === i ? { ...f, description } : f)) ?? null)

  const footer = suggested ? (
    <>
      <Button variant="secondary" disabled={busy} onClick={close}>
        Cancel
      </Button>
      <Button disabled={create.isPending} onClick={() => void createFromPhoto()}>
        {create.isPending
          ? 'Creating…'
          : `Create type with ${picked.size} ${picked.size === 1 ? 'field' : 'fields'}`}
      </Button>
    </>
  ) : (
    <>
      <Button variant="secondary" disabled={busy} onClick={close}>
        Cancel
      </Button>
      {source === 'blank' ? (
        <Button disabled={create.isPending} onClick={() => void createBlank()}>
          {create.isPending ? 'Creating…' : 'Create type'}
        </Button>
      ) : (
        <Button disabled={suggest.isPending} onClick={() => void readPhoto()}>
          {suggest.isPending ? 'Reading the image…' : 'Read from image'}
        </Button>
      )}
    </>
  )

  return (
    <Dialog title="New equipment type" onClose={close} footer={footer}>
      <div className="flex flex-col gap-4">
        <TextField
          label="Equipment Name"
          value={name}
          disabled={!!suggested || busy}
          onChange={(e) => setName(e.target.value)}
        />
        {!suggested && (
          <>
            <fieldset className="flex flex-col gap-2">
              <legend className="mb-1.5 text-small font-semibold text-ink-muted">Start from</legend>
              <ChoiceCard
                name="source"
                title="Blank"
                checked={source === 'blank'}
                disabled={busy}
                onChange={() => setSource('blank')}
              />
              <ChoiceCard
                name="source"
                title="AI assisted schema discovery"
                checked={source === 'ai'}
                disabled={busy}
                onChange={() => setSource('ai')}
              />
            </fieldset>
            {source === 'ai' && (
              <PhotoPicker
                label="Image of the label"
                hideLabel
                file={photo}
                onChange={setPhoto}
                disabled={busy}
              />
            )}
            {suggest.isPending && <ReadingPhoto />}
          </>
        )}
        {suggested && (
          <fieldset className="flex max-h-96 flex-col gap-3 overflow-y-auto">
            <legend className="mb-1.5 text-small">
              The AI found these fields on the label. Tick the ones to add. You can change any
              description, and edit or delete a field afterwards.
            </legend>
            {suggested.map((f, i) => (
              <div key={`${f.label}-${i}`} className="flex flex-col gap-1.5">
                <ChoiceCard
                  type="checkbox"
                  title={f.label}
                  description={dataTypeLabels[f.data_type]}
                  checked={picked.has(i)}
                  onChange={(e) => toggle(i, e.target.checked)}
                />
                <TextAreaField
                  label={`Description of ${f.label}`}
                  rows={2}
                  maxLength={MAX_DESCRIPTION}
                  value={f.description}
                  onChange={(e) => describe(i, e.target.value)}
                />
              </div>
            ))}
          </fieldset>
        )}
        {error && <Alert tone="danger">{error}</Alert>}
      </div>
    </Dialog>
  )
}

/** Shown while the AI reads the photo, which can take up to a minute. */
function ReadingPhoto() {
  return (
    <div
      role="status"
      className="flex items-center gap-3 rounded-lg border-[1.5px] border-brand-navy bg-brand-navy-tint px-3.5 py-3"
    >
      <span
        aria-hidden="true"
        className="size-5 shrink-0 animate-spin rounded-full border-[2.5px] border-brand-navy border-t-transparent"
      />
      <span>
        <span className="block text-body font-bold text-brand-navy">Reading your image…</span>
        <span className="text-small text-ink-muted">
          This can take up to a minute. Please keep this window open.
        </span>
      </span>
    </div>
  )
}
