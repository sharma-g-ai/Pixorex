import { useState } from 'react'
import { errorMessage } from '../../api/client'
import { useCreateSkeleton, type LocationNode, type LocationSetup } from '../../api/locations'
import { Alert } from '../../components/Alert'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { buttonClasses } from '../../components/buttonClasses'
import { Card } from '../../components/Card'
import { DataTable, type Column } from '../../components/DataTable'
import { TextField } from '../../components/TextField'
import { filterRows, treeRows, type TreeRow } from './locationTree'
import { NodeDialogs, type NodeAction } from './NodeDialogs'

interface LocationTreeViewProps {
  buId: string
  setup: LocationSetup
  onEditLevels: () => void
}

/** Tab 2 · Locations (canvas EA 19): the tree, with rename · add inside · move · delete. */
export function LocationTreeView({ buId, setup, onEditLevels }: LocationTreeViewProps) {
  const [query, setQuery] = useState('')
  const [action, setAction] = useState<NodeAction | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const skeleton = useCreateSkeleton(buId)
  const [error, setError] = useState<string | null>(null)

  const locked = setup.status === 'published'
  const rows = treeRows(setup.levels, setup.nodes)

  if (setup.nodes.length === 0) {
    const enoughLevels = setup.levels.length >= 2
    return (
      <Card title="No locations yet">
        <p className="mb-4 text-body text-ink-muted">
          First choose the levels this unit uses and their order. We then build a plain skeleton —
          one placeholder per level — that you rename and fill in here.
        </p>
        <div className="flex gap-2.5">
          {enoughLevels ? (
            <Button
              disabled={skeleton.isPending}
              onClick={() =>
                skeleton.mutateAsync(undefined).catch((err: unknown) => setError(errorMessage(err)))
              }
            >
              {skeleton.isPending ? 'Creating…' : 'Create the skeleton'}
            </Button>
          ) : (
            <Button onClick={onEditLevels}>Choose levels →</Button>
          )}
        </div>
        {error && (
          <Alert tone="danger" className="mt-3">
            {error}
          </Alert>
        )}
      </Card>
    )
  }

  const columns: Column<TreeRow>[] = [
    {
      header: 'Location',
      width: 2.4,
      cell: (r) => (
        <div
          className="truncate font-semibold"
          style={{ paddingLeft: `calc(var(--spacing) * ${r.depth * 5})` }}
        >
          {r.node.name}
        </div>
      ),
    },
    { header: 'Level', width: 1, cell: (r) => r.levelName },
    {
      header: 'Contains',
      width: 1,
      cell: (r) =>
        r.children > 0 ? (
          `${r.children} inside`
        ) : (
          <span className="text-ink-subtle">Nothing inside yet</span>
        ),
    },
    {
      header: 'Status',
      width: 1,
      cell: (r) =>
        r.node.is_placeholder ? (
          <Badge tone="warning">Placeholder</Badge>
        ) : r.childLevels.length === 0 ? (
          <Badge tone="neutral">Scan here</Badge>
        ) : null,
    },
    ...(locked
      ? []
      : [
          {
            header: 'Actions',
            width: 2.6,
            align: 'right' as const,
            cell: (r: TreeRow) => <RowActions row={r} onAction={setAction} />,
          },
        ]),
  ]

  return (
    <div className="flex flex-col gap-4">
      {notice && (
        <Alert tone="info" role="status">
          {notice}
        </Alert>
      )}
      <Card
        title="Locations"
        action={
          <span className="text-small text-ink-muted">
            {locked
              ? 'This unit is published — locations are locked to protect scan history'
              : 'Beside every location: rename · add inside · move · delete'}
          </span>
        }
      >
        <TextField
          label="Search locations"
          hideLabel
          placeholder="Search locations"
          className="mb-3 max-w-80"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <DataTable
          label="Location tree"
          columns={columns}
          rows={filterRows(rows, query)}
          rowKey={(r) => r.node.node_id}
          empty="No location matches your search."
        />
      </Card>
      {action && (
        <NodeDialogs
          buId={buId}
          setup={setup}
          rows={rows}
          action={action}
          onClose={() => setAction(null)}
          onDone={(text) => {
            setAction(null)
            setNotice(text)
          }}
        />
      )}
    </div>
  )
}

function RowActions({ row, onAction }: { row: TreeRow; onAction: (a: NodeAction) => void }) {
  const node: LocationNode = row.node
  const next = row.childLevels[0]
  return (
    <div className="flex justify-end gap-3">
      {next && (
        <button
          type="button"
          className={buttonClasses('link')}
          aria-label={`Add inside ${node.name}`}
          onClick={() => onAction({ kind: 'add', row })}
        >
          + {next.level_name}
        </button>
      )}
      <button
        type="button"
        className={buttonClasses('link')}
        aria-label={`Rename ${node.name}`}
        onClick={() => onAction({ kind: 'rename', row })}
      >
        Rename
      </button>
      {node.parent_id && (
        <button
          type="button"
          className={buttonClasses('link')}
          aria-label={`Move ${node.name}`}
          onClick={() => onAction({ kind: 'move', row })}
        >
          Move
        </button>
      )}
      {node.parent_id && (
        <button
          type="button"
          className={buttonClasses('danger-link')}
          aria-label={`Delete ${node.name}`}
          onClick={() => onAction({ kind: 'delete', row })}
        >
          Delete
        </button>
      )}
    </div>
  )
}
