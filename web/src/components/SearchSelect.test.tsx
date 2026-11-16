import { fireEvent, render, screen } from '@testing-library/react'
import { useState } from 'react'
import { describe, expect, it } from 'vitest'
import { SearchSelect } from './SearchSelect'

const PEOPLE = Array.from({ length: 40 }, (_, i) => ({
  value: `u${i}`,
  label: i === 7 ? 'Tara Demo' : `Technician ${i}`,
  hint: `${i} open`,
}))

function Harness({ onPick }: { onPick?: (v: string | null) => void }) {
  const [value, setValue] = useState<string | null>(null)
  return (
    <SearchSelect
      label="Technician"
      options={PEOPLE}
      value={value}
      onChange={(v) => {
        setValue(v)
        onPick?.(v)
      }}
    />
  )
}
const box = () => screen.getByRole('combobox', { name: 'Technician' })

describe('SearchSelect', () => {
  it('GIVEN 40 options WHEN nothing is typed THEN no list is shown', () => {
    render(<Harness />)
    expect(screen.queryByRole('listbox')).not.toBeInTheDocument()
    expect(screen.queryAllByRole('option')).toHaveLength(0)
  })

  it('GIVEN a name part WHEN typed THEN only matches are listed, at most 6', () => {
    render(<Harness />)
    fireEvent.change(box(), { target: { value: 'tara' } })
    expect(screen.getAllByRole('option')).toHaveLength(1)
    fireEvent.change(box(), { target: { value: 'Technician' } })
    expect(screen.getAllByRole('option')).toHaveLength(6)
    expect(screen.getByText(/more — keep typing/)).toBeInTheDocument()
    fireEvent.change(box(), { target: { value: 'zzz' } })
    expect(screen.getByText(/No match for/)).toBeInTheDocument()
  })

  it('GIVEN a match WHEN clicked THEN it is the one picked and Change clears it', () => {
    const picks: (string | null)[] = []
    render(<Harness onPick={(v) => picks.push(v)} />)
    fireEvent.change(box(), { target: { value: 'tara' } })
    fireEvent.click(screen.getByRole('option', { name: /Tara Demo/ }))
    expect(picks).toEqual(['u7'])
    expect(screen.queryByRole('combobox')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Change technician' }))
    expect(picks).toEqual(['u7', null])
    expect(box()).toBeInTheDocument()
  })

  it('GIVEN the keyboard WHEN arrow and Enter are pressed THEN the highlighted match is picked', () => {
    const picks: (string | null)[] = []
    render(<Harness onPick={(v) => picks.push(v)} />)
    fireEvent.change(box(), { target: { value: 'Technician 1' } })
    fireEvent.keyDown(box(), { key: 'ArrowDown' })
    fireEvent.keyDown(box(), { key: 'Enter' })
    expect(picks).toHaveLength(1)
  })
})
