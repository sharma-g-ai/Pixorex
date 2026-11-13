import { describe, expect, it } from 'vitest'
import type { Level, LocationNode } from '../../api/locations'
import { guideProblems, setupScreen, startGuide, type GuidePart } from './setupGuide'

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
