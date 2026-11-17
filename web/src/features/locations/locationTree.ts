import type { Level, LevelInput, LocationNode } from '../../api/locations'

/**
 * The standard kinds a unit's places are made of, biggest to smallest: the five levels of PRD
 * FR-2.1 (decision 2026-11-16 in STATE.md: the same names in every unit, picked, not typed).
 */
export const standardKinds = ['Facility', 'Building', 'Shop', 'Bin', 'Sub-bin'] as const

const standardIndex = (name: string) => (standardKinds as readonly string[]).indexOf(name)
const inUse = (levels: Level[]) => sortLevels(levels).filter((l) => l.requirement !== 'off')

/** The 2.2 body for a saved level, unchanged. */
export const levelInput = ({ level_id, level_name, requirement }: Level): LevelInput => ({
  level_id,
  level_name,
  requirement,
})

export function sortLevels(levels: Level[]): Level[] {
  return [...levels].sort((a, b) => a.level_order - b.level_order)
}

/**
 * Levels that may sit directly inside a location of `parentLevelId` (contract 2.4):
 * the next levels down, skipping optional ones, up to and including the first
 * required one. Levels that are off never appear.
 */
export function childLevels(levels: Level[], parentLevelId: string): Level[] {
  const ordered = sortLevels(levels)
  const start = ordered.findIndex((l) => l.level_id === parentLevelId)
  const result: Level[] = []
  for (const level of ordered.slice(start + 1)) {
    if (level.requirement === 'off') continue
    result.push(level)
    if (level.requirement === 'required') break
  }
  return result
}

/**
 * Whether a technician can place a scan at a location of this level: at the deepest required
 * level or below it. The same rule as the API's publish check and the phone's picker.
 */
export function canScanAt(levels: Level[], levelId: string): boolean {
  const deepestRequired = Math.max(
    0,
    ...levels.filter((l) => l.requirement === 'required').map((l) => l.level_order),
  )
  const level = levels.find((l) => l.level_id === levelId)
  return level !== undefined && level.level_order >= deepestRequired
}

export interface TreeRow {
  node: LocationNode
  depth: number
  levelName: string
  /** "Plant 04 › Building A › Bin 05" */
  path: string
  children: number
  childLevels: Level[]
}

/** Nodes in tree order (parents before children, siblings by name), with depth and path. */
export function treeRows(levels: Level[], nodes: LocationNode[]): TreeRow[] {
  const levelName = new Map(levels.map((l) => [l.level_id, l.level_name]))
  const byParent = new Map<string | null, LocationNode[]>()
  for (const node of nodes) {
    const list = byParent.get(node.parent_id) ?? []
    list.push(node)
    byParent.set(node.parent_id, list)
  }
  const rows: TreeRow[] = []
  const walk = (parentId: string | null, depth: number, trail: string[]) => {
    const kids = [...(byParent.get(parentId) ?? [])].sort((a, b) =>
      a.name.localeCompare(b.name, undefined, { numeric: true }),
    )
    for (const node of kids) {
      const path = [...trail, node.name]
      rows.push({
        node,
        depth,
        levelName: levelName.get(node.level_id) ?? '',
        path: path.join(' › '),
        children: byParent.get(node.node_id)?.length ?? 0,
        childLevels: childLevels(levels, node.level_id),
      })
      walk(node.node_id, depth + 1, path)
    }
  }
  walk(null, 0, [])
  return rows
}

/** What is wrong with a place, shown in its tinted row; null when nothing is. */
export type RowProblem = { kind: 'placeholder' | 'empty'; text: string }

/**
 * A temporary name (it blocks publishing), or a named place with nothing inside that stops
 * above a required level: what the publish check calls an empty branch (contract 2.7).
 */
export function rowProblem(levels: Level[], row: TreeRow): RowProblem | null {
  if (row.node.is_placeholder) return { kind: 'placeholder', text: 'Placeholder' }
  if (row.children > 0 || canScanAt(levels, row.node.level_id)) return null
  const needed = row.childLevels.find((l) => l.requirement === 'required')
  return needed ? { kind: 'empty', text: `Needs a ${needed.level_name}` } : null
}

/**
 * What is left before publishing, from the same problems the tree shows: placeholders block
 * publishing; empty places only warn (contract 2.7, plan D2).
 */
export function toFix(levels: Level[], rows: TreeRow[]): { placeholders: number; empty: number } {
  const kinds = rows.map((r) => rowProblem(levels, r)?.kind)
  return {
    placeholders: kinds.filter((k) => k === 'placeholder').length,
    empty: kinds.filter((k) => k === 'empty').length,
  }
}

/**
 * Rows whose name matches the search, plus every row above a match. Walks each match's real
 * parents (not path text, where "Building 1" looks like the start of "Building 10"), once per
 * row, so it stays fast for units with thousands of locations.
 */
export function filterRows(rows: TreeRow[], query: string): TreeRow[] {
  const q = query.trim().toLowerCase()
  if (!q) return rows
  const byId = new Map(rows.map((r) => [r.node.node_id, r.node]))
  const keep = new Set<string>()
  for (const row of rows) {
    if (!row.node.name.toLowerCase().includes(q)) continue
    let node: LocationNode | undefined = row.node
    while (node && !keep.has(node.node_id)) {
      keep.add(node.node_id)
      node = node.parent_id ? byId.get(node.parent_id) : undefined
    }
  }
  return rows.filter((r) => keep.has(r.node.node_id))
}

/** How many locations are inside a node, all the way down. */
export function descendantCount(nodes: LocationNode[], nodeId: string): number {
  const kids = nodes.filter((n) => n.parent_id === nodeId)
  return kids.reduce((sum, kid) => sum + 1 + descendantCount(nodes, kid.node_id), 0)
}

/**
 * Where a node may move (contract 2.5): under another parent at the same level as its
 * current parent. Top-level nodes cannot move.
 */
export function moveTargets(nodes: LocationNode[], node: LocationNode): LocationNode[] {
  const parent = nodes.find((n) => n.node_id === node.parent_id)
  if (!parent) return []
  return nodes.filter((n) => n.level_id === parent.level_id && n.node_id !== parent.node_id)
}

/** Count of locations per level, top to bottom. */
export function countsByLevel(levels: Level[], nodes: LocationNode[]) {
  return sortLevels(levels).map((level) => ({
    level,
    count: nodes.filter((n) => n.level_id === level.level_id).length,
  }))
}

/** One kind a place may get inside it; level_id is null until the first place of that kind. */
export interface AddChoice {
  level_id: string | null
  level_name: string
}

/**
 * What may be added straight inside a place of `parentLevelId`: the unit's own kinds (the
 * API's rule, see childLevels), plus the standard kinds it does not use yet. A new kind is
 * offered only while the unit's kinds are standard ones in the standard order, so its place
 * in the order is known, and only if no kind in between is always asked.
 */
export function addChoices(levels: Level[], parentLevelId: string): AddChoice[] {
  const saved: AddChoice[] = childLevels(levels, parentLevelId)
  const used = inUse(levels)
  const indexes = used.map((l) => standardIndex(l.level_name))
  if (indexes.some((n, i) => n < 0 || n <= (indexes[i - 1] ?? -1))) return saved
  const parent = standardIndex(used.find((l) => l.level_id === parentLevelId)?.level_name ?? '')
  if (parent < 0) return saved
  const taken = new Set(levels.map((l) => l.level_name.toLowerCase()))
  const fresh = standardKinds.filter((kind, n) => {
    const between = used.filter((l) => {
      const at = standardIndex(l.level_name)
      return at > parent && at < n
    })
    return (
      n > parent &&
      !taken.has(kind.toLowerCase()) &&
      between.every((l) => l.requirement === 'optional')
    )
  })
  return [...saved, ...fresh.map((kind) => ({ level_id: null, level_name: kind }))].sort(
    (a, b) => standardIndex(a.level_name) - standardIndex(b.level_name),
  )
}

/**
 * The 2.2 body that adds a standard kind at its place in the order. It is sent as always
 * asked; the API saves it as "can be skipped" when places already sit below it.
 */
export function levelsWithKind(levels: Level[], kind: string): LevelInput[] {
  const ordered = sortLevels(levels)
  const at = ordered.findIndex(
    (l) => l.requirement !== 'off' && standardIndex(l.level_name) > standardIndex(kind),
  )
  const result = ordered.map(levelInput)
  result.splice(at < 0 ? result.length : at, 0, {
    level_id: null,
    level_name: kind,
    requirement: 'required',
  })
  return result
}

/**
 * Kinds no place uses any more once `nodeId` and everything inside it are deleted. A kind
 * left without places would still be asked for on the phone, so nobody could finish picking.
 */
export function unusedAfterDelete(levels: Level[], nodes: LocationNode[], nodeId: string): Level[] {
  const gone = new Set([nodeId])
  // Parents come before their children in tree order, so one pass finds the whole branch.
  for (const row of treeRows(levels, nodes)) {
    if (row.node.parent_id && gone.has(row.node.parent_id)) gone.add(row.node.node_id)
  }
  const lost = new Set(nodes.filter((n) => gone.has(n.node_id)).map((n) => n.level_id))
  const kept = new Set(nodes.filter((n) => !gone.has(n.node_id)).map((n) => n.level_id))
  return levels.filter((l) => lost.has(l.level_id) && !kept.has(l.level_id))
}

/**
 * How many places have something inside that goes past this kind (a bin straight inside a
 * building goes past Shop). While there are any, the kind has to stay "can be skipped".
 */
export function placesSkipping(levels: Level[], nodes: LocationNode[], levelId: string): number {
  const order = new Map(levels.map((l) => [l.level_id, l.level_order]))
  const at = order.get(levelId) ?? 0
  const byId = new Map(nodes.map((n) => [n.node_id, n]))
  const parents = new Set<string>()
  for (const child of nodes) {
    const parent = child.parent_id ? byId.get(child.parent_id) : undefined
    if (!parent) continue
    if ((order.get(parent.level_id) ?? 0) < at && (order.get(child.level_id) ?? 0) > at)
      parents.add(parent.node_id)
  }
  return parents.size
}

/** The most places one add may create (contract 2.4). */
export const MAX_NAMES = 50

/**
 * The names typed into "Add inside": separated by commas, and a range of numbers becomes one
 * name per number, keeping their width ("Bin 05-08" gives Bin 05, Bin 06, Bin 07, Bin 08).
 * Spaces are tidied the way the API does. The caller checks the count against MAX_NAMES.
 */
export function typedNames(text: string): string[] {
  return text
    .split(',')
    .map((part) => part.trim().split(/\s+/).join(' '))
    .filter(Boolean)
    .flatMap((part) => {
      const range = /^(.*?)(\d+)\s*[-–]\s*(\d+)$/.exec(part)
      if (!range) return [part]
      const [, prefix = '', from = '', to = ''] = range
      const start = Number(from)
      const count = Number(to) - start + 1
      // Not a range worth expanding: it stays one name, and a huge one is refused as too many.
      if (count < 2) return [part]
      const width = Math.max(from.length, to.length)
      return Array.from(
        { length: Math.min(count, MAX_NAMES + 1) },
        (_, i) => `${prefix}${String(start + i).padStart(width, '0')}`,
      )
    })
}
