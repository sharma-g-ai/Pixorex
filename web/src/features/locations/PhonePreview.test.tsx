import { render, screen, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import type { Level, LocationNode } from '../../api/locations'
import { PhonePreview } from './PhonePreview'

const levels: Level[] = [
  { level_id: 'fac', level_name: 'Plant', level_order: 1, requirement: 'required' },
  { level_id: 'shp', level_name: 'Shop', level_order: 2, requirement: 'optional' },
  { level_id: 'bin', level_name: 'Bin', level_order: 3, requirement: 'required' },
]
const node = (id: string, name: string, levelId: string, parent: string | null): LocationNode => ({
  node_id: id,
  name,
  level_id: levelId,
  parent_id: parent,
  is_placeholder: false,
  child_count: 0,
})
const nodes = [node('f', 'Plant 04', 'fac', null), node('b', 'Bin 07', 'bin', 'f')]
const phone = () => within(screen.getByRole('region', { name: "On the technician's phone" }))

describe('Phone preview (plan R7)', () => {
  it('GIVEN a bin THEN one pick per kind below the top, a skipped kind, the path, scannable', () => {
    render(<PhonePreview levels={levels} nodes={nodes} nodeId="b" />)
    expect(phone().getByText('Shop')).toBeInTheDocument()
    expect(phone().getByText('Skipped')).toBeInTheDocument()
    expect(phone().getByText('Bin 07')).toBeInTheDocument()
    expect(phone().getByText('Plant 04 › Bin 07')).toBeInTheDocument()
    expect(phone().getByText('Technicians can place a scan here.')).toBeInTheDocument()
  })

  it('GIVEN the top place THEN it says technicians pick further down', () => {
    render(<PhonePreview levels={levels} nodes={nodes} nodeId="f" />)
    expect(phone().getByText(/pick a place further down/)).toBeInTheDocument()
  })

  it('GIVEN nothing selected THEN it says how to preview', () => {
    render(<PhonePreview levels={levels} nodes={nodes} nodeId={null} />)
    expect(phone().getByText(/Pick a place in the list/)).toBeInTheDocument()
  })
})
