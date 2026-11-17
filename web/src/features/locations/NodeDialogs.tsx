import { useState } from 'react'
import { errorMessage } from '../../api/client'
import { useUpdateNode, type LocationNode, type LocationSetup } from '../../api/locations'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { ChoiceCard } from '../../components/ChoiceCard'
import { ConfirmDialog } from '../../components/ConfirmDialog'
import { Dialog } from '../../components/Dialog'
import { descendantCount, moveTargets, type TreeRow } from './locationTree'

export type NodeAction = { kind: 'move' | 'delete'; row: TreeRow }

interface NodeDialogsProps {
  buId: string
  setup: LocationSetup
  rows: TreeRow[]
  action: NodeAction
  /** Deletes the place (and the kinds nothing uses any more); resolves to what to say. */
  onDelete: (node: LocationNode) => Promise<string>
  onClose: () => void
  onDone: (notice: string) => void
}

/**
 * The two tree actions that still ask first: move (contract 2.5) and delete (2.6). Adding and
 * renaming happen in the row itself.
 */
export function NodeDialogs(props: NodeDialogsProps) {
  return props.action.kind === 'move' ? <MoveDialog {...props} /> : <DeleteDialog {...props} />
}

/** Shared footer: Cancel plus one primary action. */
function Footer({
  onClose,
  label,
  busy,
  disabled = false,
  onConfirm,
}: {
  onClose: () => void
  label: string
  busy: boolean
  disabled?: boolean
  onConfirm: () => void
}) {
  return (
    <>
      <Button variant="secondary" onClick={onClose}>
        Cancel
      </Button>
      <Button disabled={busy || disabled} onClick={onConfirm}>
        {busy ? 'Saving…' : label}
      </Button>
    </>
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

function DeleteDialog({ setup, action, onDelete, onClose, onDone }: NodeDialogsProps) {
  const { node } = action.row
  const inside = descendantCount(setup.nodes, node.node_id)
  return (
    <ConfirmDialog
      title={`Delete ${node.name}?`}
      confirmLabel="Yes, delete"
      danger
      onClose={onClose}
      onConfirm={async () => onDone(await onDelete(node))}
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
