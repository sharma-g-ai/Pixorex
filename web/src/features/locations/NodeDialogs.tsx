import { useState } from 'react'
import { errorMessage } from '../../api/client'
import { useAddNodes, useDeleteNode, useUpdateNode, type LocationSetup } from '../../api/locations'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { ChoiceCard } from '../../components/ChoiceCard'
import { ConfirmDialog } from '../../components/ConfirmDialog'
import { Dialog } from '../../components/Dialog'
import { SelectField } from '../../components/SelectField'
import { TextField } from '../../components/TextField'
import { descendantCount, moveTargets, rangeNames, type TreeRow } from './locationTree'

export type NodeAction = { kind: 'add' | 'rename' | 'move' | 'delete'; row: TreeRow }

interface NodeDialogsProps {
  buId: string
  setup: LocationSetup
  rows: TreeRow[]
  action: NodeAction
  onClose: () => void
  onDone: (notice: string) => void
}

/** The dialog for one tree action (canvas EA 19 dialogs; contracts 2.4–2.6). */
export function NodeDialogs(props: NodeDialogsProps) {
  switch (props.action.kind) {
    case 'add':
      return <AddDialog {...props} />
    case 'rename':
      return <RenameDialog {...props} />
    case 'move':
      return <MoveDialog {...props} />
    case 'delete':
      return <DeleteDialog {...props} />
  }
}

/** Shared footer: Cancel plus one primary action. */
function Footer({
  onClose,
  label,
  busy,
  disabled = false,
  danger = false,
  onConfirm,
}: {
  onClose: () => void
  label: string
  busy: boolean
  disabled?: boolean
  danger?: boolean
  onConfirm: () => void
}) {
  return (
    <>
      <Button variant="secondary" onClick={onClose}>
        Cancel
      </Button>
      <Button
        variant={danger ? 'danger' : 'primary'}
        disabled={busy || disabled}
        onClick={onConfirm}
      >
        {busy ? 'Saving…' : label}
      </Button>
    </>
  )
}

function RenameDialog({ buId, action, onClose, onDone }: NodeDialogsProps) {
  const { node, levelName, path } = action.row
  const [name, setName] = useState(node.is_placeholder ? '' : node.name)
  const [error, setError] = useState<string | null>(null)
  const update = useUpdateNode(buId)
  const save = () => {
    if (!name.trim()) return setError('Enter a name.')
    update
      .mutateAsync({ nodeId: node.node_id, name: name.trim() })
      .then(() => onDone(`Renamed to ${name.trim()}.`))
      .catch((err: unknown) => setError(errorMessage(err)))
  }
  return (
    <Dialog
      title={`Rename this ${levelName.toLowerCase()}`}
      onClose={onClose}
      footer={
        <Footer onClose={onClose} label="Save name" busy={update.isPending} onConfirm={save} />
      }
    >
      <p className="mb-3 text-small">In {path}</p>
      <TextField
        label="Name technicians see"
        placeholder={node.is_placeholder ? 'Name this placeholder' : undefined}
        value={name}
        onChange={(e) => setName(e.target.value)}
        error={error ?? undefined}
      />
      <p className="mt-2 text-xs text-ink-subtle">
        Saved straight away. Once the unit is published, names are locked.
      </p>
    </Dialog>
  )
}

function AddDialog({ buId, setup, action, onClose, onDone }: NodeDialogsProps) {
  const { node, path, childLevels } = action.row
  const [levelId, setLevelId] = useState(childLevels[0]?.level_id ?? '')
  const [mode, setMode] = useState<'one' | 'several'>('one')
  const [name, setName] = useState('')
  const [prefix, setPrefix] = useState('')
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const [error, setError] = useState<string | null>(null)
  // One key per dialog: a retried add can never create the locations twice.
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const add = useAddNodes(buId)

  const levelName = childLevels.find((l) => l.level_id === levelId)?.level_name ?? ''
  const names =
    mode === 'one' ? (name.trim() ? [name.trim()] : []) : (rangeNames(prefix, from, to) ?? [])
  const siblings = new Set(
    setup.nodes.filter((n) => n.parent_id === node.node_id).map((n) => n.name.toLowerCase()),
  )
  const duplicates = names.filter((n) => siblings.has(n.toLowerCase()))

  const save = () => {
    if (names.length === 0) return setError('Enter a name (or a range of up to 50) to continue.')
    if (duplicates.length > 0) return setError(`${duplicates.join(', ')} already exists here.`)
    add
      .mutateAsync({ parent_id: node.node_id, level_id: levelId, names, idempotencyKey })
      .then(() =>
        onDone(
          `${names.length === 1 ? names[0] : `${names.length} locations`} added inside ${node.name}.`,
        ),
      )
      .catch((err: unknown) => setError(errorMessage(err)))
  }

  return (
    <Dialog
      title={`Add inside ${node.name}`}
      onClose={onClose}
      footer={<Footer onClose={onClose} label="Create" busy={add.isPending} onConfirm={save} />}
    >
      <div className="flex flex-col gap-3.5">
        <p className="text-small">{path}</p>
        {childLevels.length > 1 && (
          <SelectField
            label="What goes inside"
            options={childLevels.map((l) => ({ value: l.level_id, label: l.level_name }))}
            value={levelId}
            onChange={(e) => setLevelId(e.target.value)}
          />
        )}
        <fieldset className="flex gap-2">
          <legend className="sr-only">How many</legend>
          <ChoiceCard
            name="add-mode"
            value="one"
            title="Add one"
            checked={mode === 'one'}
            onChange={() => setMode('one')}
          />
          <ChoiceCard
            name="add-mode"
            value="several"
            title="Add several"
            checked={mode === 'several'}
            onChange={() => setMode('several')}
          />
        </fieldset>
        {mode === 'one' ? (
          <TextField
            label={`Name of the new ${levelName.toLowerCase()}`}
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
        ) : (
          <div className="grid grid-cols-3 gap-2.5">
            <TextField
              label="Name starts with"
              placeholder={`${levelName} `}
              value={prefix}
              onChange={(e) => setPrefix(e.target.value)}
            />
            <TextField
              label="From"
              inputMode="numeric"
              placeholder="01"
              value={from}
              onChange={(e) => setFrom(e.target.value)}
            />
            <TextField
              label="To"
              inputMode="numeric"
              placeholder="10"
              value={to}
              onChange={(e) => setTo(e.target.value)}
            />
          </div>
        )}
        {names.length > 0 && (
          <p className="text-small">
            New {names.length === 1 ? 'path' : 'paths'}: {path} ›{' '}
            <b className="text-ink">{names[0]}</b>
            {names.length > 1 && (
              <>
                {' '}
                … <b className="text-ink">{names[names.length - 1]}</b> ({names.length})
              </>
            )}
          </p>
        )}
        {error && <Alert tone="danger">{error}</Alert>}
      </div>
    </Dialog>
  )
}

function MoveDialog({ buId, setup, rows, action, onClose, onDone }: NodeDialogsProps) {
  const { node, levelName } = action.row
  const targets = moveTargets(setup.nodes, node)
  const [target, setTarget] = useState('')
  const [error, setError] = useState<string | null>(null)
  const update = useUpdateNode(buId)
  const pathOf = (id: string) => rows.find((r) => r.node.node_id === id)?.path ?? ''

  const save = () => {
    if (!target) return setError('Pick where it goes.')
    update
      .mutateAsync({ nodeId: node.node_id, parent_id: target })
      .then(() => onDone(`${node.name} moved to ${pathOf(target)}.`))
      .catch((err: unknown) => setError(errorMessage(err)))
  }

  return (
    <Dialog
      title={`Move ${node.name}`}
      onClose={onClose}
      footer={
        <Footer
          onClose={onClose}
          label="Move here"
          busy={update.isPending}
          disabled={targets.length === 0}
          onConfirm={save}
        />
      }
    >
      <div className="flex flex-col gap-2">
        {targets.length === 0 ? (
          <p>
            There is no other place at the same level to move this {levelName.toLowerCase()} to.
          </p>
        ) : (
          targets.map((t) => (
            <ChoiceCard
              key={t.node_id}
              name="move-target"
              value={t.node_id}
              title={t.name}
              description={pathOf(t.node_id)}
              checked={target === t.node_id}
              onChange={() => setTarget(t.node_id)}
            />
          ))
        )}
        {target && (
          <p className="text-small">
            New path: <b className="text-ink">{`${pathOf(target)} › ${node.name}`}</b>
          </p>
        )}
        <p className="text-xs text-ink-subtle">
          Locations move only to the same level. You can move things until the unit is published.
        </p>
        {error && <Alert tone="danger">{error}</Alert>}
      </div>
    </Dialog>
  )
}

function DeleteDialog({ buId, setup, action, onClose, onDone }: NodeDialogsProps) {
  const { node } = action.row
  const inside = descendantCount(setup.nodes, node.node_id)
  const remove = useDeleteNode(buId)
  return (
    <ConfirmDialog
      title={`Delete ${node.name}?`}
      confirmLabel="Yes, delete"
      danger
      onClose={onClose}
      onConfirm={async () => {
        await remove.mutateAsync(node.node_id)
        onDone(`${node.name} was deleted.`)
      }}
    >
      <ul className="flex list-inside list-disc flex-col gap-2">
        <li>
          {inside > 0
            ? `This also deletes the ${inside} ${inside === 1 ? 'location' : 'locations'} inside it.`
            : 'Nothing is inside it.'}
        </li>
        <li>The unit isn't published yet, so no technician has seen it.</li>
      </ul>
    </ConfirmDialog>
  )
}
