import type { Level, LevelInput, LocationNode, Requirement } from '../../api/locations'

/** Quick-start level sets (canvas EA 12). */
export const presets: Record<2 | 3 | 4 | 5, LevelInput[]> = {
  2: [
    { level_name: 'Facility', requirement: 'required' },
    { level_name: 'Bin', requirement: 'required' },
  ],
  3: [
    { level_name: 'Facility', requirement: 'required' },
    { level_name: 'Building', requirement: 'required' },
    { level_name: 'Bin', requirement: 'required' },
  ],
  4: [
    { level_name: 'Facility', requirement: 'required' },
    { level_name: 'Building', requirement: 'required' },
    { level_name: 'Shop', requirement: 'optional' },
    { level_name: 'Bin', requirement: 'required' },
  ],
  5: [
    { level_name: 'Facility', requirement: 'required' },
    { level_name: 'Building', requirement: 'required' },
    { level_name: 'Shop', requirement: 'optional' },
    { level_name: 'Bin', requirement: 'required' },
    { level_name: 'Sub-bin', requirement: 'optional' },
  ],
}

export const requirementLabels: Record<Requirement, string> = {
  required: 'Required',
  optional: 'Optional',
  off: 'Off',
}

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

/** Rows whose name or path matches the search, plus every row above a match. */
export function filterRows(rows: TreeRow[], query: string): TreeRow[] {
  const q = query.trim().toLowerCase()
  if (!q) return rows
  const matches = rows.filter((r) => r.node.name.toLowerCase().includes(q))
  const keep = new Set<string>()
  for (const match of matches) {
    for (const row of rows) if (match.path.startsWith(row.path)) keep.add(row.node.node_id)
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

/**
 * "Add several": names from a prefix and a numeric range, keeping the width of the
 * numbers ("Bin " 05–08 → Bin 05 … Bin 08). Null when the range is not valid or over 50.
 */
export function rangeNames(prefix: string, from: string, to: string): string[] | null {
  if (!/^\d+$/.test(from) || !/^\d+$/.test(to)) return null
  const start = Number(from)
  const end = Number(to)
  if (end < start || end - start + 1 > 50) return null
  const width = Math.max(from.length, to.length)
  return Array.from(
    { length: end - start + 1 },
    (_, i) => `${prefix}${String(start + i).padStart(width, '0')}`,
  )
}
