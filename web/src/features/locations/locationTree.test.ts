import { describe, expect, it } from 'vitest'
import type { Level, LocationNode } from '../../api/locations'
import {
  MAX_NAMES,
  addChoices,
  canScanAt,
  childLevels,
  countsByLevel,
  descendantCount,
  filterRows,
  levelsWithKind,
  moveTargets,
  placesSkipping,
  rowProblem,
  toFix,
  treeRows,
  typedNames,
  unusedAfterDelete,
} from './locationTree'

const level = (
  id: string,
  name: string,
  order: number,
  requirement: Level['requirement'],
): Level => ({
  level_id: id,
  level_name: name,
  level_order: order,
  requirement,
})
const levels = [
  level('fac', 'Facility', 1, 'required'),
  level('bld', 'Building', 2, 'required'),
  level('shp', 'Shop', 3, 'optional'),
  level('bin', 'Bin', 4, 'required'),
  level('sub', 'Sub-bin', 5, 'optional'),
]
const node = (id: string, name: string, levelId: string, parent: string | null): LocationNode => ({
  node_id: id,
  name,
  level_id: levelId,
  parent_id: parent,
  is_placeholder: false,
  child_count: 0,
})
const nodes = [
  node('f', 'Plant 04', 'fac', null),
  node('a', 'Building A', 'bld', 'f'),
  node('b', 'Building B', 'bld', 'f'),
  node('s', 'Paint Shop', 'shp', 'a'),
  node('b10', 'Bin 10', 'bin', 'a'),
  node('b2', 'Bin 2', 'bin', 's'),
]

describe('childLevels', () => {
  it('GIVEN an optional level below THEN it can be skipped down to the next required one', () => {
    expect(childLevels(levels, 'bld').map((l) => l.level_name)).toEqual(['Shop', 'Bin'])
  })

  it('GIVEN the deepest required level THEN only the optional level below it', () => {
    expect(childLevels(levels, 'bin').map((l) => l.level_name)).toEqual(['Sub-bin'])
  })

  it('GIVEN a level that is off THEN it is never offered', () => {
    const withOff = levels.map((l) =>
      l.level_id === 'shp' ? { ...l, requirement: 'off' as const } : l,
    )
    expect(childLevels(withOff, 'bld').map((l) => l.level_name)).toEqual(['Bin'])
  })
})

describe('canScanAt', () => {
  it('GIVEN the deepest required level or below THEN a technician can scan there', () => {
    // The API's publish check and the phone use the same rule (deepest required level).
    expect(['fac', 'bld', 'shp', 'bin', 'sub'].map((id) => canScanAt(levels, id))).toEqual([
      false,
      false,
      false,
      true,
      true,
    ])
  })
})

describe('rowProblem', () => {
  it('GIVEN any row THEN a temporary name, an empty place, or nothing wrong', () => {
    const placeholder = { ...node('p', 'Building', 'bld', 'f'), is_placeholder: true }
    const rows = treeRows(levels, [...nodes, placeholder])
    const problem = (id: string) => {
      const row = rows.find((r) => r.node.node_id === id)
      return row ? rowProblem(levels, row) : undefined
    }
    expect(problem('p')).toEqual({ kind: 'placeholder', text: 'Placeholder' })
    // Building B is named but has nothing inside: a technician can't finish picking there.
    expect(problem('b')).toEqual({ kind: 'empty', text: 'Needs a Bin' })
    // A bin is where technicians scan; places with something inside are fine.
    expect(problem('b10')).toBeNull()
    expect(problem('a')).toBeNull()
    expect(problem('f')).toBeNull()
  })
})

describe('toFix', () => {
  it('GIVEN rows THEN counts the placeholders and the places that still need something inside', () => {
    const placeholder = { ...node('p', 'Building', 'bld', 'f'), is_placeholder: true }
    const rows = treeRows(levels, [...nodes, placeholder])
    expect(toFix(levels, rows)).toEqual({ placeholders: 1, empty: 1 })
  })
})

describe('treeRows', () => {
  it('GIVEN a tree THEN parents come before children, siblings in natural order, with paths', () => {
    const rows = treeRows(levels, nodes)
    expect(rows.map((r) => `${'-'.repeat(r.depth)}${r.node.name}`)).toEqual([
      'Plant 04',
      '-Building A',
      '--Bin 10',
      '--Paint Shop',
      '---Bin 2',
      '-Building B',
    ])
    expect(rows.find((r) => r.node.node_id === 'b2')?.path).toBe(
      'Plant 04 › Building A › Paint Shop › Bin 2',
    )
    expect(rows[0]?.children).toBe(2)
  })

  it('GIVEN a search THEN matches keep their parents', () => {
    const names = filterRows(treeRows(levels, nodes), 'bin 2').map((r) => r.node.name)
    expect(names).toEqual(['Plant 04', 'Building A', 'Paint Shop', 'Bin 2'])
  })

  it('GIVEN names that start alike THEN only the real parents are kept, not look-alikes', () => {
    // "Plant 04 › Building 1" is the start of "Plant 04 › Building 10 › Bin 9" as text.
    const alike = [
      node('f', 'Plant 04', 'fac', null),
      node('b1', 'Building 1', 'bld', 'f'),
      node('b10', 'Building 10', 'bld', 'f'),
      node('k', 'Bin 9', 'bin', 'b10'),
    ]
    const names = filterRows(treeRows(levels, alike), 'bin 9').map((r) => r.node.name)
    expect(names).toEqual(['Plant 04', 'Building 10', 'Bin 9'])
  })
})

describe('tree helpers', () => {
  it('counts everything inside a node', () => {
    expect(descendantCount(nodes, 'a')).toBe(3)
    expect(descendantCount(nodes, 'b')).toBe(0)
  })

  it('moves only under another parent at the same level', () => {
    const shop = nodes.find((n) => n.node_id === 's')
    expect(shop && moveTargets(nodes, shop).map((n) => n.name)).toEqual(['Building B'])
    const top = nodes.find((n) => n.node_id === 'f')
    expect(top && moveTargets(nodes, top)).toEqual([])
  })

  it('counts locations per level', () => {
    expect(countsByLevel(levels, nodes).map((c) => c.count)).toEqual([1, 2, 1, 2, 0])
  })
})

describe('addChoices', () => {
  const names = (ls: Level[], parent: string) => addChoices(ls, parent).map((c) => c.level_name)

  it('GIVEN every standard kind in use THEN only what the API allows inside the place', () => {
    expect(names(levels, 'bld')).toEqual(['Shop', 'Bin'])
    expect(names(levels, 'bin')).toEqual(['Sub-bin'])
    expect(names(levels, 'sub')).toEqual([])
  })

  it('GIVEN standard kinds not used yet THEN they are offered, with no id, in the standard order', () => {
    const two = [level('fac', 'Facility', 1, 'required'), level('bin', 'Bin', 2, 'required')]
    expect(addChoices(two, 'fac')).toEqual([
      { level_id: null, level_name: 'Building' },
      { level_id: null, level_name: 'Shop' },
      { level_id: 'bin', level_name: 'Bin', level_order: 2, requirement: 'required' },
    ])
    expect(names(two, 'bin')).toEqual(['Sub-bin'])
  })

  it('GIVEN a kind in between that is always asked THEN nothing below it is offered', () => {
    const three = [
      level('fac', 'Facility', 1, 'required'),
      level('bld', 'Building', 2, 'required'),
      level('bin', 'Bin', 3, 'optional'),
    ]
    // Shop and Bin go inside a facility only through a building; Sub-bin may skip Bin.
    expect(names(three, 'fac')).toEqual(['Building'])
    expect(names(three, 'bld')).toEqual(['Shop', 'Bin', 'Sub-bin'])
  })

  it('GIVEN kinds typed earlier, or a standard name that is off THEN no new kind is offered', () => {
    const typed = [level('c', 'city', 1, 'required'), level('b', 'bin number', 2, 'required')]
    expect(names(typed, 'c')).toEqual(['bin number'])
    const withOff = [
      level('fac', 'Facility', 1, 'required'),
      level('shp', 'Shop', 2, 'off'),
      level('bin', 'Bin', 3, 'required'),
    ]
    expect(names(withOff, 'fac')).toEqual(['Building', 'Bin'])
  })
})

describe('levelsWithKind', () => {
  it('GIVEN a new kind THEN it goes at its standard place, always asked, others unchanged', () => {
    const two = [level('fac', 'Facility', 1, 'required'), level('bin', 'Bin', 2, 'optional')]
    expect(levelsWithKind(two, 'Shop')).toEqual([
      { level_id: 'fac', level_name: 'Facility', requirement: 'required' },
      { level_id: null, level_name: 'Shop', requirement: 'required' },
      { level_id: 'bin', level_name: 'Bin', requirement: 'optional' },
    ])
    expect(levelsWithKind(two, 'Sub-bin').map((l) => l.level_name)).toEqual([
      'Facility',
      'Bin',
      'Sub-bin',
    ])
  })
})

describe('unusedAfterDelete', () => {
  it('GIVEN a branch deleted THEN the kinds only it used are named', () => {
    // Paint Shop is the only shop; its Bin 2 is not the only bin (Bin 10 stays).
    expect(unusedAfterDelete(levels, nodes, 's').map((l) => l.level_name)).toEqual(['Shop'])
    expect(unusedAfterDelete(levels, nodes, 'b2')).toEqual([])
    expect(unusedAfterDelete(levels, nodes, 'a').map((l) => l.level_name)).toEqual(['Shop', 'Bin'])
  })
})

describe('placesSkipping', () => {
  it('GIVEN a bin straight inside a building THEN Shop is skipped by that building', () => {
    expect(placesSkipping(levels, nodes, 'shp')).toBe(1)
    expect(placesSkipping(levels, nodes, 'bin')).toBe(0)
    expect(placesSkipping(levels, nodes, 'bld')).toBe(0)
  })
})

describe('typedNames', () => {
  it('GIVEN commas and spare spaces THEN one tidy name each', () => {
    expect(typedNames(' Bin  01 , Bin 02,, ')).toEqual(['Bin 01', 'Bin 02'])
    expect(typedNames('   ')).toEqual([])
  })

  it('GIVEN a range THEN one name per number, keeping the width', () => {
    expect(typedNames('Bin 05-08')).toEqual(['Bin 05', 'Bin 06', 'Bin 07', 'Bin 08'])
    expect(typedNames('Bay 9 – 11, Dock')).toEqual(['Bay 09', 'Bay 10', 'Bay 11', 'Dock'])
  })

  it('GIVEN a reversed or one-number range THEN it stays one name', () => {
    expect(typedNames('Line 9-3')).toEqual(['Line 9-3'])
    expect(typedNames('Line 4-4')).toEqual(['Line 4-4'])
  })

  it('GIVEN a range over the limit THEN more than MAX_NAMES come back, never thousands', () => {
    expect(typedNames('Bin 1-51')).toHaveLength(MAX_NAMES + 1)
    expect(typedNames('Bin 1-900000')).toHaveLength(MAX_NAMES + 1)
  })
})
