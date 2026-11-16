import { useMemo, useState } from 'react'
import type { LocationNode, LocationSetup } from '../../api/locations'
import { Alert } from '../../components/Alert'
import { buttonClasses } from '../../components/buttonClasses'
import { Card } from '../../components/Card'
import { DataTable, type Column } from '../../components/DataTable'
import { TextField } from '../../components/TextField'
import {
  canScanAt,
  filterRows,
  rowStatus,
  sortLevels,
  treeRows,
  type TreeRow,
} from './locationTree'
import { PhonePreview } from './PhonePreview'
import { NodeDialogs, type NodeAction } from './NodeDialogs'

interface LocationTreeViewProps {
  buId: string
  setup: LocationSetup
  /** The place shown in the phone preview; null starts on the first scannable place. */
  previewId: string | null
  onPreview: (nodeId: string) => void
}

/** The working page's list of places, with rename · add inside · move · delete. */
export function LocationTreeView({
  buId,
  setup,
  previewId: picked,
  onPreview,
}: LocationTreeViewProps) {
  const [query, setQuery] = useState('')
  const [action, setAction] = useState<NodeAction | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  const locked = setup.status === 'published'
  const rows = useMemo(() => treeRows(setup.levels, setup.nodes), [setup.levels, setup.nodes])
  // The phone preview starts on the first place a technician can scan at.
  const previewId =
    picked ?? rows.find((r) => canScanAt(setup.levels, r.node.level_id))?.node.node_id ?? null

  const columns: Column<TreeRow>[] = [
    {
      header: 'Location',
      width: 3,
      cell: (r) => {
        // No Status column: a row that needs fixing is tinted and says why under its name.
        const status = rowStatus(setup.levels, r)
        return (
          <div style={{ paddingLeft: `calc(var(--spacing) * ${r.depth * 5})` }}>
            <button
              type="button"
              className={`block max-w-full truncate text-left font-semibold hover:underline ${
                r.node.node_id === previewId ? 'text-brand-navy' : ''
              }`}
              aria-label={`Preview ${r.node.name} on the phone`}
              aria-pressed={r.node.node_id === previewId}
              onClick={() => onPreview(r.node.node_id)}
            >
              {r.node.name}
            </button>
            {status.tone === 'warning' && (
              <div className="text-xs font-semibold text-warning">⚠ {status.label}</div>
            )}
          </div>
        )
      },
    },
    { header: 'Level', width: 1, cell: (r) => r.levelName },
    {
      header: 'Contains',
      width: 1,
      cell: (r) =>
        r.children > 0 ? (
          `${r.children} inside`
        ) : (
          // ink-muted, not ink-subtle: it must stay readable on a tinted row.
          <span className="text-ink-muted">Nothing inside yet</span>
        ),
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
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start">
        <Card
          className="min-w-0 grow"
          title="Locations"
          action={
            <span className="text-small text-ink-muted">
              {`Kinds: ${sortLevels(setup.levels)
                .filter((l) => l.requirement !== 'off')
                .map((l) => l.level_name)
                .join(' › ')}`}
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
            rowTone={(r) => (rowStatus(setup.levels, r).tone === 'warning' ? 'warning' : null)}
            empty="No location matches your search."
          />
        </Card>
        <PhonePreview levels={setup.levels} nodes={setup.nodes} nodeId={previewId} />
      </div>
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
    <div className="flex flex-wrap justify-end gap-x-3 gap-y-1">
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
