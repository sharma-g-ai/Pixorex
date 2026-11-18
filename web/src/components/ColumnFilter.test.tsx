import { fireEvent, render, screen, within } from '@testing-library/react'
import { useState } from 'react'
import { describe, expect, it, vi } from 'vitest'
import {
  CheckListFilter,
  ColumnFilter,
  DateRangeFilter,
  FilterChips,
  SortToggle,
  type DayRange,
} from './ColumnFilter'
import { listChip, rangeChip } from './filterChips'

const options = [
  { value: 'a', label: 'Anita Rao' },
  { value: 'r', label: 'Ravi Kumar' },
  { value: 's', label: 'Sunil Das' },
]

function Checks({ searchable = false }: { searchable?: boolean }) {
  const [selected, setSelected] = useState<string[]>([])
  return (
    <>
      <ColumnFilter label="Captured by" active={selected.length > 0}>
        {(close) => (
          <CheckListFilter
            title="Captured by"
            options={options}
            selected={selected}
            onChange={setSelected}
            onDone={close}
            searchable={searchable}
          />
        )}
      </ColumnFilter>
      <output aria-label="picked">{selected.join(',')}</output>
    </>
  )
}

const funnel = () => screen.getByRole('button', { name: 'Filter by Captured by' })

describe('ColumnFilter', () => {
  it('GIVEN the funnel WHEN clicked THEN opens a dialog and says it is expanded', () => {
    render(<Checks />)
    expect(funnel()).toHaveAttribute('aria-expanded', 'false')
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    fireEvent.click(funnel())
    expect(funnel()).toHaveAttribute('aria-expanded', 'true')
    expect(screen.getByRole('dialog', { name: 'Captured by filter' })).toBeInTheDocument()
  })

  it('GIVEN several choices WHEN some are ticked THEN they are kept and the funnel turns on', () => {
    render(<Checks />)
    expect(funnel()).not.toHaveAttribute('data-active')
    fireEvent.click(funnel())
    fireEvent.click(screen.getByRole('checkbox', { name: 'Ravi Kumar' }))
    fireEvent.click(screen.getByRole('checkbox', { name: 'Sunil Das' }))
    expect(screen.getByLabelText('picked')).toHaveTextContent('r,s')
    expect(funnel()).toHaveAttribute('data-active', 'true')
    fireEvent.click(screen.getByRole('checkbox', { name: 'Ravi Kumar' }))
    expect(screen.getByLabelText('picked')).toHaveTextContent('s')
  })

  it('GIVEN ticked choices WHEN Clear is pressed THEN nothing is ticked (no filter)', () => {
    render(<Checks />)
    fireEvent.click(funnel())
    const clear = screen.getByRole('button', { name: 'Clear' })
    expect(clear).toBeDisabled()
    fireEvent.click(screen.getByRole('checkbox', { name: 'Anita Rao' }))
    fireEvent.click(clear)
    expect(screen.getByLabelText('picked')).toBeEmptyDOMElement()
    expect(funnel()).not.toHaveAttribute('data-active')
  })

  it('GIVEN an open panel WHEN Done, Escape or a click outside THEN it closes', () => {
    render(<Checks />)
    fireEvent.click(funnel())
    fireEvent.click(screen.getByRole('button', { name: 'Done' }))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(funnel()).toHaveFocus()

    fireEvent.click(funnel())
    fireEvent.keyDown(document, { key: 'Escape' })
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(funnel()).toHaveFocus()

    fireEvent.click(funnel())
    fireEvent.mouseDown(document.body)
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('GIVEN an open panel WHEN a click lands inside it THEN it stays open', () => {
    render(<Checks />)
    fireEvent.click(funnel())
    fireEvent.mouseDown(screen.getByRole('checkbox', { name: 'Anita Rao' }))
    expect(screen.getByRole('dialog')).toBeInTheDocument()
  })

  it('GIVEN a searchable list WHEN typing THEN only matching choices are shown', () => {
    render(<Checks searchable />)
    fireEvent.click(funnel())
    const search = screen.getByRole('searchbox', { name: 'Search Captured by' })
    fireEvent.change(search, { target: { value: 'ravi' } })
    const list = screen.getByRole('group', { name: 'Captured by' })
    expect(within(list).getAllByRole('checkbox')).toHaveLength(1)
    expect(within(list).getByRole('checkbox', { name: 'Ravi Kumar' })).toBeInTheDocument()
    fireEvent.change(search, { target: { value: 'zzz' } })
    expect(screen.getByText('Nothing found.')).toBeInTheDocument()
  })
})

function Dates({ onChange }: { onChange: (r: DayRange) => void }) {
  const [range, setRange] = useState<DayRange>({ from: '', to: '' })
  return (
    <DateRangeFilter
      title="Date"
      value={range}
      onChange={(r) => {
        setRange(r)
        onChange(r)
      }}
      onDone={() => {}}
    />
  )
}

const pick = (label: string, value: string) =>
  fireEvent.change(screen.getByLabelText(label), { target: { value } })

describe('DateRangeFilter', () => {
  it('GIVEN From and To WHEN both are picked THEN the range is reported', () => {
    const seen = vi.fn()
    render(<Dates onChange={seen} />)
    pick('From', '2026-11-12')
    pick('To', '2026-11-16')
    expect(seen).toHaveBeenLastCalledWith({ from: '2026-11-12', to: '2026-11-16' })
  })

  it('GIVEN only From THEN the To side stays open', () => {
    const seen = vi.fn()
    render(<Dates onChange={seen} />)
    pick('From', '2026-11-12')
    expect(seen).toHaveBeenLastCalledWith({ from: '2026-11-12', to: '' })
  })

  it('GIVEN a From after To WHEN picked THEN To moves with it, so the range is never backwards', () => {
    const seen = vi.fn()
    render(<Dates onChange={seen} />)
    pick('To', '2026-11-10')
    pick('From', '2026-11-14')
    expect(seen).toHaveBeenLastCalledWith({ from: '2026-11-14', to: '2026-11-14' })
  })

  it('GIVEN a To before From WHEN picked THEN From moves with it', () => {
    const seen = vi.fn()
    render(<Dates onChange={seen} />)
    pick('From', '2026-11-14')
    pick('To', '2026-11-10')
    expect(seen).toHaveBeenLastCalledWith({ from: '2026-11-10', to: '2026-11-10' })
  })

  it('GIVEN a range WHEN Clear THEN both sides are empty', () => {
    const seen = vi.fn()
    render(<Dates onChange={seen} />)
    expect(screen.getByRole('button', { name: 'Clear' })).toBeDisabled()
    pick('From', '2026-11-12')
    fireEvent.click(screen.getByRole('button', { name: 'Clear' }))
    expect(seen).toHaveBeenLastCalledWith({ from: '', to: '' })
  })
})

describe('SortToggle', () => {
  it('GIVEN oldest first THEN says so, offers newest first and reports the click', () => {
    const toggle = vi.fn()
    render(<SortToggle label="Date" direction="oldest_first" onToggle={toggle} />)
    fireEvent.click(
      screen.getByRole('button', { name: 'Sort by Date, oldest first. Click for newest first.' }),
    )
    expect(toggle).toHaveBeenCalledOnce()
  })

  it('GIVEN newest first THEN offers oldest first', () => {
    render(<SortToggle label="Date" direction="newest_first" onToggle={() => {}} />)
    expect(
      screen.getByRole('button', { name: 'Sort by Date, newest first. Click for oldest first.' }),
    ).toBeInTheDocument()
  })
})

describe('FilterChips', () => {
  it('GIVEN no filters THEN shows nothing', () => {
    const { container } = render(<FilterChips chips={[]} onClearAll={() => {}} />)
    expect(container).toBeEmptyDOMElement()
  })

  it('GIVEN one chip THEN removes it, with no Clear all', () => {
    const remove = vi.fn()
    render(
      <FilterChips
        chips={[{ key: 'status', text: 'Status: Waiting', onRemove: remove }]}
        onClearAll={() => {}}
      />,
    )
    expect(screen.queryByRole('button', { name: 'Clear all' })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Remove filter Status: Waiting' }))
    expect(remove).toHaveBeenCalledOnce()
  })

  it('GIVEN two chips THEN offers Clear all', () => {
    const clearAll = vi.fn()
    render(
      <FilterChips
        chips={[
          { key: 'a', text: 'A', onRemove: () => {} },
          { key: 'b', text: 'B', onRemove: () => {} },
        ]}
        onClearAll={clearAll}
      />,
    )
    fireEvent.click(screen.getByRole('button', { name: 'Clear all' }))
    expect(clearAll).toHaveBeenCalledOnce()
  })
})

describe('chip text', () => {
  it('lists up to two choices and counts more', () => {
    expect(listChip('Schema', ['pump label'])).toBe('Schema: pump label')
    expect(listChip('Schema', ['a', 'b'])).toBe('Schema: a, b')
    expect(listChip('Schema', ['a', 'b', 'c'])).toBe('Schema: 3 selected')
  })

  it('writes a range with either side open', () => {
    expect(rangeChip('Date', { from: '2026-11-12', to: '2026-11-16' })).toBe(
      'Date: 12 Nov – 16 Nov',
    )
    expect(rangeChip('Date', { from: '2026-11-12', to: '' })).toBe('Date: from 12 Nov')
    expect(rangeChip('Date', { from: '', to: '2026-11-16' })).toBe('Date: until 16 Nov')
  })
})
