import { describe, expect, it } from 'vitest'
import type { Level, LocationNode } from '../../api/locations'
import {
  childLevels,
  countsByLevel,
  descendantCount,
  filterRows,
  moveTargets,
  rangeNames,
  treeRows,
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

describe('rangeNames', () => {
  it('keeps the width of the numbers', () => {
    expect(rangeNames('Bin ', '05', '08')).toEqual(['Bin 05', 'Bin 06', 'Bin 07', 'Bin 08'])
  })

  it('refuses ranges over 50, reversed or not numeric', () => {
    expect(rangeNames('Bin ', '1', '51')).toBeNull()
    expect(rangeNames('Bin ', '9', '3')).toBeNull()
    expect(rangeNames('Bin ', 'a', '3')).toBeNull()
  })
})
