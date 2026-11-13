import type { Level, LocationSetup } from '../../api/locations'
import { sortLevels } from './locationTree'

/**
 * Rules of the guided location setup (docs/proposals/location-setup-flow-plan.md). The
 * screens only call these; the API rules they mirror live in api/app/services/locations.py.
 */

/** One part of the place the admin describes: "Building C" is a "Building". */
export interface GuidePart {
  place: string
  kind: string
  /** Middle kinds only: "Not every Building has a Shop". */
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

/** What stops Create, in plain words; empty when the API will accept it. */
export function guideProblems(parts: GuidePart[], levels: Level[]): string[] {
  if (parts.length < 2) return ['Describe at least 2 parts, from the site down.']
  const problems: string[] = []
  parts.forEach((p, i) => {
    const place = clean(p.place)
    const kind = clean(p.kind)
    if (!place) problems.push(`Part ${i + 1}: type the place.`)
    else if (place.length > MAX_PLACE)
      problems.push(`Part ${i + 1}: the place can have at most ${MAX_PLACE} characters.`)
    if (!kind) problems.push(`Part ${i + 1}: name its kind.`)
    else if (kind.length > MAX_KIND)
      problems.push(`Part ${i + 1}: the kind can have at most ${MAX_KIND} characters.`)
  })
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
