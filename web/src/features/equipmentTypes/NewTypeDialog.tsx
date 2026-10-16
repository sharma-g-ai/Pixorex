import { useState } from 'react'
import { errorMessage } from '../../api/client'
import { useCreateType, type EquipmentType } from '../../api/equipmentTypes'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { ChoiceCard } from '../../components/ChoiceCard'
import { Dialog } from '../../components/Dialog'
import { TextField } from '../../components/TextField'
import { typeNameTaken } from './fieldRules'

interface NewTypeDialogProps {
  buId: string
  types: EquipmentType[]
  onClose: () => void
  onCreated: (type: EquipmentType) => void
}

/** "New equipment type": blank or a copy of an existing type (canvas BU 24; contract 2.11). */
export function NewTypeDialog({ buId, types, onClose, onCreated }: NewTypeDialogProps) {
  const [name, setName] = useState('')
  const [source, setSource] = useState('blank')
  const [error, setError] = useState<string | null>(null)
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const create = useCreateType(buId)

  const save = async () => {
    if (!name.trim()) return setError('Enter a name.')
    if (typeNameTaken(types, name))
      return setError('A type with this name is already in the register.')
    try {
      const type = await create.mutateAsync({
        body:
          source === 'blank'
            ? { name: name.trim(), created_via: 'blank' }
            : { name: name.trim(), created_via: 'copy', copied_from_type_id: source },
        idempotencyKey,
      })
      onCreated(type)
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  return (
    <Dialog
      title="New equipment type"
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button disabled={create.isPending} onClick={() => void save()}>
            {create.isPending ? 'Creating…' : 'Create type'}
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <TextField
          label="Name technicians will see"
          value={name}
          onChange={(e) => setName(e.target.value)}
        />
        <fieldset className="flex max-h-60 flex-col gap-2 overflow-y-auto">
          <legend className="mb-1.5 text-small font-semibold text-ink-muted">Start from</legend>
          <ChoiceCard
            name="source"
            title="Blank"
            checked={source === 'blank'}
            onChange={() => setSource('blank')}
          />
          {types.map((t) => (
            <ChoiceCard
              key={t.type_id}
              name="source"
              title={`Copy of ${t.name}`}
              description={`${t.field_count} fields`}
              checked={source === t.type_id}
              onChange={() => setSource(t.type_id)}
            />
          ))}
        </fieldset>
        <p className="text-xs text-ink-subtle">
          The type starts as Not published: add and check its fields, then publish. Once published
          it can't be edited or deleted. For a photo-based start, use AI-assist.
        </p>
        {error && <Alert tone="danger">{error}</Alert>}
      </div>
    </Dialog>
  )
}
