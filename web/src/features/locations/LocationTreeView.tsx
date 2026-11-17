import { useEffect, useMemo, useState } from 'react'
import { errorMessage } from '../../api/client'
import { useUpdateNode, type LocationSetup } from '../../api/locations'
import { ActionMenu } from '../../components/ActionMenu'
import { Alert } from '../../components/Alert'
import { Card } from '../../components/Card'
import { TextField } from '../../components/TextField'
import { AddInside } from './AddInside'
import { KindsLine } from './KindsLine'
import {
  addChoices,
  filterRows,
  rowProblem,
  sortLevels,
  treeRows,
  type TreeRow,
} from './locationTree'
import { NodeDialogs, type NodeAction } from './NodeDialogs'
import { PlaceRow } from './PlaceRow'
import { NEW_TOP, useTreeActions } from './useTreeActions'

interface LocationTreeViewProps {
  buId: string
  setup: LocationSetup
  /** The unit's facility name: its top place, shown before any place is saved. */
  siteName: string
  /** A place to scroll to and outline ("Show me" in Review & publish). */
  focusId?: string | null
  /** What just happened, for the page's status bar. */
  onNotice: (text: string) => void
}

/** A short tree is read at a glance: the search box appears from this many places. */
const SEARCH_FROM = 8

/**
 * The whole location setup on one screen (decision 2026-11-16): the kinds on one line, and the
 * places as a tree where adding and renaming happen in the row. Rename, move and delete are
 * behind the row's "⋯"; move and delete ask first.
 */
export function LocationTreeView({
  buId,
  setup,
  siteName,
  focusId,
  onNotice,
}: LocationTreeViewProps) {
  const [query, setQuery] = useState('')
  const [closed, setClosed] = useState<ReadonlySet<string>>(new Set())
  // A unit with no place yet opens with the add form on its facility.
  const [adding, setAdding] = useState<string | null>(setup.nodes.length === 0 ? TOP : null)
  const [renaming, setRenaming] = useState<string | null>(null)
  const [action, setAction] = useState<NodeAction | null>(null)
  const [error, setError] = useState<string | null>(null)
  const actions = useTreeActions(buId, setup)
  const rename = useUpdateNode(buId)

  const locked = setup.status === 'published'
  const levels = setup.levels.length > 0 ? setup.levels : [NEW_TOP]
  const rows = useMemo(() => treeRows(setup.levels, setup.nodes), [setup.levels, setup.nodes])
  const shown = query.trim() ? filterRows(rows, query) : open(rows, closed)
  const say = (text: string) => {
    setError(null)
    onNotice(text)
  }
  const fail = (err: unknown) => setError(errorMessage(err))

  useEffect(() => {
    if (focusId) document.getElementById(rowId(focusId))?.scrollIntoView?.({ block: 'center' })
  }, [focusId])

  const addForm = (row: TreeRow | null) => (
    <AddInside
      parentName={row?.node.name ?? siteName}
      choices={addChoices(levels, row?.node.level_id ?? sortLevels(levels)[0]?.level_id ?? '')}
      siblings={setup.nodes.filter((n) => n.parent_id === row?.node.node_id).map((n) => n.name)}
      busy={actions.busy}
      onCancel={() => setAdding(null)}
      onAdd={async (kind, names, key) => {
        try {
          say(await actions.addPlaces(row?.node ?? null, kind, names, key))
          setAdding(null)
        } catch (err) {
          // The first add also makes the top place, which replaces the row this form is in:
          // say it up here, where it stays visible. Otherwise the form shows it.
          if (!row) fail(err)
          throw err
        }
      }}
    />
  )

  return (
    <div className="flex flex-col gap-4">
      {error && <Alert tone="danger">{error}</Alert>}
      <Card title="Locations">
        <KindsLine
          levels={setup.levels}
          locked={locked}
          busy={actions.busy}
          onToggle={(level, skip) => {
            const refused = skip ? null : actions.mustStaySkippable(level)
            if (refused) return setError(refused)
            void actions.setSkippable(level, skip).then(say, fail)
          }}
        />
        {rows.length >= SEARCH_FROM && (
          <TextField
            label="Search locations"
            hideLabel
            placeholder="Search locations"
            className="mb-3 max-w-80"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        )}
        <ul aria-label="Location tree" className="overflow-hidden rounded-xl border border-line">
          {rows.length === 0 && (
            <li>
              <PlaceRow
                name={siteName}
                kind={sortLevels(levels)[0]?.level_name ?? ''}
                depth={0}
                onAddInside={!locked && adding !== TOP ? () => setAdding(TOP) : undefined}
              />
              {!locked && adding === TOP && addForm(null)}
            </li>
          )}
          {rows.length > 0 && shown.length === 0 && (
            <li className="px-4.5 py-6 text-center text-body text-ink-muted">
              No location matches your search.
            </li>
          )}
          {shown.map((row) => {
            const { node } = row
            const problem = locked ? null : rowProblem(setup.levels, row)
            const canAdd = addChoices(setup.levels, node.level_id).length > 0
            return (
              <li key={node.node_id}>
                <PlaceRow
                  id={rowId(node.node_id)}
                  name={node.name}
                  kind={row.levelName}
                  depth={row.depth}
                  warning={problem?.text}
                  highlighted={node.node_id === focusId}
                  onAddInside={
                    !locked && canAdd
                      ? () => {
                          setAdding(node.node_id)
                          setClosed((ids) => without(ids, node.node_id))
                        }
                      : undefined
                  }
                  fold={
                    row.children > 0 && !query.trim()
                      ? {
                          closed: closed.has(node.node_id),
                          onToggle: () => setClosed((ids) => toggled(ids, node.node_id)),
                        }
                      : undefined
                  }
                  rename={
                    renaming === node.node_id
                      ? {
                          startEmpty: node.is_placeholder,
                          onCancel: () => setRenaming(null),
                          onSave: async (name) => {
                            await rename.mutateAsync({ nodeId: node.node_id, name })
                            setRenaming(null)
                            say(`Renamed to ${name}.`)
                          },
                        }
                      : undefined
                  }
                >
                  {!locked && (
                    <ActionMenu
                      label={`More for ${node.name}`}
                      actions={[
                        { label: 'Rename', onSelect: () => setRenaming(node.node_id) },
                        // The top place stays: it can be renamed, not moved or deleted.
                        ...(node.parent_id
                          ? [
                              {
                                label: 'Move',
                                onSelect: () => setAction({ kind: 'move', row }),
                              },
                              {
                                label: 'Delete',
                                danger: true,
                                onSelect: () => setAction({ kind: 'delete', row }),
                              },
                            ]
                          : []),
                      ]}
                    />
                  )}
                </PlaceRow>
                {!locked && adding === node.node_id && addForm(row)}
              </li>
            )
          })}
        </ul>
      </Card>
      {action && (
        <NodeDialogs
          buId={buId}
          setup={setup}
          rows={rows}
          action={action}
          onDelete={actions.deletePlace}
          onClose={() => setAction(null)}
          onDone={(text) => {
            setAction(null)
            say(text)
          }}
        />
      )}
    </div>
  )
}

/** Stands for the facility while the unit has no saved place. */
const TOP = 'top'
const rowId = (nodeId: string) => `place-${nodeId}`

/** The rows outside every closed place. Rows come parents first, so one pass is enough. */
function open(rows: TreeRow[], closed: ReadonlySet<string>): TreeRow[] {
  let hideBelow: number | null = null
  return rows.filter((row) => {
    if (hideBelow !== null && row.depth > hideBelow) return false
    hideBelow = closed.has(row.node.node_id) ? row.depth : null
    return true
  })
}

const without = (ids: ReadonlySet<string>, id: string) => new Set([...ids].filter((x) => x !== id))
const toggled = (ids: ReadonlySet<string>, id: string) =>
  ids.has(id) ? without(ids, id) : new Set([...ids, id])
