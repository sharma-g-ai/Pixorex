import type { Level, LevelInput, LocationNode, LocationSetup } from '../../api/locations'
import { canScanAt, sortLevels } from './locationTree'

/**
 * Rules of the guided location setup (docs/proposals/location-setup-flow-plan.md). The
 * screens only call these; the API rules they mirror live in api/app/services/locations.py.
 */

/** One part of the place the admin describes: "Building C" is a "Building". */
export interface GuidePart {
  place: string
  kind: string
  /** Any kind below the top: "Not every Building has a Shop". */
  optional: boolean
  /** The saved level this kind came from, when a unit was set up half-way. */
  level_id: string | null
}

// The API's limits (LevelInput.level_name, NodeChange.name) and its whitespace rule.
const MAX_KIND = 100
const MAX_PLACE = 200
const clean = (text: string) => text.trim().split(/\s+/).join(' ')

/** The guided setup until the first place exists; the working page after that. */
export function setupScreen(setup: Pick<LocationSetup, 'status' | 'nodes'>): 'guide' | 'work' {
  return setup.status !== 'published' && setup.nodes.length === 0 ? 'guide' : 'work'
}

/** Step 1 starts from the unit's site name, and from any kinds saved earlier (Off ones aside). */
export function startGuide(levels: Level[], siteName: string): GuidePart[] {
  const parts: GuidePart[] = sortLevels(levels)
    .filter((l) => l.requirement !== 'off')
    .map((l, i) => ({
      place: i === 0 ? siteName : '',
      kind: l.level_name,
      optional: l.requirement === 'optional',
      level_id: l.level_id,
    }))
  if (parts.length === 0) parts.push({ place: siteName, kind: '', optional: false, level_id: null })
  if (parts.length === 1) parts.push({ place: '', kind: '', optional: false, level_id: null })
  return parts
}

/**
 * What stops Next (scope 'places') or Create ('all'), in plain words; empty when the API will
 * accept it.
 */
export function guideProblems(
  parts: GuidePart[],
  levels: Level[],
  scope: 'places' | 'all' = 'all',
): string[] {
  if (parts.length < 2) return ['Describe at least 2 parts, from the site down.']
  const problems: string[] = []
  parts.forEach((p, i) => {
    const place = clean(p.place)
    const kind = clean(p.kind)
    if (!place) problems.push(`Part ${i + 1}: type the place.`)
    else if (place.length > MAX_PLACE)
      problems.push(`Part ${i + 1}: the place can have at most ${MAX_PLACE} characters.`)
    if (scope === 'places') return
    if (!kind) problems.push(`Part ${i + 1}: name its kind.`)
    else if (kind.length > MAX_KIND)
      problems.push(`Part ${i + 1}: the kind can have at most ${MAX_KIND} characters.`)
  })
  if (scope === 'places') return problems
  // Level names are unique per unit, Off levels included (contract 2.2).
  const off = levels.filter((l) => l.requirement === 'off').map((l) => l.level_name)
  const seen = new Set<string>()
  for (const kind of [...off, ...parts.map((p) => p.kind)].map(clean).filter(Boolean)) {
    if (seen.has(kind.toLowerCase())) {
      problems.push(`Each kind needs its own name: "${kind}" is used twice.`)
      break
    }
    seen.add(kind.toLowerCase())
  }
  return problems
}

/**
 * The body of contract 2.2. Only the top kind is always required; an Off level saved
 * earlier is sent back unchanged, right after the kind it followed.
 */
export function guideLevels(parts: GuidePart[], levels: Level[]): LevelInput[] {
  const result: LevelInput[] = parts.map((p, i) => ({
    level_id: p.level_id,
    level_name: clean(p.kind),
    requirement: i > 0 && p.optional ? 'optional' : 'required',
  }))
  const saved = sortLevels(levels)
  saved.forEach((l, i) => {
    if (l.requirement !== 'off') return
    const before = saved
      .slice(0, i)
      .reverse()
      .map((b) => result.findIndex((r) => r.level_id === b.level_id))
      .find((index) => index >= 0)
    result.splice((before ?? 0) + 1, 0, {
      level_id: l.level_id,
      level_name: l.level_name,
      requirement: 'off',
    })
  })
  return result
}

/**
 * After the skeleton (contract 2.3): one rename (2.5) per place, the top one included, since a
 * rename is what clears the placeholder flag. Null when the skeleton doesn't match the parts.
 */
export function guideRenames(
  parts: GuidePart[],
  setup: Pick<LocationSetup, 'levels' | 'nodes'>,
): { node_id: string; name: string }[] | null {
  const inUse = sortLevels(setup.levels).filter((l) => l.requirement !== 'off')
  const renames = parts.map((p, i) => {
    const node = setup.nodes.find((n) => n.level_id === inUse[i]?.level_id)
    return node ? { node_id: node.node_id, name: clean(p.place) } : null
  })
  return inUse.length === parts.length && renames.every((r) => r !== null)
    ? (renames as { node_id: string; name: string }[])
    : null
}

/** What the phone's picker shows for a place: one pick per kind below the top, down to it. */
export function phonePicks(
  levels: Level[],
  nodes: LocationNode[],
  nodeId: string,
): { picks: { level_name: string; name: string | null }[]; path: string; canScan: boolean } | null {
  const byId = new Map(nodes.map((n) => [n.node_id, n]))
  const chain: LocationNode[] = []
  for (let n = byId.get(nodeId); n; n = n.parent_id ? byId.get(n.parent_id) : undefined) {
    chain.unshift(n)
  }
  const target = chain.at(-1)
  if (!target) return null
  const ordered = sortLevels(levels).filter((l) => l.requirement !== 'off')
  const depth = ordered.findIndex((l) => l.level_id === target.level_id)
  return {
    picks: ordered.slice(1, depth + 1).map((l) => ({
      level_name: l.level_name,
      name: chain.find((n) => n.level_id === l.level_id)?.name ?? null,
    })),
    path: chain.map((n) => n.name).join(' › '),
    canScan: canScanAt(levels, target.level_id),
  }
}
