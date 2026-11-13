import { describe, expect, it } from 'vitest'
import type { Level, LocationNode } from '../../api/locations'
import {
  guideLevels,
  guideProblems,
  guideRenames,
  phonePicks,
  setupScreen,
  startGuide,
  type GuidePart,
} from './guideRules'

const level = (
  id: string,
  name: string,
  order: number,
  requirement: Level['requirement'],
): Level => ({ level_id: id, level_name: name, level_order: order, requirement })
const node = (id: string, name: string, levelId: string, parent: string | null): LocationNode => ({
  node_id: id,
  name,
  level_id: levelId,
  parent_id: parent,
  is_placeholder: false,
  child_count: 0,
})
const part = (place: string, kind: string, extra: Partial<GuidePart> = {}): GuidePart => ({
  place,
  kind,
  optional: false,
  level_id: null,
  ...extra,
})

describe('setupScreen', () => {
  it('GIVEN no places THEN the guided setup; GIVEN places or published THEN the working page', () => {
    expect(setupScreen({ status: 'not_published', nodes: [] })).toBe('guide')
    expect(setupScreen({ status: 'not_published', nodes: [node('f', 'P', 'fac', null)] })).toBe(
      'work',
    )
    expect(setupScreen({ status: 'published', nodes: [node('f', 'P', 'fac', null)] })).toBe('work')
  })
})

describe('startGuide', () => {
  it('GIVEN a new unit THEN two parts, the first filled with the site name (R1)', () => {
    expect(startGuide([], 'Plant 04')).toEqual([part('Plant 04', ''), part('', '')])
  })

  it('GIVEN levels saved half-way THEN their kinds are filled in; Off levels get no box', () => {
    const saved = [
      level('fac', 'Plant', 1, 'required'),
      level('old', 'Zone', 2, 'off'),
      level('bld', 'Building', 3, 'optional'),
      level('bin', 'Bin', 4, 'required'),
    ]
    expect(startGuide(saved, 'Plant 04')).toEqual([
      part('Plant 04', 'Plant', { level_id: 'fac' }),
      part('', 'Building', { level_id: 'bld', optional: true }),
      part('', 'Bin', { level_id: 'bin' }),
    ])
  })
})

describe('guideProblems', () => {
  const ok = [part('Plant 04', 'Plant'), part('Building C', 'Building'), part('Bin 07', 'Bin')]

  it('GIVEN every box filled and different kinds THEN no problem', () => {
    expect(guideProblems(ok, [])).toEqual([])
  })

  it('GIVEN fewer than 2 parts or an empty box THEN it says which (R2)', () => {
    expect(guideProblems([part('Plant 04', 'Plant')], [])).toEqual([
      'Describe at least 2 parts, from the site down.',
    ])
    expect(guideProblems([part('Plant 04', 'Plant'), part(' ', '')], [])).toEqual([
      'Part 2: type the place.',
      'Part 2: name its kind.',
    ])
  })

  it('GIVEN scope places THEN only the places are checked (step 1)', () => {
    expect(guideProblems([part('Plant 04', ''), part('', '')], [], 'places')).toEqual([
      'Part 2: type the place.',
    ])
  })

  it('GIVEN the same kind twice in any case, also against an Off level THEN refused (R3)', () => {
    expect(guideProblems([part('A', 'Bin'), part('B', ' bin ')], [])).toEqual([
      'Each kind needs its own name: "bin" is used twice.',
    ])
    const off = [level('old', 'Zone', 2, 'off')]
    expect(guideProblems([part('A', 'Plant'), part('B', 'zone')], off)).toEqual([
      'Each kind needs its own name: "zone" is used twice.',
    ])
  })

  it('GIVEN names over the API limits THEN refused before sending', () => {
    const long = [part('x'.repeat(201), 'Plant'), part('B', 'k'.repeat(101))]
    expect(guideProblems(long, [])).toEqual([
      'Part 1: the place can have at most 200 characters.',
      'Part 2: the kind can have at most 100 characters.',
    ])
  })
})

describe('guideLevels', () => {
  it('GIVEN parts THEN contract 2.2 gets them in order; only the top is always required (R4)', () => {
    const parts = [
      part('Plant 04', ' Plant ', { optional: true }),
      part('Paint Shop', 'Shop', { optional: true }),
      part('Bin 07', 'Bin', { optional: true }),
    ]
    expect(guideLevels(parts, [])).toEqual([
      { level_id: null, level_name: 'Plant', requirement: 'required' },
      { level_id: null, level_name: 'Shop', requirement: 'optional' },
      { level_id: null, level_name: 'Bin', requirement: 'optional' },
    ])
  })

  it('GIVEN an Off level saved half-way THEN it is sent back unchanged, after its neighbour', () => {
    const saved = [
      level('fac', 'Plant', 1, 'required'),
      level('old', 'Zone', 2, 'off'),
      level('bin', 'Bin', 3, 'required'),
    ]
    const parts = [
      part('Plant 04', 'Plant', { level_id: 'fac' }),
      part('Bin 07', 'Bin', { level_id: 'bin' }),
    ]
    expect(guideLevels(parts, saved).map((l) => [l.level_id, l.level_name, l.requirement])).toEqual(
      [
        ['fac', 'Plant', 'required'],
        ['old', 'Zone', 'off'],
        ['bin', 'Bin', 'required'],
      ],
    )
  })
})

describe('guideRenames', () => {
  it('GIVEN the skeleton THEN every place is renamed, the top one too, even when unchanged (R4)', () => {
    const levels = [
      level('fac', 'Plant', 1, 'required'),
      level('old', 'Zone', 2, 'off'),
      level('bin', 'Bin', 3, 'required'),
    ]
    // The skeleton names the top after the facility and the rest after their level.
    const nodes = [node('n1', 'Plant 04', 'fac', null), node('n2', 'Bin', 'bin', 'n1')]
    expect(
      guideRenames([part('Plant 04', 'Plant'), part(' Bin ', 'Bin')], { levels, nodes }),
    ).toEqual([
      { node_id: 'n1', name: 'Plant 04' },
      { node_id: 'n2', name: 'Bin' },
    ])
  })

  it('GIVEN a skeleton that does not match the parts THEN null, so nothing is renamed', () => {
    const levels = [level('fac', 'Plant', 1, 'required'), level('bin', 'Bin', 2, 'required')]
    expect(guideRenames([part('A', 'Plant'), part('B', 'Bin')], { levels, nodes: [] })).toBeNull()
  })
})

describe('phonePicks', () => {
  const levels = [
    level('fac', 'Plant', 1, 'required'),
    level('bld', 'Building', 2, 'required'),
    level('shp', 'Shop', 3, 'optional'),
    level('bin', 'Bin', 4, 'required'),
  ]
  const nodes = [
    node('f', 'Plant 04', 'fac', null),
    node('c', 'Building C', 'bld', 'f'),
    node('s', 'Paint Shop', 'shp', 'c'),
    node('b7', 'Bin 07', 'bin', 's'),
    node('b9', 'Bin 09', 'bin', 'c'),
  ]

  it('GIVEN a bin THEN one pick per kind below the top, the path, and scanning is possible (R7)', () => {
    expect(phonePicks(levels, nodes, 'b7')).toEqual({
      picks: [
        { level_name: 'Building', name: 'Building C' },
        { level_name: 'Shop', name: 'Paint Shop' },
        { level_name: 'Bin', name: 'Bin 07' },
      ],
      path: 'Plant 04 › Building C › Paint Shop › Bin 07',
      canScan: true,
    })
  })

  it('GIVEN a skipped optional kind THEN its pick is empty', () => {
    expect(phonePicks(levels, nodes, 'b9')?.picks[1]).toEqual({ level_name: 'Shop', name: null })
  })

  it('GIVEN a building THEN only the picks down to it, and no scanning there', () => {
    expect(phonePicks(levels, nodes, 'c')).toEqual({
      picks: [{ level_name: 'Building', name: 'Building C' }],
      path: 'Plant 04 › Building C',
      canScan: false,
    })
  })

  it('GIVEN an unknown place THEN null', () => {
    expect(phonePicks(levels, nodes, 'nope')).toBeNull()
  })
})
