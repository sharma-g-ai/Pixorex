import { fireEvent, render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import type { Level } from '../../api/locations'
import { SetupGuide } from './SetupGuide'

const guide = (levels: Level[] = [], onCreate = vi.fn()) => {
  render(
    <SetupGuide
      levels={levels}
      siteName="Plant 04"
      busy={false}
      error={null}
      onCreate={onCreate}
    />,
  )
  return onCreate
}
const type = (label: string, value: string) =>
  fireEvent.change(screen.getByLabelText(label), { target: { value } })
const click = (name: string) => fireEvent.click(screen.getByRole('button', { name }))

describe('Guided setup on one screen (plan R1–R3)', () => {
  it('GIVEN a new unit THEN it starts from the site name, with room for one smaller part', () => {
    guide()
    expect(screen.getByLabelText('Place 1')).toHaveValue('Plant 04')
    expect(screen.getByLabelText('Place 2')).toHaveValue('')
    expect(screen.queryByRole('button', { name: 'Next' })).not.toBeInTheDocument()
  })

  it('GIVEN a kind THEN it is picked from the standard menu, not typed', () => {
    guide()
    const kind = screen.getByLabelText('Kind 2')
    expect(kind.tagName).toBe('SELECT')
    expect(
      within(kind)
        .getAllByRole('option')
        .map((o) => o.textContent),
    ).toEqual(['Choose a kind', 'Facility', 'Building', 'Shop', 'Bin', 'Sub-bin'])
  })

  it('GIVEN empty boxes WHEN Create THEN nothing is sent and it says which (R2)', () => {
    const onCreate = guide()
    click('Create and add more places')
    expect(screen.getByText('Part 2: type the place.')).toBeInTheDocument()
    expect(screen.getByText('Part 1: choose its kind.')).toBeInTheDocument()
    expect(onCreate).not.toHaveBeenCalled()
  })

  it('GIVEN smaller parts added and one removed THEN the places keep their order', () => {
    guide()
    type('Place 2', 'Building C')
    click('+ Add a smaller part')
    type('Place 3', 'Bin 07')
    click('+ Add a smaller part')
    click('Remove place 4')
    expect(screen.queryByLabelText('Place 4')).not.toBeInTheDocument()
    expect(screen.getByLabelText('Place 3')).toHaveValue('Bin 07')
    expect(screen.getByRole('button', { name: 'Remove place 1' })).toBeDisabled()
  })

  it('GIVEN a common setup picked WHEN Create THEN the parts are sent', () => {
    const onCreate = guide()
    type('Place 2', 'Building C')
    click('+ Add a smaller part')
    type('Place 3', 'Bin 07')
    click('Facility › Building › Bin')
    fireEvent.click(screen.getByLabelText(/Not every Facility has a Building/))
    expect(screen.getByLabelText(/Not every Building has a Bin/)).not.toBeChecked()
    click('Create and add more places')
    expect(onCreate).toHaveBeenCalledWith([
      { place: 'Plant 04', kind: 'Facility', optional: false, level_id: null },
      { place: 'Building C', kind: 'Building', optional: true, level_id: null },
      { place: 'Bin 07', kind: 'Bin', optional: false, level_id: null },
    ])
  })

  it('GIVEN the same kind twice WHEN Create THEN nothing is sent and it says why (R3)', () => {
    const onCreate = guide()
    type('Place 2', 'Bin 07')
    type('Kind 1', 'Bin')
    type('Kind 2', 'Bin')
    click('Create and add more places')
    expect(
      screen.getByText('Each kind needs its own name: "Bin" is used twice.'),
    ).toBeInTheDocument()
    expect(onCreate).not.toHaveBeenCalled()
  })

  it('GIVEN kinds saved earlier under another name THEN that name stays on the menu', () => {
    guide([
      { level_id: 'fac', level_name: 'Plant', level_order: 1, requirement: 'required' },
      { level_id: 'bin', level_name: 'Bin', level_order: 2, requirement: 'required' },
    ])
    expect(screen.getByLabelText('Kind 1')).toHaveValue('Plant')
    expect(screen.getByLabelText('Kind 2')).toHaveValue('Bin')
  })

  it('GIVEN a 5-part place WHEN its common setup is picked THEN the last kind stays optional', () => {
    const onCreate = guide()
    for (const [i, place] of ['B', 'S', 'Bin 1', 'Sub 1'].entries()) {
      if (i > 0) click('+ Add a smaller part')
      type(`Place ${i + 2}`, place)
    }
    click('Facility › Building › Shop › Bin › Sub-bin')
    click('Create and add more places')
    expect(onCreate.mock.calls[0]?.[0].map((p: { optional: boolean }) => p.optional)).toEqual([
      false,
      false,
      true,
      false,
      true,
    ])
  })
})
